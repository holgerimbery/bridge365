# (c) 2026 Holger Imbery (contact@holgerimbery.blog)
# Licensed under the project LICENSE file.
# Enables Azure App Service built-in authentication (Easy Auth) with
# Microsoft Entra ID as the identity provider, so unauthenticated
# requests are rejected before they reach your application code.

param(
    [string]$ResourceGroup,
    [string]$AppServiceName,
    [string]$TenantId,
    [string]$ClientId,
    [string]$SubscriptionId,
    [switch]$SkipDelegatedScopeSetup
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

# Verifies (and optionally switches to) the intended Azure subscription/tenant
# before any resources are modified, so a stale `az login` session can't
# silently target the wrong tenant/subscription.
function Confirm-AzureContext {
    param(
        [string]$ExpectedTenantId,
        [string]$ExpectedSubscriptionId
    )

    if ($ExpectedSubscriptionId) {
        az account set --subscription $ExpectedSubscriptionId
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to switch to subscription '$ExpectedSubscriptionId'. Run 'az login' and verify AZURE_SUBSCRIPTION_ID, then retry."
            exit 1
        }
    }

    if ($ExpectedTenantId) {
        $CurrentTenantId = az account show --query tenantId -o tsv
        if ($LASTEXITCODE -ne 0) {
            Write-Error "Failed to read the current Azure CLI context. Run 'az login' and retry."
            exit 1
        }
        if ($CurrentTenantId -ne $ExpectedTenantId) {
            Write-Error "Azure CLI is logged into tenant '$CurrentTenantId', but TENANT_ID specifies '$ExpectedTenantId'. Run 'az login --tenant $ExpectedTenantId' (and 'az account set --subscription <id>' if you have access to multiple subscriptions), then retry."
            exit 1
        }
    }
}

# Exposes a delegated "user_impersonation" OAuth2 scope on the app
# registration and forces v1-format access tokens, so tokens requested for
# api://<ClientId> (e.g. via `az login --scope` or the custom connector's
# delegated OAuth flow) are actually issued and accepted - without this,
# Azure AD rejects token requests with AADSTS650057 (no scope to request),
# and even after a token is issued, Easy Auth's classic v1 config rejects
# it (issuer mismatch or an un-allowlisted audience, both 401).
function Enable-DelegatedApiScope {
    param(
        [string]$ClientId
    )

    $ObjectId = az ad app show --id $ClientId --query id -o tsv
    if ($LASTEXITCODE -ne 0 -or -not $ObjectId) {
        Write-Error "Failed to look up the app registration object ID for client ID '$ClientId'."
        exit 1
    }

    $ScopeId = "a7e26fb7-ec5a-4179-81c3-daa4d26300b4"
    $Body = @{
        identifierUris = @("api://$ClientId")
        api = @{
            requestedAccessTokenVersion = 1
            oauth2PermissionScopes = @(
                @{
                    adminConsentDescription  = "Allow the app to access the shared mailbox classifier on behalf of the signed-in user."
                    adminConsentDisplayName  = "Access shared mailbox classifier"
                    id                       = $ScopeId
                    isEnabled                = $true
                    type                     = "User"
                    userConsentDescription   = "Allow the app to access the shared mailbox classifier on your behalf."
                    userConsentDisplayName   = "Access shared mailbox classifier"
                    value                    = "user_impersonation"
                }
            )
        }
    } | ConvertTo-Json -Depth 6

    $TempFile = New-TemporaryFile
    Set-Content -Path $TempFile -Value $Body -Encoding utf8

    az rest --method PATCH --uri "https://graph.microsoft.com/v1.0/applications/$ObjectId" --headers "Content-Type=application/json" --body "@$TempFile"
    $ExitCode = $LASTEXITCODE
    Remove-Item $TempFile -ErrorAction SilentlyContinue

    if ($ExitCode -ne 0) {
        Write-Error "Failed to expose the delegated 'user_impersonation' scope on app '$ClientId'. See az CLI output above."
        exit 1
    }
    Write-Host "Delegated scope 'user_impersonation' exposed on api://$ClientId (v1 access tokens)" -ForegroundColor Green
}

$env_file = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) ".env"
if (Test-Path $env_file) {
    $env_vars = Load-EnvFile $env_file
    if (-not $ResourceGroup) { $ResourceGroup = $env_vars['RESOURCE_GROUP'] }
    if (-not $AppServiceName) { $AppServiceName = $env_vars['APP_SERVICE_NAME'] }
    if (-not $TenantId) { $TenantId = $env_vars['TENANT_ID'] }
    if (-not $ClientId) { $ClientId = $env_vars['CLIENT_ID'] }
    if (-not $SubscriptionId) { $SubscriptionId = $env_vars['AZURE_SUBSCRIPTION_ID'] }
}

# Validate
if (-not $ResourceGroup -or -not $AppServiceName -or -not $TenantId -or -not $ClientId) {
    Write-Error "Missing required parameters: ResourceGroup, AppServiceName, TenantId, ClientId"
    Write-Host "Provide via CLI parameters or .env file in the repo root" -ForegroundColor Yellow
    exit 1
}

Confirm-AzureContext -ExpectedTenantId $TenantId -ExpectedSubscriptionId $SubscriptionId

if (-not $SkipDelegatedScopeSetup) {
    Enable-DelegatedApiScope -ClientId $ClientId
}

# Both audiences are allowlisted: "api://<clientId>" for tokens obtained by a
# *different* client requesting our API as the resource (az CLI, manual
# testing), and the bare "<clientId>" for the Power Platform custom connector,
# which requests a token where our own app is both the OAuth client AND the
# resource - Azure AD requires the bare GUID (not the App ID URI) for that
# self-referencing case (AADSTS90009 otherwise).
az webapp auth update `
    --resource-group $ResourceGroup `
    --name $AppServiceName `
    --enabled true `
    --action LoginWithAzureActiveDirectory `
    --aad-client-id $ClientId `
    --aad-token-issuer-url "https://sts.windows.net/$TenantId/" `
    --aad-allowed-token-audiences "api://$ClientId" "$ClientId"

if ($LASTEXITCODE -ne 0) {
    Write-Error "Failed to enable Entra authentication for '$AppServiceName'. See az CLI output above for details."
    exit 1
}
Write-Host "Entra authentication enabled for $AppServiceName" -ForegroundColor Green
