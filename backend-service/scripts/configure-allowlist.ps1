# (c) 2026 Holger Imbery (contact@holgerimbery.blog)
# Licensed under the project LICENSE file.
# Sets the tenant and client-id allowlist your backend code checks against
# on every incoming token, in addition to Easy Auth's signature validation.

param(
    [string]$ResourceGroup,
    [string]$AppServiceName,
    [string]$AllowedTenantId,
    [string]$AllowedClientIds
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

$env_file = Join-Path (Split-Path $PSScriptRoot -Parent) ".env"
if (Test-Path $env_file) {
    $env_vars = Load-EnvFile $env_file
    if (-not $ResourceGroup) { $ResourceGroup = $env_vars['RESOURCE_GROUP'] }
    if (-not $AppServiceName) { $AppServiceName = $env_vars['APP_SERVICE_NAME'] }
    if (-not $AllowedTenantId) { $AllowedTenantId = $env_vars['ALLOWED_TENANT_ID'] }
    if (-not $AllowedClientIds) { $AllowedClientIds = $env_vars['ALLOWED_CLIENT_IDS'] }
}

# Validate
if (-not $ResourceGroup -or -not $AppServiceName -or -not $AllowedTenantId -or -not $AllowedClientIds) {
    Write-Error "Missing required parameters: ResourceGroup, AppServiceName, AllowedTenantId, AllowedClientIds"
    Write-Host "Provide via CLI parameters or .env file" -ForegroundColor Yellow
    exit 1
}

az webapp config appsettings set `
    --resource-group $ResourceGroup `
    --name $AppServiceName `
    --settings `
        ALLOWED_TENANT_ID="$AllowedTenantId" `
        ALLOWED_CLIENT_IDS="$AllowedClientIds"

Write-Host "Allowlist configured on $AppServiceName" -ForegroundColor Green
