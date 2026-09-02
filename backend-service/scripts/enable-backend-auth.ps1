# (c) 2026 Holger Imbery (contact@holgerimbery.blog)
# Licensed under the project LICENSE file.
# Enables Azure App Service built-in authentication (Easy Auth) with
# Microsoft Entra ID as the identity provider, so unauthenticated
# requests are rejected before they reach your application code.

param(
    [string]$ResourceGroup,
    [string]$AppServiceName,
    [string]$TenantId,
    [string]$ClientId
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
    if (-not $AppServiceName) { $AppServiceName = $env_vars['APP_SERVICE_NAME'] }
    if (-not $TenantId) { $TenantId = $env_vars['TENANT_ID'] }
    if (-not $ClientId) { $ClientId = $env_vars['CLIENT_ID'] }
}

# Validate
if (-not $ResourceGroup -or -not $AppServiceName -or -not $TenantId -or -not $ClientId) {
    Write-Error "Missing required parameters: ResourceGroup, AppServiceName, TenantId, ClientId"
    Write-Host "Provide via CLI parameters or .env file in the repo root" -ForegroundColor Yellow
    exit 1
}

az webapp auth update `
    --resource-group $ResourceGroup `
    --name $AppServiceName `
    --enabled true `
    --action LoginWithAzureActiveDirectory `
    --aad-client-id $ClientId `
    --aad-token-issuer-url "https://sts.windows.net/$TenantId/"

Write-Host "Entra authentication enabled for $AppServiceName" -ForegroundColor Green
