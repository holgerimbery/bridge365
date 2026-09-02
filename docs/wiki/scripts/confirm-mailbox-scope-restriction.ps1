# (c) 2026 Holger Imbery (contact@holgerimbery.blog)
# Licensed under the project LICENSE file.
# Re-verifies the Application Access Policy created in Step 3.5, confirming the
# app registration can only reach the intended shared mailbox and not every
# mailbox in the tenant. Run this periodically as part of your security checklist.

param(
    [string]$ClientId,
    [string]$MailboxAddress
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

$RepoRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$env_file = Join-Path $RepoRoot ".env"
if (Test-Path $env_file) {
    $env_vars = Load-EnvFile $env_file
    if (-not $ClientId) { $ClientId = $env_vars['CLIENT_ID'] }
    if (-not $MailboxAddress) { $MailboxAddress = $env_vars['MAILBOX_ADDRESS'] }
}

# Validate
if (-not $ClientId -or -not $MailboxAddress) {
    Write-Error "Missing required parameters: ClientId, MailboxAddress"
    Write-Host "Provide via CLI parameters or .env file in the repo root" -ForegroundColor Yellow
    exit 1
}

if (-not (Get-ConnectionInformation)) { Connect-ExchangeOnline }

Test-ApplicationAccessPolicy -Identity $MailboxAddress -AppId $ClientId
