# (c) 2026 Holger Imbery (contact@holgerimbery.blog)
# Licensed under the project LICENSE file.

param(
    [Parameter(Mandatory)] [string]$BackendUrl,
    [string]$MailboxAddress = "test@company.com"
)

Write-Host "Testing Backend Endpoints" -ForegroundColor Cyan
Write-Host "Backend: $BackendUrl" -ForegroundColor Gray
Write-Host ""

# Test 1: Health endpoint
Write-Host "1. Testing /health endpoint..." -ForegroundColor Yellow
try {
    $Response = Invoke-RestMethod -Uri "$BackendUrl/health" -Method Get
    Write-Host "   ✓ Health check passed" -ForegroundColor Green
    Write-Host "   Response: $($Response | ConvertTo-Json)" -ForegroundColor Gray
} catch {
    Write-Host "   ✗ Health check failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# Test 2: Get messages endpoint
Write-Host "2. Testing /api/mailbox/messages endpoint..." -ForegroundColor Yellow
try {
    $Response = Invoke-RestMethod -Uri "$BackendUrl/api/mailbox/messages?mailboxAddress=$MailboxAddress&top=5" `
        -Method Get -ErrorAction Stop
    Write-Host "   ✓ Messages endpoint works" -ForegroundColor Green
    Write-Host "   Found $($Response.value.Count) messages" -ForegroundColor Gray
} catch {
    Write-Host "   ⚠ Warning: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "     (This is normal if app registration doesn't have mailbox access yet)" -ForegroundColor Gray
}

Write-Host ""

# Test 3: Classify endpoint
Write-Host "3. Testing /api/mailbox/classify endpoint..." -ForegroundColor Yellow
try {
    $Body = @{ messageId = "test-message-id" } | ConvertTo-Json
    $Response = Invoke-RestMethod -Uri "$BackendUrl/api/mailbox/classify" `
        -Method Post -Body $Body -ContentType "application/json"
    Write-Host "   ✓ Classify endpoint works" -ForegroundColor Green
    Write-Host "   Response: $($Response | ConvertTo-Json)" -ForegroundColor Gray
} catch {
    Write-Host "   ✗ Classify endpoint failed: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""

# Test 4: Poll (trigger) endpoint
Write-Host "4. Testing /api/mailbox/messages/poll endpoint..." -ForegroundColor Yellow
try {
    $Response = Invoke-RestMethod -Uri "$BackendUrl/api/mailbox/messages/poll?mailboxAddress=$MailboxAddress" `
        -Method Get -ErrorAction Stop
    Write-Host "   ✓ Poll endpoint works" -ForegroundColor Green
    Write-Host "   Found $($Response.value.Count) new messages" -ForegroundColor Gray
} catch {
    Write-Host "   ⚠ Warning: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "     (This is normal if app registration doesn't have mailbox access yet)" -ForegroundColor Gray
}

# Test 5: Send message endpoint
Write-Host "5. Testing /api/mailbox/messages/send endpoint..." -ForegroundColor Yellow
try {
    $Body = @{ mailboxAddress = $MailboxAddress; to = "recipient@company.com"; subject = "Test"; body = "Test body" } | ConvertTo-Json
    $Response = Invoke-RestMethod -Uri "$BackendUrl/api/mailbox/messages/send" `
        -Method Post -Body $Body -ContentType "application/json" -ErrorAction Stop
    Write-Host "   ✓ Send message endpoint works" -ForegroundColor Green
    Write-Host "   Response: $($Response | ConvertTo-Json)" -ForegroundColor Gray
} catch {
    Write-Host "   ⚠ Warning: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "     (This is normal if app registration doesn't have mailbox access yet)" -ForegroundColor Gray
}

Write-Host ""

# Test 6: Send draft message endpoint
Write-Host "6. Testing /api/mailbox/drafts/{draftId}/send endpoint..." -ForegroundColor Yellow
try {
    $Body = @{ mailboxAddress = $MailboxAddress } | ConvertTo-Json
    $Response = Invoke-RestMethod -Uri "$BackendUrl/api/mailbox/drafts/test-draft-id/send" `
        -Method Post -Body $Body -ContentType "application/json" -ErrorAction Stop
    Write-Host "   ✓ Send draft message endpoint works" -ForegroundColor Green
    Write-Host "   Response: $($Response | ConvertTo-Json)" -ForegroundColor Gray
} catch {
    Write-Host "   ⚠ Warning: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "     (This is normal if app registration doesn't have mailbox access yet)" -ForegroundColor Gray
}
Write-Host ""
Write-Host "Testing complete!" -ForegroundColor Cyan
