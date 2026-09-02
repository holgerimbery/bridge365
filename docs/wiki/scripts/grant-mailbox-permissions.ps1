# (c) 2026 Holger Imbery (contact@holgerimbery.blog)
# Licensed under the project LICENSE file.
# Restricts an app-only Graph application (Mail.Read/Mail.Send) to only
# access the specified shared mailbox, instead of every mailbox in the tenant.

param(
    [string]$ClientId,
    [string]$MailboxAddress,
    [string]$SecurityGroupName
)

# Load from .env if parameters not provided
function Load-EnvFile {
    param([string]$EnvPath)
    $env_vars = @{}
    if (Test-Path $EnvPath) {
        Get-Content $EnvPath | Where-Object { $_ -match '=' -and -not $_.StartsWith('#') } | ForEach-Object {
            $key, $value = $_ -split '=', 2
            $env_vars[$key.Trim()] = $value.Trim()
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
    if (-not $SecurityGroupName) { $SecurityGroupName = $env_vars['SECURITY_GROUP_NAME'] }
}

# Validate
if (-not $ClientId -or -not $MailboxAddress -or -not $SecurityGroupName) {
    Write-Error "Missing required parameters: ClientId, MailboxAddress, SecurityGroupName"
    Write-Host "Provide via CLI parameters or .env file in the repo root" -ForegroundColor Yellow
    exit 1
}

Connect-ExchangeOnline

# 1. Create a mail-enabled security group scoped to this app (if it doesn't exist yet)
$Group = Get-DistributionGroup -Identity $SecurityGroupName -ErrorAction SilentlyContinue
if (-not $Group) {
    New-DistributionGroup -Name $SecurityGroupName -Type Security | Out-Null
    Write-Host "Created mail-enabled security group: $SecurityGroupName" -ForegroundColor Cyan
}

# 2. Add the shared mailbox as a member of the group
Add-DistributionGroupMember -Identity $SecurityGroupName -Member $MailboxAddress -ErrorAction SilentlyContinue

# 3. Restrict the app so it can only access mailboxes in this group
New-ApplicationAccessPolicy -AccessRight RestrictAccess `
    -AppId $ClientId `
    -PolicyScopeGroupId $SecurityGroupName `
    -Description "Restrict $ClientId to shared mailbox $MailboxAddress"

Write-Host "Application access policy created: $ClientId restricted to $SecurityGroupName" -ForegroundColor Green
