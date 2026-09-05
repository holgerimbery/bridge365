# (c) 2026 Holger Imbery (contact@holgerimbery.blog)
# Licensed under the project LICENSE file.
# Generates the real (gitignored) custom-connector/openapi.yaml from
# custom-connector/openapi.template.yaml by substituting __BACKEND_HOST__
# with your actual backend App Service hostname. Run this before importing
# openapi.yaml manually in the Power Platform portal (README.md, Step 2);
# deploy-connector.ps1 calls this automatically for the CLI path.

param(
    [string]$BackendHost,
    [string]$Template,
    [string]$OutputPath
)

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

$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$env_file = Join-Path $RepoRoot ".env"

if (-not $BackendHost -and (Test-Path $env_file)) {
    $env_vars = Load-EnvFile $env_file
    if ($env_vars['BACKEND_URL']) {
        $BackendHost = $env_vars['BACKEND_URL'] -replace '^https?://', '' -replace '/$', ''
    } elseif ($env_vars['APP_SERVICE_NAME']) {
        $BackendHost = "$($env_vars['APP_SERVICE_NAME']).azurewebsites.net"
    }
}

if (-not $BackendHost) {
    Write-Error "Could not determine backend host. Provide -BackendHost, or set BACKEND_URL or APP_SERVICE_NAME in .env."
    exit 1
}

if (-not $Template) { $Template = Join-Path $RepoRoot "custom-connector\openapi.template.yaml" }
if (-not $OutputPath) { $OutputPath = Join-Path $RepoRoot "custom-connector\openapi.yaml" }

if (-not (Test-Path $Template)) {
    Write-Error "Template not found at '$Template'."
    exit 1
}

$content = Get-Content $Template -Raw
$content = $content.Replace('__BACKEND_HOST__', $BackendHost)
Set-Content -Path $OutputPath -Value $content -NoNewline

Write-Host "Generated '$OutputPath' with host '$BackendHost'." -ForegroundColor Green