# (c) 2026 Holger Imbery (contact@holgerimbery.blog)
# Licensed under the project LICENSE file.
# Creates or updates the SharedMailboxConnector Power Platform custom connector
# from openapi.yaml + apiProperties.template.json via the paconn CLI, so the
# connector can be deployed/updated from the command line instead of the
# Power Platform portal wizard (see docs/wiki/phase-1-mailbox-setup.md, Section 5).
#
# Requires: Python 3.5+ and `pip install paconn`, and a one-time interactive
# `paconn login` (device-code flow; no service-principal support today).
#
# First run (no -ConnectorId): creates a new connector and prints its ID -
# save that ID (e.g. into .env as CUSTOM_CONNECTOR_ID) to update it later.
# Subsequent runs (-ConnectorId supplied): updates the existing connector.

param(
    [string]$EnvironmentId,
    [string]$TenantId,
    [string]$ClientId,
    [string]$ClientSecret,
    [string]$ConnectorId,
    [string]$ApiDefinition,
    [string]$ApiPropertiesTemplate,
    [string]$IconPath
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

$RepoRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
$env_file = Join-Path $RepoRoot ".env"
if (Test-Path $env_file) {
    $env_vars = Load-EnvFile $env_file
    if (-not $EnvironmentId) { $EnvironmentId = $env_vars['POWER_PLATFORM_ENVIRONMENT_ID'] }
    if (-not $TenantId) { $TenantId = $env_vars['TENANT_ID'] }
    if (-not $ClientId) { $ClientId = $env_vars['CLIENT_ID'] }
    if (-not $ClientSecret) { $ClientSecret = $env_vars['CLIENT_SECRET'] }
    if (-not $ConnectorId) { $ConnectorId = $env_vars['CUSTOM_CONNECTOR_ID'] }
}

if (-not $ApiDefinition) { $ApiDefinition = Join-Path $RepoRoot "custom-connector\openapi.yaml" }
if (-not $ApiPropertiesTemplate) { $ApiPropertiesTemplate = Join-Path $RepoRoot "custom-connector\apiProperties.template.json" }

# Validate
if (-not $EnvironmentId -or -not $TenantId -or -not $ClientId -or -not $ClientSecret) {
    Write-Error "Missing required parameters: EnvironmentId, TenantId, ClientId, ClientSecret"
    Write-Host "Provide via CLI parameters or .env file in the repo root (POWER_PLATFORM_ENVIRONMENT_ID, TENANT_ID, CLIENT_ID, CLIENT_SECRET)" -ForegroundColor Yellow
    exit 1
}

if (-not (Get-Command paconn -ErrorAction SilentlyContinue)) {
    Write-Error "paconn CLI not found. Install it with 'pip install paconn' (requires Python 3.5+), then run 'paconn login' once before retrying."
    exit 1
}

if (-not (Test-Path $ApiDefinition)) {
    Write-Error "API definition not found at '$ApiDefinition'."
    exit 1
}

if (-not (Test-Path $ApiPropertiesTemplate)) {
    Write-Error "API properties template not found at '$ApiPropertiesTemplate'."
    exit 1
}

# Render the template with real tenant/client IDs (not secrets - safe to
# substitute locally); the generated file is gitignored, never committed.
$GeneratedApiProperties = Join-Path $RepoRoot "custom-connector\apiProperties.json"
$templateContent = Get-Content $ApiPropertiesTemplate -Raw
$templateContent = $templateContent.Replace('__TENANT_ID__', $TenantId).Replace('__CLIENT_ID__', $ClientId)
Set-Content -Path $GeneratedApiProperties -Value $templateContent -NoNewline

$paconnArgs = @(
    '--api-def', $ApiDefinition,
    '--api-prop', $GeneratedApiProperties,
    '-e', $EnvironmentId,
    '--secret', $ClientSecret
)
if ($IconPath -and (Test-Path $IconPath)) {
    $paconnArgs += @('--icon', $IconPath)
}

if ($ConnectorId) {
    Write-Host "Updating existing connector '$ConnectorId'..." -ForegroundColor Cyan
    paconn update -c $ConnectorId @paconnArgs
} else {
    Write-Host "Creating new connector..." -ForegroundColor Cyan
    paconn create @paconnArgs
}

if ($LASTEXITCODE -ne 0) {
    Write-Error "paconn command failed. See output above for details."
    exit 1
}

if (-not $ConnectorId) {
    Write-Host "Connector created. Copy the connector ID printed above into .env as CUSTOM_CONNECTOR_ID so future runs update it instead of creating a duplicate." -ForegroundColor Green
} else {
    Write-Host "Connector '$ConnectorId' updated." -ForegroundColor Green
}