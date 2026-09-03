# (c) 2026 Holger Imbery (contact@holgerimbery.blog)
# Licensed under the project LICENSE file.
# Enforces HTTPS-only traffic and restricts inbound access to an
# allowlisted set of IP ranges (e.g. Power Platform / your office egress).

param(
    [string]$ResourceGroup,
    [string]$AppServiceName,
    [string[]]$AllowedIpRanges,
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

$env_file = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) ".env"
if (Test-Path $env_file) {
    $env_vars = Load-EnvFile $env_file
    if (-not $ResourceGroup) { $ResourceGroup = $env_vars['RESOURCE_GROUP'] }
    if (-not $AppServiceName) { $AppServiceName = $env_vars['APP_SERVICE_NAME'] }
    if (-not $AllowedIpRanges) { $AllowedIpRanges = $env_vars['ALLOWED_IP_RANGES']?.Split(',') | ForEach-Object { $_.Trim() } }
    if (-not $TenantId) { $TenantId = $env_vars['TENANT_ID'] }
    if (-not $SubscriptionId) { $SubscriptionId = $env_vars['AZURE_SUBSCRIPTION_ID'] }
}

# Validate
if (-not $ResourceGroup -or -not $AppServiceName -or -not $AllowedIpRanges) {
    Write-Error "Missing required parameters: ResourceGroup, AppServiceName, AllowedIpRanges"
    Write-Host "Provide via CLI parameters or .env file in the repo root" -ForegroundColor Yellow
    exit 1
}

Confirm-AzureContext -ExpectedTenantId $TenantId -ExpectedSubscriptionId $SubscriptionId

az webapp update --resource-group $ResourceGroup --name $AppServiceName --https-only true
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to enforce HTTPS-only on '$AppServiceName'. See az CLI output above for details."
    exit 1
}

$Priority = 100
foreach ($Range in $AllowedIpRanges) {
    az webapp config access-restriction add `
        --resource-group $ResourceGroup `
        --name $AppServiceName `
        --rule-name "Allow-$Range" `
        --action Allow `
        --ip-address $Range `
        --priority $Priority
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to add access restriction for IP range '$Range' on '$AppServiceName'. See az CLI output above for details."
        exit 1
    }
    $Priority += 10
}

Write-Host "HTTPS-only enforced and ingress restricted on $AppServiceName" -ForegroundColor Green
