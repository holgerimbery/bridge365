# (c) 2026 Holger Imbery (contact@holgerimbery.blog)
# Licensed under the project LICENSE file.
# Verifies the Azure App Service is reachable right after creation, before any
# backend code is deployed. Expect a 404 from the platform (not a connection
# error) - that confirms the App Service itself is up.

param(
    [string]$BackendUrl
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
    if (-not $BackendUrl) { $BackendUrl = $env_vars['BACKEND_URL'] }
}

# Validate
if (-not $BackendUrl) {
    Write-Error "Missing required parameter: BackendUrl"
    Write-Host "Provide via CLI parameter or .env file in the repo root" -ForegroundColor Yellow
    exit 1
}

# Test connectivity
$Response = Invoke-WebRequest -Uri "$BackendUrl/health" -SkipHttpErrorCheck

Write-Host "Status Code: $($Response.StatusCode)" -ForegroundColor Green
Write-Host "Response: $($Response.Content)" -ForegroundColor Gray
