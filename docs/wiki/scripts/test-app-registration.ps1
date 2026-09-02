# (c) 2026 Holger Imbery (contact@holgerimbery.blog)
# Licensed under the project LICENSE file.
# Test app registration credentials

param(
    [string]$ClientId,
    [string]$ClientSecret,
    [string]$TenantId
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

$RepoRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$env_file = Join-Path $RepoRoot "backend-service\.env"
if (Test-Path $env_file) {
    $env_vars = Load-EnvFile $env_file
    if (-not $ClientId) { $ClientId = $env_vars['CLIENT_ID'] }
    if (-not $ClientSecret) { $ClientSecret = $env_vars['CLIENT_SECRET'] }
    if (-not $TenantId) { $TenantId = $env_vars['TENANT_ID'] }
}

# Validate
if (-not $ClientId -or -not $ClientSecret -or -not $TenantId) {
    Write-Error "Missing required parameters: ClientId, ClientSecret, TenantId"
    Write-Host "Provide via CLI parameters or backend-service/.env file" -ForegroundColor Yellow
    exit 1
}

$TokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"

$Body = @{
    grant_type = "client_credentials"
    client_id = $ClientId
    client_secret = $ClientSecret
    scope = "https://graph.microsoft.com/.default"
}

try {
    $Response = Invoke-RestMethod -Uri $TokenUrl -Method Post -Body $Body
    Write-Host "✓ Token acquired successfully" -ForegroundColor Green
    Write-Host "  Token expires in: $($Response.expires_in) seconds" -ForegroundColor Gray
    Write-Host "  Access Token: $($Response.access_token.Substring(0, 50))..." -ForegroundColor Gray
} catch {
    Write-Host "✗ Token acquisition failed" -ForegroundColor Red
    Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
}