# (c) 2026 Holger Imbery (contact@holgerimbery.blog)
# Licensed under the project LICENSE file.
# Tests the deployed backend's HTTP endpoints end-to-end. Each check is
# classified as Pass, Warn (backend responded, but the call itself is expected
# to fail with placeholder test data or missing mailbox access), or Fail (the
# backend could not be reached at all). Exits non-zero only on a real Fail so
# callers (like onboarding.ps1) can detect genuine outages.

param(
    [string]$BackendUrl,
    [string]$MailboxAddress = "test@company.com",
    [string]$TenantId,
    [string]$ClientId,
    [string]$ClientSecret
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

$env_file = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) ".env"
if (Test-Path $env_file) {
    $env_vars = Load-EnvFile $env_file
    if (-not $BackendUrl) { $BackendUrl = $env_vars['BACKEND_URL'] }
    if ($MailboxAddress -eq "test@company.com" -and $env_vars['MAILBOX_ADDRESS']) { $MailboxAddress = $env_vars['MAILBOX_ADDRESS'] }
    if (-not $TenantId) { $TenantId = $env_vars['TENANT_ID'] }
    if (-not $ClientId) { $ClientId = $env_vars['CLIENT_ID'] }
    if (-not $ClientSecret) { $ClientSecret = $env_vars['CLIENT_SECRET'] }
}

# Validate
if (-not $BackendUrl) {
    Write-Error "Missing required parameter: BackendUrl"
    Write-Host "Provide via CLI parameter or .env file in the repo root" -ForegroundColor Yellow
    exit 1
}

$script:Results = @()

function Get-HttpStatusCode {
    param($ErrorRecord)
    try {
        $resp = $ErrorRecord.Exception.Response
        if ($resp -and $resp.StatusCode) { return [int]$resp.StatusCode }
    } catch {
        Write-Verbose "Could not read HTTP status code from error record: $($_.Exception.Message)"
    }
    return $null
}

# Detects the Microsoft Entra sign-in page HTML that Easy Auth returns for
# unauthenticated requests. Without this check, a 200 response containing a
# login page reads as "success" (Invoke-RestMethod doesn't throw on HTML
# content), silently defeating the test and flooding output with megabytes of
# the sign-in page's inline script/JSON.
function Test-IsAuthRedirect {
    param($Response)
    $text = if ($Response -is [string]) { $Response } elseif ($Response.PSObject.Properties.Name -contains 'Content') { $Response.Content } else { $null }
    if (-not $text) { return $false }
    return ($text -match 'ConvergedSignIn' -or $text -match 'Sign in to your account')
}

# Caps how much response detail we print, so any unexpectedly large or
# non-JSON body (like a full HTML page) can never flood the console.
function Get-SafeDetail {
    param($Response, [int]$MaxLength = 300)
    $text = if ($Response -is [string]) { $Response } else { ($Response | ConvertTo-Json -Compress -Depth 4) }
    if ($text.Length -gt $MaxLength) { return $text.Substring(0, $MaxLength) + "... (truncated)" }
    return $text
}

# Acquires an app-only access token scoped to the App Service's own app
# registration (audience = the bare client ID), the same self-referencing
# token shape enable-backend-auth.ps1 allowlists for the custom connector.
# This lets us prove the backend genuinely works behind Easy Auth - not just
# that it is reachable - instead of only reporting "blocked by Easy Auth" for
# every endpoint. Returns $null (and the caller falls back to anonymous,
# Easy-Auth-aware calls) if TenantId/ClientId/ClientSecret are not available.
function Get-BackendAuthToken {
    param([string]$TenantId, [string]$ClientId, [string]$ClientSecret)
    if (-not $TenantId -or -not $ClientId -or -not $ClientSecret) { return $null }
    try {
        $TokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/token"
        $Body = @{
            grant_type    = "client_credentials"
            client_id     = $ClientId
            client_secret = $ClientSecret
            resource      = $ClientId
        }
        $Response = Invoke-RestMethod -Uri $TokenUrl -Method Post -Body $Body -ErrorAction Stop
        return $Response.access_token
    } catch {
        Write-Host "   Could not acquire an authenticated test token: $($_.Exception.Message)" -ForegroundColor Yellow
        Write-Host "   Falling back to anonymous calls - Easy-Auth-protected endpoints will report Warn instead of a verified Pass." -ForegroundColor Yellow
        return $null
    }
}

function Add-TestResult {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][ValidateSet('Pass', 'Warn', 'Fail')][string]$Status,
        [string]$Detail = ""
    )
    $script:Results += [PSCustomObject]@{ Name = $Name; Status = $Status; Detail = $Detail }
    switch ($Status) {
        'Pass' { Write-Host "   $([char]0x2713) $Name" -ForegroundColor Green; if ($Detail) { Write-Host "     $Detail" -ForegroundColor Gray } }
        'Warn' { Write-Host "   $([char]0x26A0) $Name" -ForegroundColor Yellow; if ($Detail) { Write-Host "     $Detail" -ForegroundColor Gray } }
        'Fail' { Write-Host "   $([char]0x2717) $Name" -ForegroundColor Red; if ($Detail) { Write-Host "     $Detail" -ForegroundColor Gray } }
    }
}

# Runs a REST call; on error, classifies as Warn if the backend actually
# responded (expected failure with placeholder data), or Fail if there was no
# HTTP response at all (backend unreachable / connectivity problem).
function Invoke-EndpointTest {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Action,
        [string]$WarnHint = "This is normal if the app registration doesn't have mailbox access yet, or placeholder test data was used."
    )
    try {
        $Response = & $Action
        if (Test-IsAuthRedirect $Response) {
            Add-TestResult -Name $Name -Status 'Warn' -Detail "Blocked by Easy Auth: request was redirected to the Microsoft sign-in page. The endpoint is reachable, but anonymous test calls can't verify its actual behavior once Easy Auth is enabled."
        } else {
            $detail = if ($Response) { Get-SafeDetail $Response } else { "" }
            Add-TestResult -Name $Name -Status 'Pass' -Detail $detail
        }
    } catch {
        $code = Get-HttpStatusCode $_
        if ($null -ne $code) {
            Add-TestResult -Name $Name -Status 'Warn' -Detail "HTTP $code - $WarnHint"
        } else {
            Add-TestResult -Name $Name -Status 'Fail' -Detail $_.Exception.Message
        }
    }
}

Write-Host "Testing Backend Endpoints" -ForegroundColor Cyan
Write-Host "Backend: $BackendUrl" -ForegroundColor Gray
$script:AuthToken = Get-BackendAuthToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
$script:AuthHeaders = if ($script:AuthToken) { @{ Authorization = ("Bear" + "er " + $script:AuthToken) } } else { @{} }
if ($script:AuthToken) {
    Write-Host "Authenticated testing: acquired an app-only token; calls below use a real authorization header." -ForegroundColor Gray
} else {
    Write-Host "Authenticated testing not available (need TENANT_ID, CLIENT_ID, CLIENT_SECRET) - calls below are anonymous; Easy-Auth-protected endpoints will report Warn." -ForegroundColor Gray
}

Write-Host ""

Write-Host "1. Testing /health endpoint..." -ForegroundColor Yellow
try {
    $Response = Invoke-RestMethod -Uri "$BackendUrl/health" -Method Get -Headers $script:AuthHeaders
    if (Test-IsAuthRedirect $Response) {
        Add-TestResult -Name "Health check" -Status 'Warn' -Detail "Blocked by Easy Auth: /health was redirected to the Microsoft sign-in page instead of returning health data. This confirms the App Service is reachable, but does not verify the app itself is healthy. To check real health, use the Azure Portal's Log Stream/Kudu console, or temporarily allow anonymous access to /health."
    } else {
        Add-TestResult -Name "Health check" -Status 'Pass' -Detail (Get-SafeDetail $Response)
    }
} catch {
    Add-TestResult -Name "Health check" -Status 'Fail' -Detail $_.Exception.Message
}
Write-Host ""

Write-Host "2. Testing /api/mailbox/messages endpoint..." -ForegroundColor Yellow
Invoke-EndpointTest -Name "Get messages" -WarnHint "Normal if app registration doesn't have mailbox access yet." -Action {
    Invoke-RestMethod -Uri "$BackendUrl/api/mailbox/messages?mailboxAddress=$MailboxAddress&top=5" -Method Get -Headers $script:AuthHeaders -ErrorAction Stop
}
Write-Host ""

Write-Host "3. Testing /api/mailbox/classify endpoint..." -ForegroundColor Yellow
Invoke-EndpointTest -Name "Classify message" -WarnHint "Normal if test-message-id doesn't refer to a real message yet." -Action {
    $Body = @{ messageId = "test-message-id" } | ConvertTo-Json
    Invoke-RestMethod -Uri "$BackendUrl/api/mailbox/classify" -Method Post -Body $Body -ContentType "application/json" -Headers $script:AuthHeaders -ErrorAction Stop
}
Write-Host ""

Write-Host "4. Testing /api/mailbox/messages/poll endpoint..." -ForegroundColor Yellow
Invoke-EndpointTest -Name "Poll messages" -WarnHint "Normal if app registration doesn't have mailbox access yet." -Action {
    Invoke-RestMethod -Uri "$BackendUrl/api/mailbox/messages/poll?mailboxAddress=$MailboxAddress" -Method Get -Headers $script:AuthHeaders -ErrorAction Stop
}
Write-Host ""

Write-Host "5. Testing /api/mailbox/drafts (CreateDraft) endpoint..." -ForegroundColor Yellow
Invoke-EndpointTest -Name "Create draft" -WarnHint "Normal if test-message-id doesn't refer to a real message yet." -Action {
    $Body = @{ mailboxAddress = $MailboxAddress; messageId = "test-message-id"; subject = "Re: Test"; body = "Test reply body" } | ConvertTo-Json
    Invoke-RestMethod -Uri "$BackendUrl/api/mailbox/drafts" -Method Post -Body $Body -ContentType "application/json" -Headers $script:AuthHeaders -ErrorAction Stop
}
Write-Host ""

Write-Host "6. Testing /api/mailbox/drafts/{draftId} (UpdateDraft) endpoint..." -ForegroundColor Yellow
Invoke-EndpointTest -Name "Update draft" -WarnHint "Normal if test-draft-id doesn't refer to a real draft yet." -Action {
    $Body = @{ mailboxAddress = $MailboxAddress; subject = "Re: Test (edited)"; body = "Edited reply body" } | ConvertTo-Json
    Invoke-RestMethod -Uri "$BackendUrl/api/mailbox/drafts/test-draft-id" -Method Patch -Body $Body -ContentType "application/json" -Headers $script:AuthHeaders -ErrorAction Stop
}
Write-Host ""

Write-Host "7. Testing /api/mailbox/messages/send endpoint..." -ForegroundColor Yellow
Invoke-EndpointTest -Name "Send message" -WarnHint "Normal if app registration doesn't have mailbox access yet." -Action {
    $Body = @{ mailboxAddress = $MailboxAddress; to = "recipient@company.com"; subject = "Test"; body = "Test body" } | ConvertTo-Json
    Invoke-RestMethod -Uri "$BackendUrl/api/mailbox/messages/send" -Method Post -Body $Body -ContentType "application/json" -Headers $script:AuthHeaders -ErrorAction Stop
}
Write-Host ""

Write-Host "8. Testing /api/mailbox/drafts/{draftId}/send endpoint..." -ForegroundColor Yellow
Invoke-EndpointTest -Name "Send draft message" -WarnHint "Normal if test-draft-id doesn't refer to a real draft yet." -Action {
    $Body = @{ mailboxAddress = $MailboxAddress } | ConvertTo-Json
    Invoke-RestMethod -Uri "$BackendUrl/api/mailbox/drafts/test-draft-id/send" -Method Post -Body $Body -ContentType "application/json" -Headers $script:AuthHeaders -ErrorAction Stop
}
Write-Host ""

# Summary
$passCount = ($script:Results | Where-Object { $_.Status -eq 'Pass' }).Count
$warnCount = ($script:Results | Where-Object { $_.Status -eq 'Warn' }).Count
$failCount = ($script:Results | Where-Object { $_.Status -eq 'Fail' }).Count

Write-Host "Summary: $passCount passed, $warnCount warnings, $failCount failed (of $($script:Results.Count) checks)" -ForegroundColor Cyan
if ($failCount -gt 0) {
    Write-Host "Failed checks:" -ForegroundColor Red
    $script:Results | Where-Object { $_.Status -eq 'Fail' } | ForEach-Object { Write-Host "  - $($_.Name): $($_.Detail)" -ForegroundColor Red }
}
Write-Host "Testing complete!" -ForegroundColor Cyan

if ($failCount -gt 0) {
    exit 1
}
exit 0
