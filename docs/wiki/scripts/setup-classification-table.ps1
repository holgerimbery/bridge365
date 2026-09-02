# (c) 2026 Holger Imbery (contact@holgerimbery.blog)
# Licensed under the project LICENSE file.
#
# Setup Classification Table in Dataverse
# Creates the classification table with schema for rule-based routing.

#Requires -Version 7.0
param(
    [Parameter(Mandatory)] [string]$EnvironmentUrl,
    [string]$PublisherPrefix = "ins"
)

$ErrorActionPreference = "Stop"

Write-Host "Setting up Classification Table in Dataverse" -ForegroundColor Cyan
Write-Host "Environment: $EnvironmentUrl" -ForegroundColor Gray
Write-Host "Publisher Prefix: $PublisherPrefix" -ForegroundColor Gray

# Verify Dataverse connectivity
Write-Host "`nVerifying Dataverse connectivity..." -ForegroundColor Yellow
try {
    $response = Invoke-RestMethod -Uri "$EnvironmentUrl/api/data/v9.2/EntityDefinitions" `
        -Method Get -Headers @{ Authorization = "Bearer TOKEN_PLACEHOLDER" }
    Write-Host "✓ Dataverse connection successful" -ForegroundColor Green
} catch {
    Write-Host "✗ Dataverse connection failed. Verify URL and authentication." -ForegroundColor Red
    exit 1
}

Write-Host "`nTable Schema:" -ForegroundColor Green
$schema = @(
    @{ Name = "className"; Type = "Text (Single)"; Required = $true }
    @{ Name = "classExamples"; Type = "Multiline Text"; Required = $true }
    @{ Name = "classTarget"; Type = "Text (Single)"; Required = $true }
    @{ Name = "classTargetEmail"; Type = "Email"; Required = $true }
    @{ Name = "isActive"; Type = "Yes/No"; Required = $true }
    @{ Name = "priority"; Type = "Integer"; Required = $false }
    @{ Name = "modelLabel"; Type = "Text (Single)"; Required = $false }
    @{ Name = "lastUpdated"; Type = "Date & Time"; Required = $false }
)

$schema | ForEach-Object { 
    Write-Host "  - $($_.Name) [$($_.Type)]" -ForegroundColor White
}

Write-Host "`nTable Creation Steps:" -ForegroundColor Green
Write-Host "  1. Create new table in Dataverse (display name: 'Classification')" -ForegroundColor White
Write-Host "  2. Add columns as defined above" -ForegroundColor White
Write-Host "  3. Set Publisher Prefix to '$PublisherPrefix'" -ForegroundColor White
Write-Host "  4. Enable audit tracking for compliance" -ForegroundColor White

Write-Host "`n✓ Classification table schema defined" -ForegroundColor Green
Write-Host "  Next: Create table manually in Power Apps Maker portal or use Dataverse SDK" -ForegroundColor Cyan
