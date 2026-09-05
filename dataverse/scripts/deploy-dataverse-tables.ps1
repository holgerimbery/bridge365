# (c) 2026 Holger Imbery (contact@holgerimbery.blog)
# Licensed under the project LICENSE file.
#
# Deploys the Phase 2 classification Dataverse tables (Classification Rule,
# Classification Audit) from the JSON templates in dataverse/schemas/, using
# the Dataverse Web API directly (no manual maker-portal steps). Idempotent:
# safe to re-run - existing tables/columns/relationships are left untouched,
# only missing ones are created.
#
# Prerequisites:
# 1. An Azure AD app registration with a client secret (the same one used by
#    backend-service/custom-connector works fine - no extra API permissions
#    needed in Azure AD itself for Dataverse; auth is client-credentials
#    against the Dataverse resource URL).
# 2. That app registration must be added as an **Application User** in the
#    target Dataverse environment (Power Platform Admin Center -> Environment
#    -> Settings -> Users + permissions -> Application users -> + New app
#    user), with a security role that includes "Create"/"Write" on
#    Customizations (e.g. **System Customizer** or **System Administrator**).
#    Without this, every call below fails with 401/403.
#
# Usage:
#   .\dataverse\scripts\deploy-dataverse-tables.ps1 `
#     -DataverseUrl "https://org.crm.dynamics.com" `
#     -TenantId "<tenant-id>" -ClientId "<app-client-id>" -ClientSecret "<app-client-secret>" `
#     -PublisherPrefix "b365"
#
# All parameters can also come from .env in the repo root (DATAVERSE_ENVIRONMENT_URL,
# TENANT_ID, CLIENT_ID, CLIENT_SECRET, DATAVERSE_PUBLISHER_PREFIX).

#Requires -Version 7.0
param(
    [string]$DataverseUrl,
    [string]$TenantId,
    [string]$ClientId,
    [string]$ClientSecret,
    [string]$PublisherPrefix,
    [string[]]$SchemaFiles
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

if (-not $SchemaFiles) {
    $SchemaFiles = Get-ChildItem (Join-Path $PSScriptRoot "..\schemas") -Filter "*.schema.json" | Sort-Object Name | ForEach-Object { $_.FullName }
}

Write-Host "Dataverse environment: $DataverseUrl" -ForegroundColor Cyan
Write-Host "Publisher prefix: $PublisherPrefix" -ForegroundColor Gray
Write-Host "Schema files: $($SchemaFiles.Count)" -ForegroundColor Gray

# --- Auth: client-credentials token scoped to the Dataverse resource -------
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
$AccessToken = $tokenResponse.access_token
$Headers = @{
    Authorization      = "Bearer $AccessToken"
    "OData-MaxVersion" = "4.0"
    "OData-Version"    = "4.0"
    Accept             = "application/json"
    "Content-Type"     = "application/json; charset=utf-8"
}
Write-Host "Token acquired." -ForegroundColor Green

$ApiBase = "$DataverseUrl/api/data/v9.2"

function Get-Label {
    param([string]$Text)
    return @{
        "@odata.type"    = "Microsoft.Dynamics.CRM.Label"
        LocalizedLabels  = @(@{ "@odata.type" = "Microsoft.Dynamics.CRM.LocalizedLabel"; Label = $Text; LanguageCode = 1033 })
    }
}

function Get-RequiredLevel {
    param([bool]$Required)
    return @{ Value = $(if ($Required) { "ApplicationRequired" } else { "None" }); CanBeChanged = $true }
}

function Test-EntityExists {
    param([string]$LogicalName)
    try {
        Invoke-RestMethod -Method Get -Headers $Headers `
            -Uri "$ApiBase/EntityDefinitions(LogicalName='$LogicalName')?`$select=LogicalName,EntitySetName" | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Get-AttributeMetadata {
    param($Attr, [string]$Prefix)
    $schemaName = "$Prefix" + "_" + $Attr.logicalName
    $displayName = Get-Label $Attr.displayName
    $description = Get-Label ($Attr.description ?? $Attr.displayName)
    $required = Get-RequiredLevel ([bool]($Attr.required -eq $true))

    switch ($Attr.type) {
        "String" {
            return @{
                "@odata.type"   = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
                SchemaName      = $schemaName
                DisplayName     = $displayName
                Description     = $description
                RequiredLevel   = $required
                MaxLength       = [int]($Attr.maxLength ?? 200)
                FormatName      = @{ Value = $(if ($Attr.format) { $Attr.format } else { "Text" }) }
            }
        }
        "Memo" {
            return @{
                "@odata.type" = "Microsoft.Dynamics.CRM.MemoAttributeMetadata"
                SchemaName    = $schemaName
                DisplayName   = $displayName
                Description   = $description
                RequiredLevel = $required
                MaxLength     = [int]($Attr.maxLength ?? 2000)
            }
        }
        "Integer" {
            return @{
                "@odata.type" = "Microsoft.Dynamics.CRM.IntegerAttributeMetadata"
                SchemaName    = $schemaName
                DisplayName   = $displayName
                Description   = $description
                RequiredLevel = $required
                MinValue      = [int]($Attr.minValue ?? 0)
                MaxValue      = [int]($Attr.maxValue ?? 2147483647)
            }
        }
        "Decimal" {
            return @{
                "@odata.type" = "Microsoft.Dynamics.CRM.DecimalAttributeMetadata"
                SchemaName    = $schemaName
                DisplayName   = $displayName
                Description   = $description
                RequiredLevel = $required
                MinValue      = [double]($Attr.minValue ?? 0)
                MaxValue      = [double]($Attr.maxValue ?? 100)
                Precision     = [int]($Attr.precision ?? 2)
            }
        }
        "Boolean" {
            return @{
                "@odata.type" = "Microsoft.Dynamics.CRM.BooleanAttributeMetadata"
                SchemaName    = $schemaName
                DisplayName   = $displayName
                Description   = $description
                RequiredLevel = $required
                OptionSet     = @{
                    "@odata.type" = "Microsoft.Dynamics.CRM.BooleanOptionSetMetadata"
                    TrueOption    = @{ Value = 1; Label = (Get-Label ($Attr.trueLabel ?? "Yes")) }
                    FalseOption   = @{ Value = 0; Label = (Get-Label ($Attr.falseLabel ?? "No")) }
                }
            }
        }
        default {
            throw "Unsupported attribute type '$($Attr.type)' for '$($Attr.logicalName)'"
        }
    }
}

function New-DataverseEntity {
    param($Schema, [string]$Prefix)
    $logicalName = "$Prefix" + "_" + $Schema.logicalName
    if (Test-EntityExists $logicalName) {
        Write-Host "  Table '$logicalName' already exists - skipping create." -ForegroundColor Gray
        return
    }

    Write-Host "  Creating table '$logicalName'..." -ForegroundColor Cyan
    $primarySchemaName = "$Prefix" + "_" + $Schema.primaryAttribute.logicalName
    $body = @{
        "@odata.type"        = "Microsoft.Dynamics.CRM.EntityMetadata"
        SchemaName           = ("$Prefix" + "_" + $Schema.logicalName).Substring(0,1).ToUpper() + ("$Prefix" + "_" + $Schema.logicalName).Substring(1)
        DisplayName          = Get-Label $Schema.displayName
        DisplayCollectionName = Get-Label $Schema.displayCollectionName
        Description          = Get-Label $Schema.description
        OwnershipType         = "UserOwned"
        IsActivity            = $false
        HasNotes              = $false
        HasActivities         = $false
        Attributes            = @(
            @{
                "@odata.type" = "Microsoft.Dynamics.CRM.StringAttributeMetadata"
                SchemaName    = $primarySchemaName
                DisplayName   = Get-Label $Schema.primaryAttribute.displayName
                Description   = Get-Label ($Schema.primaryAttribute.description ?? $Schema.primaryAttribute.displayName)
                RequiredLevel = Get-RequiredLevel $true
                MaxLength     = [int]($Schema.primaryAttribute.maxLength ?? 200)
                IsPrimaryName = $true
            }
        )
    }

    Invoke-RestMethod -Method Post -Headers $Headers -Uri "$ApiBase/EntityDefinitions" -Body ($body | ConvertTo-Json -Depth 10) | Out-Null

    # Table creation is not always instant - poll briefly before adding columns.
    $attempts = 0
    while (-not (Test-EntityExists $logicalName) -and $attempts -lt 10) {
        Start-Sleep -Seconds 2
        $attempts++
    }
    Write-Host "  Table '$logicalName' created." -ForegroundColor Green
}

function Test-AttributeExists {
    param([string]$EntityLogicalName, [string]$AttributeLogicalName)
    try {
        Invoke-RestMethod -Method Get -Headers $Headers `
            -Uri "$ApiBase/EntityDefinitions(LogicalName='$EntityLogicalName')/Attributes(LogicalName='$AttributeLogicalName')?`$select=LogicalName" | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Add-DataverseAttributes {
    param($Schema, [string]$Prefix)
    $entityLogicalName = "$Prefix" + "_" + $Schema.logicalName
    foreach ($attr in $Schema.attributes) {
        $attrLogicalName = "$Prefix" + "_" + $attr.logicalName
        if (Test-AttributeExists -EntityLogicalName $entityLogicalName -AttributeLogicalName $attrLogicalName) {
            Write-Host "    Column '$attrLogicalName' already exists - skipping." -ForegroundColor Gray
            continue
        }
        Write-Host "    Adding column '$attrLogicalName' ($($attr.type))..." -ForegroundColor Cyan
        $attrMetadata = Get-AttributeMetadata -Attr $attr -Prefix $Prefix
        Invoke-RestMethod -Method Post -Headers $Headers `
            -Uri "$ApiBase/EntityDefinitions(LogicalName='$entityLogicalName')/Attributes" `
            -Body ($attrMetadata | ConvertTo-Json -Depth 10) | Out-Null
        Write-Host "    Column '$attrLogicalName' created." -ForegroundColor Green
    }
}

function Test-RelationshipExists {
    param([string]$SchemaName)
    try {
        Invoke-RestMethod -Method Get -Headers $Headers `
            -Uri "$ApiBase/RelationshipDefinitions(SchemaName='$SchemaName')?`$select=SchemaName" | Out-Null
        return $true
    } catch {
        return $false
    }
}

function Add-DataverseLookups {
    param($Schema, [string]$Prefix)
    if (-not $Schema.lookups) { return }
    $referencingEntity = "$Prefix" + "_" + $Schema.logicalName
    foreach ($lookup in $Schema.lookups) {
        $referencedEntity = "$Prefix" + "_" + $lookup.referencedEntityLogicalName
        $relSchemaName = "$Prefix" + "_" + $lookup.referencedEntityLogicalName + "_" + $Schema.logicalName
        if (Test-RelationshipExists $relSchemaName) {
            Write-Host "    Relationship '$relSchemaName' already exists - skipping." -ForegroundColor Gray
            continue
        }
        if (-not (Test-EntityExists $referencedEntity)) {
            Write-Warning "    Referenced table '$referencedEntity' does not exist yet - deploy it first, then re-run to create this lookup."
            continue
        }
        Write-Host "    Creating lookup relationship '$relSchemaName' -> $referencedEntity..." -ForegroundColor Cyan
        $lookupSchemaName = "$Prefix" + "_" + $lookup.logicalName
        $body = @{
            "@odata.type"     = "Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata"
            SchemaName        = $relSchemaName
            ReferencedEntity  = $referencedEntity
            ReferencingEntity = $referencingEntity
            Lookup            = @{
                "@odata.type" = "Microsoft.Dynamics.CRM.LookupAttributeMetadata"
                SchemaName    = $lookupSchemaName
                DisplayName   = Get-Label $lookup.displayName
                Description   = Get-Label ($lookup.description ?? $lookup.displayName)
                RequiredLevel = Get-RequiredLevel $false
            }
        }
        Invoke-RestMethod -Method Post -Headers $Headers -Uri "$ApiBase/RelationshipDefinitions" -Body ($body | ConvertTo-Json -Depth 10) | Out-Null
        Write-Host "    Relationship '$relSchemaName' created." -ForegroundColor Green
    }
}

# --- Pass 1: create tables (and their primary columns) ---------------------
$schemas = @()
foreach ($file in $SchemaFiles) {
    Write-Host "`nProcessing schema: $file" -ForegroundColor Yellow
    $schema = Get-Content $file -Raw | ConvertFrom-Json
    $schemas += , $schema
    New-DataverseEntity -Schema $schema -Prefix $PublisherPrefix
}

# --- Pass 2: add non-primary columns ----------------------------------------
foreach ($schema in $schemas) {
    Write-Host "`nColumns for '$($PublisherPrefix)_$($schema.logicalName)':" -ForegroundColor Yellow
    Add-DataverseAttributes -Schema $schema -Prefix $PublisherPrefix
}

# --- Pass 3: lookups/relationships (run last - both tables must exist) -----
foreach ($schema in $schemas) {
    if ($schema.lookups) {
        Write-Host "`nRelationships for '$($PublisherPrefix)_$($schema.logicalName)':" -ForegroundColor Yellow
        Add-DataverseLookups -Schema $schema -Prefix $PublisherPrefix
    }
}

Write-Host "`nDone. Table logical names:" -ForegroundColor Green
foreach ($schema in $schemas) {
    $logicalName = "$PublisherPrefix" + "_" + $schema.logicalName
    try {
        $meta = Invoke-RestMethod -Method Get -Headers $Headers `
            -Uri "$ApiBase/EntityDefinitions(LogicalName='$logicalName')?`$select=LogicalName,EntitySetName"
        Write-Host "  $($meta.LogicalName)  (collection: $($meta.EntitySetName))" -ForegroundColor White
    } catch {
        Write-Host "  $logicalName" -ForegroundColor White
    }
}