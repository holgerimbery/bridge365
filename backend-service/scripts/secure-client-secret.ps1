# (c) 2026 Holger Imbery (contact@holgerimbery.blog)
# Licensed under the project LICENSE file.
# Stores the app registration client secret in Key Vault and wires the
# App Service to read it via a Key Vault reference, instead of storing
# the plaintext secret directly in application settings.

param(
    [string]$ResourceGroup,
    [string]$KeyVaultName,
    [string]$AppServiceName,
    [string]$ClientSecret,
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
# before any resources are created or modified, so a stale `az login`
# session can't silently target the wrong tenant/subscription.
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
    if (-not $KeyVaultName) { $KeyVaultName = $env_vars['KEY_VAULT_NAME'] }
    if (-not $AppServiceName) { $AppServiceName = $env_vars['APP_SERVICE_NAME'] }
    if (-not $ClientSecret) { $ClientSecret = $env_vars['CLIENT_SECRET'] }
    if (-not $TenantId) { $TenantId = $env_vars['TENANT_ID'] }
    if (-not $SubscriptionId) { $SubscriptionId = $env_vars['AZURE_SUBSCRIPTION_ID'] }
}

# Validate
if (-not $ResourceGroup -or -not $KeyVaultName -or -not $AppServiceName -or -not $ClientSecret) {
    Write-Error "Missing required parameters: ResourceGroup, KeyVaultName, AppServiceName, ClientSecret"
    Write-Host "Provide via CLI parameters or .env file in the repo root" -ForegroundColor Yellow
    exit 1
}

Confirm-AzureContext -ExpectedTenantId $TenantId -ExpectedSubscriptionId $SubscriptionId

# Create Key Vault if it doesn't already exist (2>$null suppresses the
# expected "already exists" error on re-runs; a real failure is still
# caught below by confirming the vault is reachable)
az keyvault create --resource-group $ResourceGroup --name $KeyVaultName --location "westeurope" 2>$null
az keyvault show --resource-group $ResourceGroup --name $KeyVaultName | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Key Vault '$KeyVaultName' does not exist and could not be created. See az CLI output above for details."
    exit 1
}

# Store the secret
az keyvault secret set --vault-name $KeyVaultName --name "AzureClientSecret" --value $ClientSecret | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to store the secret in Key Vault '$KeyVaultName'. See az CLI output above for details."
    exit 1
}

# Grant the App Service managed identity access to read secrets
az webapp identity assign --resource-group $ResourceGroup --name $AppServiceName | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to assign a managed identity to '$AppServiceName'. See az CLI output above for details."
    exit 1
}
$PrincipalId = az webapp identity show --resource-group $ResourceGroup --name $AppServiceName --query principalId -o tsv
if ($LASTEXITCODE -ne 0 -or -not $PrincipalId) {
    Write-Error "Failed to read the managed identity principal ID for '$AppServiceName'. See az CLI output above for details."
    exit 1
}

az keyvault set-policy --name $KeyVaultName --object-id $PrincipalId --secret-permissions get list | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to grant '$AppServiceName' access to Key Vault '$KeyVaultName'. See az CLI output above for details."
    exit 1
}

# Point the app setting to the Key Vault reference instead of the raw value
az webapp config appsettings set `
    --resource-group $ResourceGroup `
    --name $AppServiceName `
    --settings AZURE_CLIENT_SECRET="@Microsoft.KeyVault(VaultName=$KeyVaultName;SecretName=AzureClientSecret)"

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to point '$AppServiceName' at the Key Vault reference. See az CLI output above for details."
    exit 1
}
Write-Host "Client secret moved to Key Vault: $KeyVaultName" -ForegroundColor Green
