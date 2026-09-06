# (c) 2026 Holger Imbery (contact@holgerimbery.blog)
# Licensed under the project LICENSE file.
# Creates (or reuses) the Entra ID app registration used by the backend
# service to call Microsoft Graph app-only (Phase 1, Step 3.1-3.2 of
# docs/wiki/phase-1-mailbox-setup.md - previously a manual portal-only
# procedure). Adds the Mail.Read/Mail.Send Microsoft Graph application
# permissions, attempts admin consent, and verifies consent actually landed
# by inspecting the service principal's appRoleAssignments directly (the
# only reliable check - az ad app permission list-grants only shows
# delegated grants and misleadingly returns [] for application permissions).
#
# Also requests the delegated Microsoft Graph "User.Read" permission
# (Scope, not Role). This isn't used by the backend service itself, but
# it is required for any INTERACTIVE sign-in against this app registration
# - e.g. creating/testing a connection for the custom connector in the
# Power Platform maker portal, which performs a delegated AAD OAuth login.
# Without it, Azure AD rejects the sign-in with AADSTS90008 ("must require
# access to Microsoft Graph by specifying at least 'Sign in and read user
# profile' permission"), since apps created purely via 'az ad app create'
# don't get this default permission the portal wizard normally adds.
#
# Idempotent: re-running with the same -DisplayName reuses the existing app
# registration instead of creating a duplicate.

param(
    [string]$DisplayName,
    [string[]]$GraphAppPermissions = @('Mail.Read', 'Mail.Send'),
    [string[]]$GraphDelegatedPermissions = @('User.Read'),
    [int]$SecretExpiryMonths = 12
)

$ErrorActionPreference = "Stop"
$GraphResourceAppId = "00000003-0000-0000-c000-000000000000"

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

$RepoRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$env_file = Join-Path $RepoRoot ".env"
if (Test-Path $env_file) {
    $env_vars = Load-EnvFile $env_file
    if (-not $DisplayName) { $DisplayName = $env_vars['APP_REGISTRATION_NAME'] }
}
if (-not $DisplayName) { $DisplayName = "SharedMailboxClassifier" }

Write-Host "== App registration: $DisplayName ==" -ForegroundColor Cyan

# 1. Create or reuse the app registration
$existing = az ad app list --display-name $DisplayName --query "[0]" -o json 2>$null | ConvertFrom-Json
if ($existing) {
    Write-Host "Reusing existing app registration '$DisplayName' (appId: $($existing.appId))" -ForegroundColor Yellow
    $AppId = $existing.appId
} else {
    Write-Host "Creating app registration '$DisplayName'..." -ForegroundColor Cyan
    $created = az ad app create --display-name $DisplayName --sign-in-audience AzureADMyOrg -o json | ConvertFrom-Json
    if (-not $created) {
        Write-Error "Failed to create app registration. Do you have 'Application Developer' or higher rights in Entra ID?"
        exit 1
    }
    $AppId = $created.appId
    Write-Host "Created app registration (appId: $AppId)" -ForegroundColor Green
}

# 2. Create (or reuse) the service principal
$sp = az ad sp list --filter "appId eq '$AppId'" --query "[0]" -o json 2>$null | ConvertFrom-Json
if (-not $sp) {
    az ad sp create --id $AppId -o none
    $sp = az ad sp show --id $AppId -o json | ConvertFrom-Json
}
$SpObjectId = $sp.id

# 3. Resolve requested permission names to Graph appRoleIds dynamically
#    (looked up live instead of hardcoded, since GUIDs are easy to
#    mistype/mismatch across Graph API versions).
$graphSp = az ad sp show --id $GraphResourceAppId -o json | ConvertFrom-Json
$resourceAccess = @()
$resolvedRoleIds = @{}
foreach ($permName in $GraphAppPermissions) {
    $role = $graphSp.appRoles | Where-Object { $_.value -eq $permName -and $_.allowedMemberTypes -contains 'Application' }
    if (-not $role) {
        Write-Warning "Could not resolve Graph application permission '$permName' - skipping. Add it manually via API permissions in the portal."
        continue
    }
    $resolvedRoleIds[$permName] = $role.id
    $resourceAccess += @{ id = $role.id; type = "Role" }
}

$resolvedScopeIds = @{}
foreach ($permName in $GraphDelegatedPermissions) {
    $scope = $graphSp.oauth2PermissionScopes | Where-Object { $_.value -eq $permName }
    if (-not $scope) {
        Write-Warning "Could not resolve Graph delegated permission '$permName' - skipping. Add it manually via API permissions in the portal."
        continue
    }
    $resolvedScopeIds[$permName] = $scope.id
    $resourceAccess += @{ id = $scope.id; type = "Scope" }
}

if ($resourceAccess.Count -gt 0) {
    # Use "az ad app permission add" instead of "az ad app update
    # --required-resource-accesses": it is additive/idempotent per permission
    # and, critically, its failures are not silently swallowed like the
    # single bulk "update" call could be. Each permission is requested
    # individually and its exit code is checked.
    $permArgs = @()
    foreach ($permName in $resolvedRoleIds.Keys) {
        $permArgs += "$($resolvedRoleIds[$permName])=Role"
    }
    foreach ($permName in $resolvedScopeIds.Keys) {
        $permArgs += "$($resolvedScopeIds[$permName])=Scope"
    }
    az ad app permission add --id $AppId --api $GraphResourceAppId --api-permissions $permArgs -o none
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to request Graph permissions (az ad app permission add exited with code $LASTEXITCODE). Add them manually via API permissions in the portal, then re-run this script."
        exit 1
    }

    # Verify the permissions actually landed on the app object instead of
    # trusting the exit code alone - this is what previously failed
    # silently and left API permissions completely empty in the portal.
    $verifyApp = az ad app show --id $AppId --query "requiredResourceAccess" -o json | ConvertFrom-Json
    $verifiedIds = @()
    foreach ($entry in $verifyApp) {
        if ($entry.resourceAppId -eq $GraphResourceAppId) {
            $verifiedIds += $entry.resourceAccess.id
        }
    }
    $allResolved = $resolvedRoleIds + $resolvedScopeIds
    $notRequested = @($allResolved.Keys | Where-Object { $verifiedIds -notcontains $allResolved[$_] })
    if ($notRequested.Count -gt 0) {
        Write-Error "Graph permissions were not found on the app registration after requesting them: $($notRequested -join ', '). Add them manually via API permissions in the portal, then re-run this script."
        exit 1
    }

    Write-Host "Requested Graph permissions: $($resolvedRoleIds.Keys -join ', ') (application), $($resolvedScopeIds.Keys -join ', ') (delegated)" -ForegroundColor Cyan
}

# 4. Attempt admin consent. This requires Global Administrator or Privileged
#    Role Administrator - if it fails, print exact manual steps instead of
#    aborting the whole onboarding run.
try {
    az ad app permission admin-consent --id $AppId -o none 2>$null
    Start-Sleep -Seconds 5
} catch {
    # Consent failures (e.g. insufficient privileges) are expected here and
    # handled below via the appRoleAssignments verification instead of a throw.
    Write-Verbose "admin-consent attempt failed: $($_.Exception.Message)"
}

# 5. Verify consent actually landed by checking appRoleAssignments directly -
#    the only reliable signal (see phase-1-mailbox-setup.md Step 3.2).
$assignments = az rest --method GET --uri "https://graph.microsoft.com/v1.0/servicePrincipals/$SpObjectId/appRoleAssignments" -o json 2>$null | ConvertFrom-Json
$assignedRoleIds = @($assignments.value | ForEach-Object { $_.appRoleId })
$missing = @()
foreach ($permName in $resolvedRoleIds.Keys) {
    if ($assignedRoleIds -notcontains $resolvedRoleIds[$permName]) {
        $missing += $permName
    }
}

if ($missing.Count -eq 0 -and $resolvedRoleIds.Count -gt 0) {
    Write-Host "Admin consent verified via appRoleAssignments for: $($resolvedRoleIds.Keys -join ', ')" -ForegroundColor Green
} else {
    Write-Host ""
    Write-Host "=======================================================================" -ForegroundColor Yellow
    Write-Host " ACTION REQUIRED: Admin consent could not be verified for: $($missing -join ', ')" -ForegroundColor Yellow
    Write-Host "=======================================================================" -ForegroundColor Yellow
    Write-Host "This account likely lacks Global Administrator / Privileged Role" -ForegroundColor Yellow
    Write-Host "Administrator rights needed to grant admin consent for application" -ForegroundColor Yellow
    Write-Host "permissions. Ask a tenant admin to do ONE of the following:" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Option A (Portal):" -ForegroundColor Cyan
    Write-Host "    1. https://portal.azure.com -> Microsoft Entra ID -> App registrations -> $DisplayName" -ForegroundColor Gray
    Write-Host "    2. API permissions -> Grant admin consent for <tenant>" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Option B (CLI, run by a Global Administrator):" -ForegroundColor Cyan
    Write-Host "    az ad app permission admin-consent --id $AppId" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Then re-run this script (or menu option 2) to verify." -ForegroundColor Cyan
    Write-Host "=======================================================================" -ForegroundColor Yellow
    Write-Host ""
}

# 6. Create a client secret. Skipped if -SkipSecret style reuse is desired -
#    callers wanting a fresh secret later should use the onboarding "rotate
#    secret" menu option (az ad app credential reset) instead of re-running this.
$secretResult = az ad app credential reset --id $AppId --years ([math]::Ceiling($SecretExpiryMonths / 12)) --append -o json | ConvertFrom-Json

$TenantId = az account show --query tenantId -o tsv

[PSCustomObject]@{
    AppId           = $AppId
    ObjectId        = $SpObjectId
    TenantId        = $TenantId
    ClientSecret    = $secretResult.password
    ConsentVerified = ($missing.Count -eq 0 -and $resolvedRoleIds.Count -gt 0)
}