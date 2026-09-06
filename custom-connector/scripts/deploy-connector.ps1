# (c) 2026 Holger Imbery (contact@holgerimbery.blog)
# Licensed under the project LICENSE file.
# Creates or updates the SharedMailboxConnector Power Platform custom connector
# from openapi.template.yaml + apiProperties.template.json via the paconn CLI,
# so the connector can be deployed/updated from the command line instead of
# the Power Platform portal wizard (docs/wiki/phase-1-mailbox-setup.md,
# Section 5). openapi.template.yaml is committed (no real hostname);
# openapi.yaml (with your real backend host) is generated and gitignored.
#
# Requires: Python 3.5+ and `pip install paconn pyyaml`, and a one-time
# interactive `paconn login` (device-code flow; no service-principal support
# today). pyyaml is needed because paconn's --api-def only accepts JSON - this
# script converts the generated openapi.yaml to a gitignored JSON file for it.
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
    [string]$IconPath,
    [string]$BackendHost
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

if (-not $ApiDefinition) {
    $ApiDefinition = Join-Path $RepoRoot "custom-connector\openapi.yaml"
    # openapi.yaml is gitignored (contains your real backend hostname) and
    # generated from the committed openapi.template.yaml - regenerate it here
    # so the deploy always reflects your current .env / -BackendHost value.
    $GenerateScript = Join-Path $RepoRoot "custom-connector\scripts\generate-openapi.ps1"
    # Must be a hashtable, not an array: splatting an array (@('-BackendHost',
    # $BackendHost)) passes its elements as POSITIONAL arguments, not named
    # ones - the literal string '-BackendHost' would bind to generate-openapi.ps1's
    # first parameter ($BackendHost) and the real hostname would bind to its
    # second parameter ($Template), causing a confusing "Template not found"
    # error instead of ever touching the backend host.
    $generateArgs = @{}
    if ($BackendHost) { $generateArgs['BackendHost'] = $BackendHost }
    & $GenerateScript @generateArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to generate openapi.yaml. Provide -BackendHost, or set BACKEND_URL/APP_SERVICE_NAME in .env."
        exit 1
    }
}
if (-not $ApiPropertiesTemplate) { $ApiPropertiesTemplate = Join-Path $RepoRoot "custom-connector\apiProperties.template.json" }

# Validate
if (-not $EnvironmentId -or -not $TenantId -or -not $ClientId -or -not $ClientSecret) {
    Write-Error "Missing required parameters: EnvironmentId, TenantId, ClientId, ClientSecret"
    Write-Host "Provide via CLI parameters or .env file in the repo root (POWER_PLATFORM_ENVIRONMENT_ID, TENANT_ID, CLIENT_ID, CLIENT_SECRET)" -ForegroundColor Yellow
    exit 1
}

if (-not (Get-Command paconn -ErrorAction SilentlyContinue)) {
    Write-Error "paconn CLI not found. Install it with 'pip install paconn pyyaml' (requires Python 3.5+), then run 'paconn login' once before retrying."
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

# paconn only accepts JSON for --api-def, but openapi.yaml is our source of
# truth (imported directly by the portal wizard). Convert it to a generated,
# gitignored JSON file here so both paths stay in sync with one source file.
if ($ApiDefinition -match '\.ya?ml$') {
    $PythonCmd = Get-Command python -ErrorAction SilentlyContinue
    if (-not $PythonCmd) { $PythonCmd = Get-Command py -ErrorAction SilentlyContinue }
    if (-not $PythonCmd) {
        Write-Error "Python not found (needed to convert openapi.yaml to JSON for paconn). Install Python 3.5+ and 'pip install pyyaml'."
        exit 1
    }

    $ConvertScript = Join-Path $RepoRoot "custom-connector\scripts\_yaml_to_json.py"
    $GeneratedApiDefinition = Join-Path $RepoRoot "custom-connector\openapi.generated.json"
    & $PythonCmd.Source $ConvertScript $ApiDefinition $GeneratedApiDefinition
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to convert '$ApiDefinition' to JSON. Ensure 'pyyaml' is installed: pip install pyyaml"
        exit 1
    }
    $ApiDefinition = $GeneratedApiDefinition
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