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
            $env_vars[$key.Trim()] = $value.Trim().Trim('"').Trim("'")
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

$isAuthRedirect = $Response.Content -and ($Response.Content -match 'ConvergedSignIn' -or $Response.Content -match 'Sign in to your account')
if ($isAuthRedirect) {
    Write-Host "Status Code: $($Response.StatusCode) (redirected to Microsoft sign-in page)" -ForegroundColor Yellow
    Write-Host "Easy Auth (App Service Authentication) is enabled and is blocking anonymous access to /health." -ForegroundColor Yellow
    Write-Host "This confirms the App Service itself is reachable, but does not verify the deployed app is healthy." -ForegroundColor Gray
    Write-Host "To check real health once Easy Auth is on, use the Azure Portal's Log Stream/Kudu console, or temporarily allow anonymous access to /health." -ForegroundColor Gray
} else {
    Write-Host "Status Code: $($Response.StatusCode)" -ForegroundColor Green
    $content = $Response.Content
    if ($content -and $content.Length -gt 300) { $content = $content.Substring(0, 300) + "... (truncated)" }
    Write-Host "Response: $content" -ForegroundColor Gray
}
