# (c) 2026 Holger Imbery (contact@holgerimbery.blog)
# Licensed under the project LICENSE file.
# Stores the app registration client secret in Key Vault and wires the
# App Service to read it via a Key Vault reference, instead of storing
# the plaintext secret directly in application settings.

param(
    [string]$ResourceGroup,
    [string]$KeyVaultName,
    [string]$AppServiceName,
    [string]$ClientSecret
)

# Load from .env if parameters not provided
function Load-EnvFile {
    param([string]$EnvPath)
    $env_vars = @{}
    if (Test-Path $EnvPath) {
        Get-Content $EnvPath | Where-Object { $_ -match '=' -and -not $_.StartsWith('#') } | ForEach-Object {
            $key, $value = $_ -split '=', 2
            $env_vars[$key.Trim()] = $value.Trim()
        }
    }
    return $env_vars
}

$env_file = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) ".env"
if (Test-Path $env_file) {
    $env_vars = Load-EnvFile $env_file
    if (-not $ResourceGroup) { $ResourceGroup = $env_vars['RESOURCE_GROUP'] }
    if (-not $KeyVaultName) { $KeyVaultName = $env_vars['KEY_VAULT_NAME'] }
    if (-not $AppServiceName) { $AppServiceName = $env_vars['APP_SERVICE_NAME'] }
    if (-not $ClientSecret) { $ClientSecret = $env_vars['CLIENT_SECRET'] }
}

# Validate
if (-not $ResourceGroup -or -not $KeyVaultName -or -not $AppServiceName -or -not $ClientSecret) {
    Write-Error "Missing required parameters: ResourceGroup, KeyVaultName, AppServiceName, ClientSecret"
    Write-Host "Provide via CLI parameters or .env file in the repo root" -ForegroundColor Yellow
    exit 1
}

# Create Key Vault if it doesn't already exist
az keyvault create --resource-group $ResourceGroup --name $KeyVaultName --location "westeurope" 2>$null

# Store the secret
az keyvault secret set --vault-name $KeyVaultName --name "AzureClientSecret" --value $ClientSecret | Out-Null

# Grant the App Service managed identity access to read secrets
az webapp identity assign --resource-group $ResourceGroup --name $AppServiceName | Out-Null
$PrincipalId = az webapp identity show --resource-group $ResourceGroup --name $AppServiceName --query principalId -o tsv

az keyvault set-policy --name $KeyVaultName --object-id $PrincipalId --secret-permissions get list | Out-Null

# Point the app setting to the Key Vault reference instead of the raw value
az webapp config appsettings set `
    --resource-group $ResourceGroup `
    --name $AppServiceName `
    --settings AZURE_CLIENT_SECRET="@Microsoft.KeyVault(VaultName=$KeyVaultName;SecretName=AzureClientSecret)"

Write-Host "Client secret moved to Key Vault: $KeyVaultName" -ForegroundColor Green
