# (c) 2026 Holger Imbery (contact@holgerimbery.blog)
# Licensed under the project LICENSE file.

param(
    [string]$ResourceGroup,
    [string]$AppServiceName,
    [string]$Location = "eastus",
    [string]$TenantId,
    [string]$SubscriptionId
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
# before any resources are created, so a stale `az login` session can't
# silently deploy into the wrong tenant/subscription.
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

# App Service (and the compute/networking/storage behind it) needs these
# resource providers registered on the subscription before any resource can
# be created. A subscription that has never deployed a VM/Web App before -
# common for a fresh or rarely-used Visual Studio/MSDN subscription - often
# has them "NotRegistered", which surfaces as a confusing "0 quota"/"Total
# VMs: 0" error from `az appservice plan create` instead of a clear
# "provider not registered" message. Check and register upfront instead of
# waiting to hit that wall.
function Ensure-ResourceProvidersRegistered {
    param([string[]]$Namespaces)

    foreach ($ns in $Namespaces) {
        $state = az provider show --namespace $ns --query registrationState -o tsv 2>$null
        if ($state -eq "Registered") {
            continue
        }

        Write-Host "  Registering resource provider '$ns' (current state: $state)..." -ForegroundColor Yellow
        az provider register --namespace $ns -o none
        if ($LASTEXITCODE -ne 0) {
            Write-Warning "Failed to request registration for '$ns'. If resource creation below fails, register it manually: az provider register --namespace $ns"
            continue
        }

        $maxWaitSeconds = 180
        $waited = 0
        while ($state -ne "Registered" -and $waited -lt $maxWaitSeconds) {
            Start-Sleep -Seconds 10
            $waited += 10
            $state = az provider show --namespace $ns --query registrationState -o tsv 2>$null
        }

        if ($state -eq "Registered") {
            Write-Host "  [OK] '$ns' registered" -ForegroundColor Green
        } else {
            Write-Warning "'$ns' is still '$state' after ${maxWaitSeconds}s. Registration can take longer for brand-new subscriptions - wait a few minutes and re-run this script, or check status with: az provider show --namespace $ns --query registrationState -o tsv"
        }
    }
}

$env_file = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) ".env"
if (Test-Path $env_file) {
    $env_vars = Load-EnvFile $env_file
    if (-not $ResourceGroup) { $ResourceGroup = $env_vars['RESOURCE_GROUP'] }
    if (-not $AppServiceName) { $AppServiceName = $env_vars['APP_SERVICE_NAME'] }
    if ($Location -eq "eastus" -and $env_vars['LOCATION']) { $Location = $env_vars['LOCATION'] }
    if (-not $TenantId) { $TenantId = $env_vars['TENANT_ID'] }
    if (-not $SubscriptionId) { $SubscriptionId = $env_vars['AZURE_SUBSCRIPTION_ID'] }
}

# Validate
if (-not $ResourceGroup -or -not $AppServiceName) {
    Write-Error "Missing required parameters: ResourceGroup, AppServiceName"
    Write-Host "Provide via CLI parameters or .env file in the repo root" -ForegroundColor Yellow
    exit 1
}

Write-Host "Creating Azure App Service..." -ForegroundColor Yellow

Confirm-AzureContext -ExpectedTenantId $TenantId -ExpectedSubscriptionId $SubscriptionId

Write-Host "Checking required resource providers are registered..." -ForegroundColor Yellow
Ensure-ResourceProvidersRegistered -Namespaces @("Microsoft.Compute", "Microsoft.Web", "Microsoft.Network", "Microsoft.Storage")

# Create resource group
az group create --name $ResourceGroup --location $Location
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create resource group '$ResourceGroup'. See az CLI output above for details."
    exit 1
}
Write-Host "✓ Resource group created: $ResourceGroup" -ForegroundColor Green

# Create App Service plan. A B1 plan needs regional vCPU quota that many
# subscriptions (especially free/trial/dev-test ones) start out at zero for,
# so a first attempt can fail with "insufficient regional vCPU quota" even
# though everything else (resource group, permissions) is fine. Rather than
# aborting the whole onboarding run on that single external quota limit,
# offer to retry interactively with a different region - most subscriptions
# have quota for at least one of eastus/westus2/westeurope.
$PlanLocation = $Location
$PlanSku = "B1"
$PlanCreated = $false
$MaxAttempts = 3
for ($Attempt = 1; $Attempt -le $MaxAttempts; $Attempt++) {
    az appservice plan create `
        --resource-group $ResourceGroup `
        --name "$AppServiceName-plan" `
        --sku $PlanSku `
        --location $PlanLocation `
        --is-linux

    if ($LASTEXITCODE -eq 0) {
        $PlanCreated = $true
        break
    }

    Write-Warning "Failed to create App Service plan '$AppServiceName-plan' (sku=$PlanSku, location=$PlanLocation)."
    Write-Host "  Common cause: insufficient regional vCPU quota for this SKU/region in the current subscription." -ForegroundColor Yellow
    Write-Host "  Option A - request a quota increase: https://aka.ms/ProdportalCRP/#blade/Microsoft_Azure_Capacity/UsageAndQuota.ReactView (Compute-VM (cores-vCPUs) subscription limit increases)" -ForegroundColor Gray
    Write-Host "  Option B - switch Azure subscription (menu: re-run onboarding.ps1 and pick a different subscription index) if another one has spare quota." -ForegroundColor Gray
    Write-Host "  Option C - retry now with a different region." -ForegroundColor Gray

    if ($Attempt -eq $MaxAttempts) { break }
    $RetryChoice = Read-Host "Retry with a different region now? (y/n) [n]"
    if ($RetryChoice -ne 'y') { break }

    $NewLocation = Read-Host "Azure region to try [$PlanLocation]"
    if ($NewLocation) { $PlanLocation = $NewLocation }
}

if (-not $PlanCreated) {
    Write-Error "Failed to create App Service plan '$AppServiceName-plan' after $Attempt attempt(s). See az CLI output above for details."
    exit 1
}
if ($PlanLocation -ne $Location) {
    Write-Host "  Note: the plan was created in '$PlanLocation' instead of '$Location'. Update LOCATION=$PlanLocation in .env so later steps (and future runs) stay consistent." -ForegroundColor Yellow
}
Write-Host "✓ App Service plan created" -ForegroundColor Green

# Create web app
az webapp create `
    --resource-group $ResourceGroup `
    --plan "$AppServiceName-plan" `
    --name $AppServiceName `
    --runtime "PYTHON:3.11"

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to create App Service '$AppServiceName'. See az CLI output above for details."
    exit 1
}
$Url = "https://$AppServiceName.azurewebsites.net"
Write-Host "✓ App Service created: $Url" -ForegroundColor Green
