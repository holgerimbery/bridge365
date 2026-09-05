# (c) 2026 Holger Imbery (contact@holgerimbery.blog)
# Licensed under the project LICENSE file.
# Fail-safe ZIP deployment for the Python backend to Azure App Service (Linux).
# Fixes two common causes of an endless "Starting the site..." / HTTP 502 loop:
#   1. WEBSITE_RUN_FROM_PACKAGE conflicting with SCM_DO_BUILD_DURING_DEPLOYMENT
#      (when both are set, Oryx silently skips the build and dependencies are
#      never installed, so the app crash-loops on import errors forever).
#   2. Deploying into Kudu/SCM immediately after a restart, before it has
#      finished coming back up, which surfaces as an HTTP 502 on the deploy
#      call itself.
# Also retries transient deployment failures and polls /health afterward so
# you get a clear pass/fail result instead of an ambiguous hang.

param(
    [string]$ResourceGroup,
    [string]$AppServiceName,
    [string]$TenantId,
    [string]$SubscriptionId,
    [int]$MaxDeployAttempts = 3,
    [int]$HealthCheckTimeoutSeconds = 300
)

# Load from .env if parameters not provided
function Load-EnvFile {
    param([string]$EnvPath)
    $env_vars = @{}
    if (Test-Path $EnvPath) {
        Get-Content $EnvPath | Where-Object { $_ -match '=' -and -not $_.StartsWith('#') } | ForEach-Object {
            $key, $value = $_ -split '=', 2
            $env_vars[$key.Trim()] = $value.Trim().Trim('"').Trim("'")
        }
    }
    return $env_vars
}

# Verifies (and optionally switches to) the intended Azure subscription/tenant
# before any resources are modified, so a stale `az login` session can't
# silently target the wrong tenant/subscription.
function Confirm-AzureContext {
    param(
        [string]$ExpectedTenantId,
        [string]$ExpectedSubscriptionId
    )

    if ($ExpectedSubscriptionId) {
        az account set --subscription $ExpectedSubscriptionId
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to switch to subscription '$ExpectedSubscriptionId'. Run 'az login' and verify AZURE_SUBSCRIPTION_ID, then retry."
            exit 1
        }
    }

    if ($ExpectedTenantId) {
        $CurrentTenantId = az account show --query tenantId -o tsv
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to read the current Azure CLI context. Run 'az login' and retry."
            exit 1
        }
        if ($CurrentTenantId -ne $ExpectedTenantId) {
            Write-Error "Azure CLI is logged into tenant '$CurrentTenantId', but TENANT_ID specifies '$ExpectedTenantId'. Run 'az login --tenant $ExpectedTenantId' (and 'az account set --subscription <id>' if you have access to multiple subscriptions), then retry."
            exit 1
        }
    }
}

$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$env_file = Join-Path $RepoRoot ".env"
if (Test-Path $env_file) {
    $env_vars = Load-EnvFile $env_file
    if (-not $ResourceGroup) { $ResourceGroup = $env_vars['RESOURCE_GROUP'] }
    if (-not $AppServiceName) { $AppServiceName = $env_vars['APP_SERVICE_NAME'] }
    if (-not $TenantId) { $TenantId = $env_vars['TENANT_ID'] }
    if (-not $SubscriptionId) { $SubscriptionId = $env_vars['AZURE_SUBSCRIPTION_ID'] }
}

# Validate
if (-not $ResourceGroup -or -not $AppServiceName) {
    Write-Error "Missing required parameters: ResourceGroup, AppServiceName"
    Write-Host "Provide via CLI parameters or .env file in the repo root" -ForegroundColor Yellow
    exit 1
}

Confirm-AzureContext -ExpectedTenantId $TenantId -ExpectedSubscriptionId $SubscriptionId

Write-Host "Step 1/6: Ensuring build settings do not conflict..." -ForegroundColor Yellow

# WEBSITE_RUN_FROM_PACKAGE, if present, makes Oryx skip the build step
# entirely (the ZIP runs read-only exactly as uploaded), which silently
# defeats SCM_DO_BUILD_DURING_DEPLOYMENT and leaves requirements.txt
# uninstalled. Remove it if set; ignore failure if it was never set.
az webapp config appsettings delete `
    --resource-group $ResourceGroup `
    --name $AppServiceName `
    --setting-names WEBSITE_RUN_FROM_PACKAGE 2>$null | Out-Null

az webapp config appsettings set `
    --resource-group $ResourceGroup `
    --name $AppServiceName `
    --settings SCM_DO_BUILD_DURING_DEPLOYMENT=true | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to configure SCM_DO_BUILD_DURING_DEPLOYMENT on '$AppServiceName'. See az CLI output above for details."
    exit 1
}

# Set the startup command explicitly instead of relying on Oryx auto-detect,
# so the entry point (app.py's `app` Flask object) is never ambiguous.
az webapp config set `
    --resource-group $ResourceGroup `
    --name $AppServiceName `
    --startup-file "gunicorn --bind=0.0.0.0 --timeout 600 app:app" | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to set the startup command on '$AppServiceName'. See az CLI output above for details."
    exit 1
}
Write-Host "Build settings and startup command confirmed" -ForegroundColor Green

Write-Host "Step 2/6: Restarting App Service to apply configuration..." -ForegroundColor Yellow
az webapp restart --resource-group $ResourceGroup --name $AppServiceName | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to restart '$AppServiceName'. See az CLI output above for details."
    exit 1
}
Write-Host "Restart requested" -ForegroundColor Green

Write-Host "Step 3/6: Waiting for Kudu (SCM site) to become responsive..." -ForegroundColor Yellow
$KuduUrl = "https://$AppServiceName.scm.azurewebsites.net/api/settings"
$KuduReady = $false
for ($i = 1; $i -le 12; $i++) {
    try {
        $Response = Invoke-WebRequest -Uri $KuduUrl -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        if ($Response.StatusCode -eq 200) {
            $KuduReady = $true
            break
        }
    } catch {
        # Kudu not up yet - expected right after a restart, keep polling.
    }
    Write-Host "   Kudu not ready yet, retrying in 10s... ($i/12)" -ForegroundColor Gray
    Start-Sleep -Seconds 10
}
if ($KuduReady) {
    Write-Host "Kudu is responsive" -ForegroundColor Green
} else {
    Write-Host "Kudu did not respond within 2 minutes; attempting deployment anyway" -ForegroundColor Yellow
}

Write-Host "Step 4/6: Packaging application (app.py, requirements.txt)..." -ForegroundColor Yellow
$BackendDir = Split-Path $PSScriptRoot -Parent
$ZipPath = Join-Path $RepoRoot "backend-deploy.zip"
if (Test-Path $ZipPath) { Remove-Item $ZipPath -Force }
Compress-Archive -Path (Join-Path $BackendDir "app.py"), (Join-Path $BackendDir "requirements.txt") -DestinationPath $ZipPath -Force
Write-Host "Package created: $ZipPath" -ForegroundColor Green

Write-Host "Step 5/6: Deploying application..." -ForegroundColor Yellow
$DeploySucceeded = $false
for ($Attempt = 1; $Attempt -le $MaxDeployAttempts; $Attempt++) {
    Write-Host "   Attempt $Attempt of $MaxDeployAttempts..." -ForegroundColor Gray
    az webapp deploy `
        --resource-group $ResourceGroup `
        --name $AppServiceName `
        --src-path $ZipPath `
        --type zip
    if ($LASTEXITCODE -eq 0) {
        $DeploySucceeded = $true
        break
    }
    Write-Host "   Deployment attempt $Attempt failed (often a transient Kudu 502 right after a restart)." -ForegroundColor Yellow
    if ($Attempt -lt $MaxDeployAttempts) {
        Write-Host "   Waiting 30s before retry..." -ForegroundColor Gray
        Start-Sleep -Seconds 30
    }
}

if (-not $DeploySucceeded) {
    Write-Error "Deployment failed after $MaxDeployAttempts attempts."
    Write-Host "Recent deployment log:" -ForegroundColor Yellow
    az webapp log deployment show --resource-group $ResourceGroup --name $AppServiceName
    exit 1
}
Write-Host "Deployment succeeded" -ForegroundColor Green

Write-Host "Step 6/6: Waiting for the application to become healthy..." -ForegroundColor Yellow
$HealthUrl = "https://$AppServiceName.azurewebsites.net/health"
$Deadline = (Get-Date).AddSeconds($HealthCheckTimeoutSeconds)
$Healthy = $false
while ((Get-Date) -lt $Deadline) {
    try {
        $null = Invoke-RestMethod -Uri $HealthUrl -Method Get -TimeoutSec 10 -ErrorAction Stop
        $Healthy = $true
        break
    } catch {
        Write-Host "   Waiting for app to start..." -ForegroundColor Gray
        Start-Sleep -Seconds 15
    }
}

if (-not $Healthy) {
    Write-Error "Application did not become healthy within $HealthCheckTimeoutSeconds seconds."
    Write-Host "Recent deployment log:" -ForegroundColor Yellow
    az webapp log deployment show --resource-group $ResourceGroup --name $AppServiceName
    Write-Host "Tip: run 'az webapp log tail --resource-group $ResourceGroup --name $AppServiceName' to see live runtime errors." -ForegroundColor Yellow
    exit 1
}

Write-Host "Backend deployed and healthy: https://$AppServiceName.azurewebsites.net" -ForegroundColor Green