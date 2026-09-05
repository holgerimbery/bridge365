# (c) 2026 Holger Imbery (contact@holgerimbery.blog)
# Licensed under the project LICENSE file.
#
# Populates the Classification Rule table (created by deploy-dataverse-tables.ps1)
# with sample routing rules, via the Dataverse Web API. Safe to re-run: matches
# existing rows by className and updates them instead of creating duplicates.
#
# Usage:
#   .\dataverse\scripts\seed-sample-classifications.ps1 `
#     -DataverseUrl "https://org.crm.dynamics.com" `
#     -TenantId "<tenant-id>" -ClientId "<app-client-id>" -ClientSecret "<app-client-secret>" `
#     -PublisherPrefix "b365"
#
# Pass -ClassificationsJson to seed different/additional rules instead of the
# built-in defaults below.

#Requires -Version 7.0
param(
    [string]$DataverseUrl,
    [string]$TenantId,
    [string]$ClientId,
    [string]$ClientSecret,
    [string]$PublisherPrefix,
    [string]$ClassificationsJson
)

$ErrorActionPreference = "Stop"

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
    if (-not $DataverseUrl) { $DataverseUrl = $env_vars['DATAVERSE_ENVIRONMENT_URL'] }
    if (-not $TenantId) { $TenantId = $env_vars['TENANT_ID'] }
    if (-not $ClientId) { $ClientId = $env_vars['CLIENT_ID'] }
    if (-not $ClientSecret) { $ClientSecret = $env_vars['CLIENT_SECRET'] }
    if (-not $PublisherPrefix) { $PublisherPrefix = $env_vars['DATAVERSE_PUBLISHER_PREFIX'] }
}
if (-not $PublisherPrefix) { $PublisherPrefix = "b365" }

if (-not $DataverseUrl -or -not $TenantId -or -not $ClientId -or -not $ClientSecret) {
    Write-Error "Missing required parameters: DataverseUrl, TenantId, ClientId, ClientSecret"
    Write-Host "Provide via CLI parameters or .env file in the repo root (DATAVERSE_ENVIRONMENT_URL, TENANT_ID, CLIENT_ID, CLIENT_SECRET)" -ForegroundColor Yellow
    exit 1
}
$DataverseUrl = $DataverseUrl.TrimEnd('/')
if ($DataverseUrl -notmatch '^https?://') {
    $DataverseUrl = "https://$DataverseUrl"
    Write-Host "DataverseUrl had no scheme - assuming https:// (now: $DataverseUrl)" -ForegroundColor Yellow
}

if (-not $ClassificationsJson) {
    $ClassificationsJson = @"
[
  {
    "className": "Invoice Question",
    "classExamples": "invoice\nbilling\namount\nreceipt",
    "classTarget": "Finance Department",
    "classTargetEmail": "finance@company.com",
    "isActive": true,
    "priority": 100,
    "modelLabel": "invoice_question"
  },
  {
    "className": "Technical Support",
    "classExamples": "cannot sign in\nerror\nAADSTS\naccess denied",
    "classTarget": "IT Support",
    "classTargetEmail": "itsupport@company.com",
    "isActive": true,
    "priority": 95,
    "modelLabel": "technical_support"
  },
  {
    "className": "Contract Inquiry",
    "classExamples": "contract\nagreement\nterms\nlicense",
    "classTarget": "Legal Operations",
    "classTargetEmail": "legal@company.com",
    "isActive": true,
    "priority": 90,
    "modelLabel": "contract_inquiry"
  }
]
"@
}
$classifications = $ClassificationsJson | ConvertFrom-Json

Write-Host "Dataverse environment: $DataverseUrl" -ForegroundColor Cyan
Write-Host "Rules to seed: $($classifications.Count)" -ForegroundColor Gray

# --- Auth --------------------------------------------------------------
Write-Host "`nAcquiring Dataverse access token..." -ForegroundColor Yellow
$tokenBody = @{
    grant_type    = "client_credentials"
    client_id     = $ClientId
    client_secret = $ClientSecret
    scope         = "$DataverseUrl/.default"
}
try {
    $tokenResponse = Invoke-RestMethod -Method Post `
        -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
        -ContentType "application/x-www-form-urlencoded" -Body $tokenBody
} catch {
    if ($_.ErrorDetails.Message) {
        Write-Error "Failed to acquire token: $($_.Exception.Message)`nEntra ID error detail: $($_.ErrorDetails.Message)"
    } else {
        Write-Error "Failed to acquire token: $($_.Exception.Message)"
    }
    exit 1
}
$Headers = @{
    Authorization      = "Bearer $($tokenResponse.access_token)"
    "OData-MaxVersion" = "4.0"
    "OData-Version"    = "4.0"
    Accept             = "application/json"
    "Content-Type"     = "application/json; charset=utf-8"
}
Write-Host "Token acquired." -ForegroundColor Green

$ApiBase = "$DataverseUrl/api/data/v9.2"
$entityLogicalName = "$PublisherPrefix" + "_classificationrule"

# Resolve the entity set name (pluralized collection name) dynamically instead
# of guessing/hardcoding it.
$entityMeta = Invoke-RestMethod -Method Get -Headers $Headers `
    -Uri "$ApiBase/EntityDefinitions(LogicalName='$entityLogicalName')?`$select=EntitySetName"
$EntitySet = $entityMeta.EntitySetName
Write-Host "Target collection: $EntitySet" -ForegroundColor Gray

$classNameField = "$PublisherPrefix" + "_classname"

foreach ($c in $classifications) {
    $record = @{
        "$($PublisherPrefix)_classname"        = $c.className
        "$($PublisherPrefix)_classexamples"    = $c.classExamples
        "$($PublisherPrefix)_classtarget"      = $c.classTarget
        "$($PublisherPrefix)_classtargetemail" = $c.classTargetEmail
        "$($PublisherPrefix)_isactive"         = [bool]$c.isActive
        "$($PublisherPrefix)_priority"         = [int]($c.priority ?? 0)
        "$($PublisherPrefix)_modellabel"       = $c.modelLabel
    }
    $body = $record | ConvertTo-Json

    # Look for an existing row with the same className (idempotent upsert).
    $filterValue = $c.className.Replace("'", "''")
    $existing = Invoke-RestMethod -Method Get -Headers $Headers `
        -Uri "$ApiBase/$($EntitySet)?`$select=$($PublisherPrefix)_classificationruleid&`$filter=$classNameField eq '$filterValue'"

    if ($existing.value.Count -gt 0) {
        $recordId = $existing.value[0]."$($PublisherPrefix)_classificationruleid"
        Write-Host "Updating '$($c.className)' ($recordId)..." -ForegroundColor Cyan
        Invoke-RestMethod -Method Patch -Headers $Headers -Uri "$ApiBase/$($EntitySet)($recordId)" -Body $body | Out-Null
    } else {
        Write-Host "Creating '$($c.className)'..." -ForegroundColor Cyan
        Invoke-RestMethod -Method Post -Headers $Headers -Uri "$ApiBase/$EntitySet" -Body $body | Out-Null
    }
}

Write-Host "`nDone. $($classifications.Count) classification rule(s) seeded." -ForegroundColor Green