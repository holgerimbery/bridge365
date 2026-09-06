# (c) 2026 Holger Imbery (contact@holgerimbery.blog)
# Licensed under the project LICENSE file.
#
# Bridge365 unified onboarding wizard.
#
# A single menu-driven entry point that walks a new deployer through the
# whole Phase 1/2 setup (docs/wiki/phase-1-mailbox-setup.md,
# docs/wiki/phase-2-classification-table.md) with the minimum possible
# typing: it auto-discovers whatever it can from the current `az`/Graph
# sign-in and only asks for what genuinely cannot be inferred (an app
# name, the shared mailbox address, who is allowed to call the API, and
# which Power Platform environment to target).
#
# This script does not reimplement Azure/Graph/Power Platform logic that
# already exists as dedicated, tested scripts under backend-service/scripts,
# custom-connector/scripts, dataverse/scripts and docs/wiki/scripts - it
# only collects input, generates consistent resource names, persists state
# in .env + .onboarding-state.json, and calls those existing scripts in the
# right order, with guidance printed whenever a step cannot be automated
# (e.g. missing admin rights, missing CLI tools).
#
# Usage: pwsh -File .\onboarding.ps1

$ErrorActionPreference = "Stop"
$RepoRoot = $PSScriptRoot
$EnvFile = Join-Path $RepoRoot ".env"
$StateFile = Join-Path $RepoRoot ".onboarding-state.json"

# Canonical set of every key the wizard (and the scripts it wraps) can read
# or write, in the same order as .env.example, with the onboarding-specific
# naming keys appended at the end. This is the single source of truth used
# to detect an existing .env's completeness - keep it in sync with
# .env.example whenever a step gains a new setting.
$script:KnownEnvKeys = @(
    "AZURE_SUBSCRIPTION_ID",
    "RESOURCE_GROUP",
    "LOCATION",
    "APP_SERVICE_NAME",
    "TENANT_ID",
    "CLIENT_ID",
    "CLIENT_SECRET",
    "SECURITY_GROUP_NAME",
    "ALLOWED_EMAIL_ADDRESSES",
    "POWER_PLATFORM_ENVIRONMENT_ID",
    "CUSTOM_CONNECTOR_ID",
    "DATAVERSE_ENVIRONMENT_URL",
    "DATAVERSE_PUBLISHER_PREFIX",
    "BACKEND_URL",
    "MAILBOX_ADDRESS",
    "APP_BASE_NAME",
    "APP_REGISTRATION_NAME",
    "KEY_VAULT_NAME"
)

# ---------------------------------------------------------------------------
# .env helpers - same format/semantics as every script under */scripts, so
# either can be run standalone and both stay in sync.
# ---------------------------------------------------------------------------

function Read-DotEnv {
    param([string]$Path)
    $vars = [ordered]@{}
    if (Test-Path $Path) {
        Get-Content $Path | Where-Object { $_ -match '=' -and -not $_.TrimStart().StartsWith('#') } | ForEach-Object {
            $key, $value = $_ -split '=', 2
            $vars[$key.Trim()] = $value.Trim().Trim('"').Trim("'")
        }
    }
    return $vars
}

function Save-DotEnv {
    param([System.Collections.Specialized.OrderedDictionary]$Vars, [string]$Path)
    $lines = foreach ($key in $Vars.Keys) { "$key=$($Vars[$key])" }
    Set-Content -Path $Path -Value $lines -Encoding utf8
}

function Set-EnvValue {
    param([string]$Key, [string]$Value)
    if ($null -eq $script:EnvVars) { $script:EnvVars = [ordered]@{} }
    $script:EnvVars[$Key] = $Value
    Save-DotEnv -Vars $script:EnvVars -Path $EnvFile
}

function Get-EnvValue {
    param([string]$Key, [string]$Default = "")
    if ($script:EnvVars.Contains($Key) -and $script:EnvVars[$Key]) { return $script:EnvVars[$Key] }
    return $Default
}

# Loads an existing .env (reusing every value already in it - nothing is
# ever overwritten here) or, if none exists, treats this as a brand-new
# install and creates an empty one. Either way, ensures every key in
# $script:KnownEnvKeys is present in the file (appending any that are
# missing, left blank) so the file is always a complete, self-documenting
# template and later steps only need to fill in the blanks - they never
# have to guess whether a setting exists.
function Initialize-EnvFile {
    if (-not (Test-Path $EnvFile)) {
        Write-Heading ".env"
        Write-Warn2 "No existing .env found - starting a brand-new installation."
        $script:EnvVars = [ordered]@{}
        foreach ($key in $script:KnownEnvKeys) { $script:EnvVars[$key] = "" }
        Save-DotEnv -Vars $script:EnvVars -Path $EnvFile
        Write-Ok "Created a new .env with $($script:KnownEnvKeys.Count) known keys."
        return
    }

    Write-Heading ".env"
    Write-Ok "Existing .env found at $EnvFile - reusing its values."
    $script:EnvVars = Read-DotEnv $EnvFile

    $missing = @()
    foreach ($key in $script:KnownEnvKeys) {
        if (-not $script:EnvVars.Contains($key)) {
            $script:EnvVars[$key] = ""
            $missing += $key
        }
    }

    if ($missing.Count -gt 0) {
        Save-DotEnv -Vars $script:EnvVars -Path $EnvFile
        Write-Warn2 "Appended $($missing.Count) missing key(s) to .env (left blank - the wizard will fill them in as it runs): $($missing -join ', ')"
    } else {
        Write-Ok "All $($script:KnownEnvKeys.Count) expected keys are already present in .env."
    }

    $unknown = @($script:EnvVars.Keys | Where-Object { $script:KnownEnvKeys -notcontains $_ })
    if ($unknown.Count -gt 0) {
        Write-Warn2 "Note: .env also has $($unknown.Count) extra key(s) not managed by this wizard (left untouched): $($unknown -join ', ')"
    }
}

# ---------------------------------------------------------------------------
# Onboarding state - separate from .env because it tracks *progress*
# (which steps completed, the generated naming postfix) rather than runtime
# config. Gitignored; safe to delete to force a clean re-run.
# ---------------------------------------------------------------------------

function Read-State {
    if (Test-Path $StateFile) {
        return Get-Content $StateFile -Raw | ConvertFrom-Json -AsHashtable
    }
    return @{ Postfix = $null; CompletedSteps = @() }
}

function Save-State {
    param($State)
    ($State | ConvertTo-Json -Depth 5) | Set-Content -Path $StateFile -Encoding utf8
}

function Set-StepComplete {
    param([string]$Step)
    if ($script:State.CompletedSteps -notcontains $Step) {
        $script:State.CompletedSteps += $Step
        Save-State $script:State
    }
}

function Step-IsComplete {
    param([string]$Step)
    return $script:State.CompletedSteps -contains $Step
}

# ---------------------------------------------------------------------------
# UI helpers
# ---------------------------------------------------------------------------

function Write-Heading {
    param([string]$Text)
    Write-Host ""
    Write-Host "== $Text ==" -ForegroundColor Cyan
}

function Write-Ok { param([string]$Text) Write-Host "  [OK] $Text" -ForegroundColor Green }
function Write-Warn2 { param([string]$Text) Write-Host "  [!] $Text" -ForegroundColor Yellow }
function Write-Fail { param([string]$Text) Write-Host "  [X] $Text" -ForegroundColor Red }

function Read-Prompt {
    param([string]$Message, [string]$Default = "", [switch]$Required)
    while ($true) {
        $suffix = if ($Default) { " [$Default]" } else { "" }
        $answer = Read-Host "$Message$suffix"
        if (-not $answer -and $Default) { return $Default }
        if (-not $answer -and $Required) {
            Write-Warn2 "A value is required."
            continue
        }
        return $answer
    }
}

# Runs an existing step script, treating "already exists" style failures as
# success (idempotent re-runs), and printing manual-fallback guidance on any
# other failure instead of aborting the whole wizard.
function Invoke-Step {
    param(
        [string]$Name,
        [scriptblock]$Action,
        [string]$ManualGuidance = ""
    )
    Write-Heading $Name
    try {
        & $Action
        if ($LASTEXITCODE -and $LASTEXITCODE -ne 0) {
            throw "Step exited with code $LASTEXITCODE"
        }
        Write-Ok "$Name complete"
        Set-StepComplete $Name
        return $true
    } catch {
        Write-Fail "$Name failed: $($_.Exception.Message)"
        if ($ManualGuidance) {
            Write-Warn2 "Manual steps:"
            Write-Host $ManualGuidance -ForegroundColor Gray
        }
        return $false
    }
}

# Runs a script in a separate PowerShell process (not "&" in-process) so that
# an "exit" call inside the target script - e.g. because a required parameter
# is missing - cannot terminate this wizard. Returns the child process exit
# code; output still streams live to the console.
function Invoke-ChildScript {
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [hashtable]$Arguments = @{}
    )
    $argList = @()
    foreach ($key in $Arguments.Keys) {
        $value = $Arguments[$key]
        if ([string]::IsNullOrWhiteSpace($value)) { continue }
        $argList += "-$key"
        $argList += $value
    }
    $hostCmd = Get-Command pwsh -ErrorAction SilentlyContinue
    $exePath = if ($hostCmd) { $hostCmd.Source } else { (Get-Process -Id $PID).Path }
    & $exePath -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @argList
    return $LASTEXITCODE
}

# Runs one diagnostic check: skips cleanly with guidance if required .env
# values aren't set yet (instead of invoking a script that would error out),
# otherwise runs it safely out-of-process and records Pass/Fail/Skipped for
# the end-of-run summary.
function Invoke-DiagnosticCheck {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$ScriptPath,
        [hashtable]$Arguments = @{},
        [string[]]$RequiredEnvKeys = @(),
        [string]$SkipGuidance = ""
    )
    $missing = $RequiredEnvKeys | Where-Object { -not (Get-EnvValue $_) }
    if ($missing.Count -gt 0) {
        Write-Warn2 "Skipping '$Name' - missing: $($missing -join ', ')"
        if ($SkipGuidance) { Write-Host "  $SkipGuidance" -ForegroundColor Gray }
        $script:DiagnosticResults += [PSCustomObject]@{ Name = $Name; Status = "Skipped"; Detail = "Missing: $($missing -join ', ')" }
        return
    }
    Write-Host ""
    Write-Host "--- $Name ---" -ForegroundColor Cyan
    $exitCode = Invoke-ChildScript -ScriptPath $ScriptPath -Arguments $Arguments
    if ($exitCode -eq 0) {
        $script:DiagnosticResults += [PSCustomObject]@{ Name = $Name; Status = "Pass"; Detail = "" }
    } else {
        $script:DiagnosticResults += [PSCustomObject]@{ Name = $Name; Status = "Fail"; Detail = "Exit code $exitCode" }
    }
}
# ---------------------------------------------------------------------------
# Prerequisite / environment discovery - minimizes what we have to ask for.
# ---------------------------------------------------------------------------

function Test-Prerequisites {
    Write-Heading "Checking prerequisites"
    $ok = $true
    if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
        Write-Fail "Azure CLI ('az') not found. Install: https://aka.ms/azure-cli"
        $ok = $false
    } else {
        Write-Ok "Azure CLI found"
    }
    if (-not (Get-Command pac -ErrorAction SilentlyContinue)) {
        Write-Warn2 "Power Platform CLI ('pac') not found - environment auto-discovery will be skipped. Install: https://aka.ms/PowerPlatformCLI"
    } else {
        Write-Ok "Power Platform CLI found"
    }
    if (-not (Get-Command paconn -ErrorAction SilentlyContinue)) {
        Write-Warn2 "paconn CLI not found - custom connector deploy will be skipped until installed ('pip install paconn pyyaml', then 'paconn login')."
    } else {
        Write-Ok "paconn CLI found"
    }
    return $ok
}

# Best-effort tenant display name lookup (older az CLI versions, or callers
# without az account tenant list rights, silently fall back to just the ID).
function Get-TenantDisplayName {
    param([string]$TenantId)
    try {
        $tenants = az account tenant list -o json 2>$null | ConvertFrom-Json
        $match = $tenants | Where-Object { $_.tenantId -eq $TenantId } | Select-Object -First 1
        if ($match -and $match.displayName) { return $match.displayName }
    } catch {
        Write-Verbose "Tenant display name lookup failed (older az CLI or insufficient rights): $($_.Exception.Message)"
    }
    return $null
}

# Replaces .env with a blank template of every known key - used when the
# signed-in account/tenant turns out to be wrong and the user asks to start
# clean instead of keeping settings from the previous tenant. The previous
# .env is backed up first, never silently discarded.
function Reset-EnvFile {
    if (Test-Path $EnvFile) {
        $backup = "$EnvFile.bak"
        Copy-Item -Path $EnvFile -Destination $backup -Force
        Write-Warn2 "Backed up previous .env to $backup"
    }
    $script:EnvVars = [ordered]@{}
    foreach ($key in $script:KnownEnvKeys) { $script:EnvVars[$key] = "" }
    Save-DotEnv -Vars $script:EnvVars -Path $EnvFile
    # A different tenant/account means any previously generated naming
    # postfix should not be reused either - force a fresh one.
    $script:State.Postfix = $null
    Save-State $script:State
    Write-Ok "Replaced .env with a blank template ($($script:KnownEnvKeys.Count) keys)."
}

function Get-AzureContext {
    Write-Heading "Azure sign-in"
    $account = az account show -o json 2>$null | ConvertFrom-Json

    if ($account) {
        $tenantName = Get-TenantDisplayName $account.tenantId
        $tenantLabel = if ($tenantName) { "$tenantName ($($account.tenantId))" } else { $account.tenantId }
        Write-Host "  Signed in as:  $($account.user.name)" -ForegroundColor Cyan
        Write-Host "  Tenant:        $tenantLabel" -ForegroundColor Cyan
        Write-Host "  Subscription:  $($account.name) ($($account.id))" -ForegroundColor Cyan

        $confirm = Read-Prompt "Is this the correct account/tenant? (y/n)" "y"
        if ($confirm -eq 'n') {
            Write-Warn2 "Signing out and starting a fresh 'az login'..."
            az logout -o none 2>$null
            az login -o none
            $account = az account show -o json | ConvertFrom-Json
            $tenantName = Get-TenantDisplayName $account.tenantId
            $tenantLabel = if ($tenantName) { "$tenantName ($($account.tenantId))" } else { $account.tenantId }
            Write-Ok "Now signed in as $($account.user.name) (tenant $tenantLabel)"

            $replace = Read-Prompt "Replace the existing .env with a fresh one for this account? (y/n)" "n"
            if ($replace -eq 'y') { Reset-EnvFile }
        }
    } else {
        Write-Warn2 "Not signed in to Azure CLI. Running 'az login'..."
        az login -o none
        $account = az account show -o json | ConvertFrom-Json
    }

    Write-Ok "Using tenant $($account.tenantId), subscription $($account.name) ($($account.id))"
    Set-EnvValue "TENANT_ID" $account.tenantId

    # Only offer to pick a different subscription when .env didn't already
    # have one pinned - check the pre-existing value, not the one we are
    # about to write, so this doesn't just silently no-op every run.
    $existingSubscriptionId = Get-EnvValue "AZURE_SUBSCRIPTION_ID"
    $accounts = az account list -o json | ConvertFrom-Json
    if (-not $existingSubscriptionId -and $accounts.Count -gt 1) {
        Write-Host "Multiple subscriptions available:"
        for ($i = 0; $i -lt $accounts.Count; $i++) { Write-Host "  [$i] $($accounts[$i].name) ($($accounts[$i].id))" }
        $choice = Read-Prompt "Select subscription index" "0"
        $account = $accounts[[int]$choice]
        az account set --subscription $account.id -o none
    }
    Set-EnvValue "AZURE_SUBSCRIPTION_ID" $account.id
    return $account
}

function Get-PowerPlatformEnvironment {
    if (Get-EnvValue "POWER_PLATFORM_ENVIRONMENT_ID") { return }
    if (-not (Get-Command pac -ErrorAction SilentlyContinue)) {
        Set-EnvValue "POWER_PLATFORM_ENVIRONMENT_ID" (Read-Prompt "Power Platform environment ID (GUID)" -Required)
        return
    }
    Write-Heading "Discovering Power Platform environments"
    try {
        $envJson = pac env list --json 2>$null
        $envs = $envJson | ConvertFrom-Json
    } catch { $envs = $null }
    if (-not $envs -or $envs.Count -eq 0) {
        Set-EnvValue "POWER_PLATFORM_ENVIRONMENT_ID" (Read-Prompt "Power Platform environment ID (GUID) - could not auto-list" -Required)
        return
    }
    for ($i = 0; $i -lt $envs.Count; $i++) {
        Write-Host "  [$i] $($envs[$i].DisplayName)  ($($envs[$i].EnvironmentId))"
    }
    $choice = [int](Read-Prompt "Select Power Platform environment index" "0")
    $selected = $envs[$choice]
    Set-EnvValue "POWER_PLATFORM_ENVIRONMENT_ID" $selected.EnvironmentId
    if ($selected.EnvironmentUrl) { Set-EnvValue "DATAVERSE_ENVIRONMENT_URL" $selected.EnvironmentUrl }
}

# ---------------------------------------------------------------------------
# Naming - one AppName + one generated postfix, reused for the life of the
# state file so re-runs never rename/duplicate resources. Each derived name
# is truncated to that Azure resource type's real limit while the postfix
# (the part that guarantees uniqueness) is always preserved.
# ---------------------------------------------------------------------------

function New-Postfix {
    $chars = 'abcdefghijklmnopqrstuvwxyz0123456789'
    -join (1..5 | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
}

function Get-TruncatedName {
    param([string]$Base, [string]$Postfix, [int]$MaxLength)
    $suffix = "-$Postfix"
    $maxBase = $MaxLength - $suffix.Length
    if ($maxBase -lt 1) { $maxBase = 1 }
    $trimmedBase = if ($Base.Length -gt $maxBase) { $Base.Substring(0, $maxBase) } else { $Base }
    return "$trimmedBase$suffix".Trim('-')
}

function Initialize-Naming {
    if (-not (Get-EnvValue "APP_BASE_NAME")) {
        $appName = Read-Prompt "Application name (e.g. 'sharedmbx') - used to derive all resource names" -Required
        $appName = ($appName.ToLower() -replace '[^a-z0-9-]', '-')
        Set-EnvValue "APP_BASE_NAME" $appName
    }
    $appName = Get-EnvValue "APP_BASE_NAME"

    if (-not $script:State.Postfix) {
        $script:State.Postfix = New-Postfix
        Save-State $script:State
        Write-Ok "Generated naming postfix: $($script:State.Postfix) (persisted in .onboarding-state.json)"
    }
    $postfix = $script:State.Postfix

    # Azure name length limits: App Service name <= 60, Resource Group <= 90,
    # Key Vault name <= 24, mail security group has no hard Azure limit but
    # kept short for readability.
    if (-not (Get-EnvValue "RESOURCE_GROUP")) { Set-EnvValue "RESOURCE_GROUP" (Get-TruncatedName "rg-$appName" $postfix 90) }
    if (-not (Get-EnvValue "APP_SERVICE_NAME")) { Set-EnvValue "APP_SERVICE_NAME" (Get-TruncatedName $appName $postfix 60) }
    if (-not (Get-EnvValue "APP_REGISTRATION_NAME")) { Set-EnvValue "APP_REGISTRATION_NAME" (Get-TruncatedName $appName $postfix 120) }
    if (-not (Get-EnvValue "SECURITY_GROUP_NAME")) { Set-EnvValue "SECURITY_GROUP_NAME" (Get-TruncatedName "AppAccess-$appName" $postfix 64) }
    if (-not (Get-EnvValue "KEY_VAULT_NAME")) { Set-EnvValue "KEY_VAULT_NAME" (Get-TruncatedName "kv-$appName" $postfix 24) }
    if (-not (Get-EnvValue "DATAVERSE_PUBLISHER_PREFIX")) {
        $prefix = ($appName -replace '[^a-z0-9]', '').Substring(0, [Math]::Min(8, ($appName -replace '[^a-z0-9]', '').Length))
        if ($prefix.Length -lt 2) { $prefix = "b365" }
        Set-EnvValue "DATAVERSE_PUBLISHER_PREFIX" $prefix
    }
}

# ---------------------------------------------------------------------------
# Step implementations - thin wrappers around existing scripts.
# ---------------------------------------------------------------------------

function Step-AppRegistration {
    Invoke-Step "App Registration & API Permissions" {
        $result = & (Join-Path $RepoRoot "docs\wiki\scripts\create-app-registration.ps1") `
            -DisplayName (Get-EnvValue "APP_REGISTRATION_NAME")
        if (-not $result) { throw "create-app-registration.ps1 returned no result" }
        Set-EnvValue "CLIENT_ID" $result.AppId
        Set-EnvValue "CLIENT_SECRET" $result.ClientSecret
        Set-EnvValue "TENANT_ID" $result.TenantId
        if (-not $result.ConsentVerified) {
            Write-Warn2 "Continuing without verified admin consent - Graph calls will 403 until an admin grants consent (see guidance above)."
        }
        & (Join-Path $RepoRoot "docs\wiki\scripts\test-app-registration.ps1") -ClientId $result.AppId -ClientSecret $result.ClientSecret -TenantId $result.TenantId
    } -ManualGuidance "Create the app registration manually in the Azure Portal (Entra ID > App registrations) - see docs/wiki/phase-1-mailbox-setup.md Step 3.1-3.3."
}

function Step-MailboxAccess {
    if (-not (Get-EnvValue "MAILBOX_ADDRESS")) {
        Set-EnvValue "MAILBOX_ADDRESS" (Read-Prompt "Shared mailbox address to protect (e.g. support@company.com)" -Required)
    }
    Invoke-Step "Shared Mailbox Access Restriction" {
        & (Join-Path $RepoRoot "docs\wiki\scripts\grant-mailbox-permissions.ps1") `
            -ClientId (Get-EnvValue "CLIENT_ID") `
            -MailboxAddress (Get-EnvValue "MAILBOX_ADDRESS") `
            -SecurityGroupName (Get-EnvValue "SECURITY_GROUP_NAME")
    } -ManualGuidance "Requires Exchange Online admin rights. Ask an Exchange admin to run docs/wiki/scripts/grant-mailbox-permissions.ps1, or follow docs/wiki/phase-1-mailbox-setup.md Step 3.5 manually. Note: policy propagation can take up to an hour."
}

function Step-AzureResources {
    Invoke-Step "Azure Resource Creation (Resource Group + App Service)" {
        & (Join-Path $RepoRoot "backend-service\scripts\create-app-service.ps1") `
            -ResourceGroup (Get-EnvValue "RESOURCE_GROUP") `
            -AppServiceName (Get-EnvValue "APP_SERVICE_NAME") `
            -Location (Get-EnvValue "LOCATION" "eastus") `
            -TenantId (Get-EnvValue "TENANT_ID") `
            -SubscriptionId (Get-EnvValue "AZURE_SUBSCRIPTION_ID")
        Set-EnvValue "BACKEND_URL" "https://$(Get-EnvValue 'APP_SERVICE_NAME').azurewebsites.net"
    } -ManualGuidance "Requires Contributor rights on the subscription/resource group. See docs/wiki/phase-1-mailbox-setup.md Step 4.1."
}

function Step-ConfigureAndDeployBackend {
    Invoke-Step "Configure App Service Settings" {
        & (Join-Path $RepoRoot "backend-service\scripts\configure-app-service.ps1") `
            -ResourceGroup (Get-EnvValue "RESOURCE_GROUP") `
            -AppServiceName (Get-EnvValue "APP_SERVICE_NAME") `
            -ClientId (Get-EnvValue "CLIENT_ID") `
            -ClientSecret (Get-EnvValue "CLIENT_SECRET") `
            -TenantId (Get-EnvValue "TENANT_ID") `
            -SubscriptionId (Get-EnvValue "AZURE_SUBSCRIPTION_ID")
    }
    Invoke-Step "Deploy Backend Code" {
        & (Join-Path $RepoRoot "backend-service\scripts\deploy-backend.ps1") `
            -ResourceGroup (Get-EnvValue "RESOURCE_GROUP") `
            -AppServiceName (Get-EnvValue "APP_SERVICE_NAME") `
            -TenantId (Get-EnvValue "TENANT_ID") `
            -SubscriptionId (Get-EnvValue "AZURE_SUBSCRIPTION_ID")
    } -ManualGuidance "See docs/wiki/phase-1-mailbox-setup.md Step 4.4 for manual ZIP deployment steps."
}

function Step-SecurityHardening {
    if (-not (Get-EnvValue "ALLOWED_EMAIL_ADDRESSES")) {
        $me = az account show --query user.name -o tsv 2>$null
        Set-EnvValue "ALLOWED_EMAIL_ADDRESSES" (Read-Prompt "Comma-separated allowlisted caller emails" $me)
    }
    Invoke-Step "Enable Easy Auth" {
        & (Join-Path $RepoRoot "backend-service\scripts\enable-backend-auth.ps1") `
            -ResourceGroup (Get-EnvValue "RESOURCE_GROUP") `
            -AppServiceName (Get-EnvValue "APP_SERVICE_NAME") `
            -TenantId (Get-EnvValue "TENANT_ID") `
            -ClientId (Get-EnvValue "CLIENT_ID") `
            -SubscriptionId (Get-EnvValue "AZURE_SUBSCRIPTION_ID")
    } -ManualGuidance "See docs/wiki/phase-1-mailbox-setup.md Step 4.6.1."
    Invoke-Step "Configure Email Allowlist" {
        & (Join-Path $RepoRoot "backend-service\scripts\configure-allowlist.ps1") `
            -ResourceGroup (Get-EnvValue "RESOURCE_GROUP") `
            -AppServiceName (Get-EnvValue "APP_SERVICE_NAME") `
            -AllowedEmailAddresses (Get-EnvValue "ALLOWED_EMAIL_ADDRESSES") `
            -TenantId (Get-EnvValue "TENANT_ID") `
            -SubscriptionId (Get-EnvValue "AZURE_SUBSCRIPTION_ID")
    }
    Invoke-Step "Move Client Secret to Key Vault" {
        & (Join-Path $RepoRoot "backend-service\scripts\secure-client-secret.ps1") `
            -ResourceGroup (Get-EnvValue "RESOURCE_GROUP") `
            -KeyVaultName (Get-EnvValue "KEY_VAULT_NAME") `
            -AppServiceName (Get-EnvValue "APP_SERVICE_NAME") `
            -ClientSecret (Get-EnvValue "CLIENT_SECRET") `
            -TenantId (Get-EnvValue "TENANT_ID") `
            -SubscriptionId (Get-EnvValue "AZURE_SUBSCRIPTION_ID")
    } -ManualGuidance "Requires rights to create a Key Vault in the resource group. See docs/wiki/phase-1-mailbox-setup.md Step 4.6.4."
}

function Step-CustomConnector {
    Get-PowerPlatformEnvironment
    if (-not (Get-Command paconn -ErrorAction SilentlyContinue)) {
        Write-Warn2 "Skipping custom connector deploy - paconn CLI not installed."
        Write-Host "  Install with: pip install paconn pyyaml ; then run: paconn login" -ForegroundColor Gray
        Write-Host "  Afterwards, re-run this menu option, or follow docs/wiki/phase-1-mailbox-setup.md Section 5 to create it manually in the Power Platform portal." -ForegroundColor Gray
        return
    }
    Invoke-Step "Generate & Deploy Custom Connector" {
        $before = Get-EnvValue "CUSTOM_CONNECTOR_ID"
        & (Join-Path $RepoRoot "custom-connector\scripts\deploy-connector.ps1") `
            -EnvironmentId (Get-EnvValue "POWER_PLATFORM_ENVIRONMENT_ID") `
            -TenantId (Get-EnvValue "TENANT_ID") `
            -ClientId (Get-EnvValue "CLIENT_ID") `
            -ClientSecret (Get-EnvValue "CLIENT_SECRET") `
            -ConnectorId $before `
            -BackendHost (Get-EnvValue "APP_SERVICE_NAME")
        if (-not $before) {
            Write-Warn2 "If a new connector ID was printed above, copy it into .env as CUSTOM_CONNECTOR_ID (or re-run this step and paste it when prompted)."
            $newId = Read-Prompt "Paste the new CUSTOM_CONNECTOR_ID here (or leave blank to set it later)"
            if ($newId) { Set-EnvValue "CUSTOM_CONNECTOR_ID" $newId }
        }
    } -ManualGuidance "See docs/wiki/phase-1-mailbox-setup.md Section 5 to create/update the connector manually via the Power Platform portal."
}

function Step-Dataverse {
    Invoke-Step "Deploy Dataverse Classification Tables" {
        & (Join-Path $RepoRoot "dataverse\scripts\deploy-dataverse-tables.ps1") `
            -DataverseUrl (Get-EnvValue "DATAVERSE_ENVIRONMENT_URL") `
            -TenantId (Get-EnvValue "TENANT_ID") `
            -ClientId (Get-EnvValue "CLIENT_ID") `
            -ClientSecret (Get-EnvValue "CLIENT_SECRET") `
            -PublisherPrefix (Get-EnvValue "DATAVERSE_PUBLISHER_PREFIX")
    } -ManualGuidance "See dataverse/README.md for manual table creation steps."
    $seed = Read-Prompt "Seed sample classification rules now? (y/n)" "n"
    if ($seed -eq 'y') {
        Invoke-Step "Seed Sample Classifications" {
            & (Join-Path $RepoRoot "dataverse\scripts\seed-sample-classifications.ps1") `
                -DataverseUrl (Get-EnvValue "DATAVERSE_ENVIRONMENT_URL") `
                -TenantId (Get-EnvValue "TENANT_ID") `
                -ClientId (Get-EnvValue "CLIENT_ID") `
                -ClientSecret (Get-EnvValue "CLIENT_SECRET") `
                -PublisherPrefix (Get-EnvValue "DATAVERSE_PUBLISHER_PREFIX")
        }
    }
}

function Step-Diagnostics {
    Write-Heading "Running diagnostics"
    $script:DiagnosticResults = @()

    Invoke-DiagnosticCheck -Name "App Registration Credentials" `
        -ScriptPath (Join-Path $RepoRoot "docs\wiki\scripts\test-app-registration.ps1") `
        -Arguments @{ ClientId = (Get-EnvValue "CLIENT_ID"); ClientSecret = (Get-EnvValue "CLIENT_SECRET"); TenantId = (Get-EnvValue "TENANT_ID") } `
        -RequiredEnvKeys @("CLIENT_ID", "CLIENT_SECRET", "TENANT_ID")

    Invoke-DiagnosticCheck -Name "App Service Reachability" `
        -ScriptPath (Join-Path $RepoRoot "backend-service\scripts\test-app-service.ps1") `
        -Arguments @{ BackendUrl = (Get-EnvValue "BACKEND_URL") } `
        -RequiredEnvKeys @("BACKEND_URL")

    Invoke-DiagnosticCheck -Name "Backend Functional Tests (8 endpoints)" `
        -ScriptPath (Join-Path $RepoRoot "backend-service\scripts\test-backend.ps1") `
        -Arguments @{ BackendUrl = (Get-EnvValue "BACKEND_URL"); MailboxAddress = (Get-EnvValue "MAILBOX_ADDRESS") } `
        -RequiredEnvKeys @("BACKEND_URL")

    Invoke-DiagnosticCheck -Name "Mailbox Scope Restriction" `
        -ScriptPath (Join-Path $RepoRoot "docs\wiki\scripts\confirm-mailbox-scope-restriction.ps1") `
        -Arguments @{ ClientId = (Get-EnvValue "CLIENT_ID"); MailboxAddress = (Get-EnvValue "MAILBOX_ADDRESS") } `
        -RequiredEnvKeys @("CLIENT_ID", "MAILBOX_ADDRESS", "SECURITY_GROUP_NAME") `
        -SkipGuidance "Requires SECURITY_GROUP_NAME (set once the Shared Mailbox Access step has created the Application Access Policy)."

    Write-Host ""
    Write-Heading "Diagnostics Summary"
    foreach ($r in $script:DiagnosticResults) {
        switch ($r.Status) {
            "Pass" { Write-Ok $r.Name }
            "Skipped" { Write-Warn2 "$($r.Name) - skipped ($($r.Detail))" }
            "Fail" { Write-Fail "$($r.Name) - $($r.Detail)" }
        }
    }
    $failCount = ($script:DiagnosticResults | Where-Object { $_.Status -eq "Fail" }).Count
    if ($failCount -gt 0) {
        Write-Host ""
        Write-Warn2 "$failCount check(s) failed. Scroll up to see the failing script's output, fix the issue, then re-run diagnostics."
    }
}

function Show-Config {
    Write-Heading "Current configuration ($EnvFile)"
    foreach ($key in $script:EnvVars.Keys) {
        $value = $script:EnvVars[$key]
        if ($key -match 'SECRET|PASSWORD') { $value = if ($value) { "********" } else { "" } }
        Write-Host ("  {0,-30} {1}" -f $key, $value)
    }
}

function Show-UpdateMenu {
    while ($true) {
        Write-Heading "Update & Redeploy"
        Write-Host "  1) Redeploy backend code only"
        Write-Host "  2) Re-apply App Service settings"
        Write-Host "  3) Redeploy custom connector"
        Write-Host "  4) Redeploy Dataverse tables"
        Write-Host "  5) Rotate app registration client secret"
        Write-Host "  0) Back"
        switch (Read-Prompt "Choice" "0") {
            "1" { Invoke-Step "Redeploy Backend" { & (Join-Path $RepoRoot "backend-service\scripts\deploy-backend.ps1") -ResourceGroup (Get-EnvValue "RESOURCE_GROUP") -AppServiceName (Get-EnvValue "APP_SERVICE_NAME") -TenantId (Get-EnvValue "TENANT_ID") -SubscriptionId (Get-EnvValue "AZURE_SUBSCRIPTION_ID") } }
            "2" { Step-ConfigureAndDeployBackend }
            "3" { Step-CustomConnector }
            "4" { Step-Dataverse }
            "5" {
                Invoke-Step "Rotate Client Secret" {
                    $result = az ad app credential reset --id (Get-EnvValue "CLIENT_ID") --years 1 --append -o json | ConvertFrom-Json
                    Set-EnvValue "CLIENT_SECRET" $result.password
                    & (Join-Path $RepoRoot "backend-service\scripts\configure-app-service.ps1") -ResourceGroup (Get-EnvValue "RESOURCE_GROUP") -AppServiceName (Get-EnvValue "APP_SERVICE_NAME") -ClientId (Get-EnvValue "CLIENT_ID") -ClientSecret (Get-EnvValue "CLIENT_SECRET") -TenantId (Get-EnvValue "TENANT_ID") -SubscriptionId (Get-EnvValue "AZURE_SUBSCRIPTION_ID")
                }
            }
            "0" { return }
            default { Write-Warn2 "Unknown choice" }
        }
    }
}

# ---------------------------------------------------------------------------
# Main menu
# ---------------------------------------------------------------------------

$script:State = Read-State

Write-Host ""
Write-Host "#############################################################" -ForegroundColor Magenta
Write-Host "#   Bridge365 Onboarding Wizard                            #" -ForegroundColor Magenta
Write-Host "#############################################################" -ForegroundColor Magenta

Initialize-EnvFile
Test-Prerequisites | Out-Null
Get-AzureContext | Out-Null
Initialize-Naming

while ($true) {
    Write-Heading "Main Menu (App: $(Get-EnvValue 'APP_BASE_NAME'), Postfix: $($script:State.Postfix))"
    Write-Host "  1) Full Guided Setup (runs everything below in order)"
    Write-Host "  2) App Registration + API Permissions + Admin Consent"
    Write-Host "  3) Shared Mailbox Access Restriction"
    Write-Host "  4) Create Azure Resources (Resource Group + App Service)"
    Write-Host "  5) Configure Settings & Deploy Backend Code"
    Write-Host "  6) Security Hardening (Easy Auth, Allowlist, Key Vault)"
    Write-Host "  7) Generate & Deploy Custom Connector"
    Write-Host "  8) Deploy Dataverse Tables"
    Write-Host "  9) Update & Redeploy"
    Write-Host " 10) Run Diagnostics"
    Write-Host " 11) Show Current Configuration"
    Write-Host "  0) Exit"

    $choice = Read-Prompt "Choice" "1"
    switch ($choice) {
        "1" {
            Step-AppRegistration
            Step-MailboxAccess
            Step-AzureResources
            Step-ConfigureAndDeployBackend
            Step-SecurityHardening
            Step-CustomConnector
            Step-Dataverse
            Step-Diagnostics
            Write-Ok "Full guided setup finished. Review any [!]/[X] lines above for manual follow-up."
        }
        "2" { Step-AppRegistration }
        "3" { Step-MailboxAccess }
        "4" { Step-AzureResources }
        "5" { Step-ConfigureAndDeployBackend }
        "6" { Step-SecurityHardening }
        "7" { Step-CustomConnector }
        "8" { Step-Dataverse }
        "9" { Show-UpdateMenu }
        "10" { Step-Diagnostics }
        "11" { Show-Config }
        "0" { Write-Host "Bye!" -ForegroundColor Cyan; exit 0 }
        default { Write-Warn2 "Unknown choice" }
    }
}