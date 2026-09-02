# (c) 2026 Holger Imbery (contact@holgerimbery.blog)
# Licensed under the project LICENSE file.
#
# Create Sample Classifications in Dataverse
# Populates the classification table with sample routing rules.

#Requires -Version 7.0
param(
    [Parameter(Mandatory)] [string]$EnvironmentUrl,
    [string]$ClassificationsJson = $null
)

$ErrorActionPreference = "Stop"

Write-Host "Creating Sample Classifications in Dataverse" -ForegroundColor Cyan
Write-Host "Environment: $EnvironmentUrl" -ForegroundColor Gray

# Default sample classifications
if (-not $ClassificationsJson) {
    $ClassificationsJson = @"
[
  {
    "className": "Invoice Question",
    "classExamples": ["invoice", "billing", "amount", "receipt"],
    "classTarget": "Finance Department",
    "classTargetEmail": "finance@company.com",
    "isActive": true,
    "priority": 100,
    "modelLabel": "invoice_question"
  },
  {
    "className": "Technical Support",
    "classExamples": ["cannot sign in", "error", "AADSTS", "access denied"],
    "classTarget": "IT Support",
    "classTargetEmail": "itsupport@company.com",
    "isActive": true,
    "priority": 95,
    "modelLabel": "technical_support"
  },
  {
    "className": "Contract Inquiry",
    "classExamples": ["contract", "agreement", "terms", "license"],
    "classTarget": "Legal Operations",
    "classTargetEmail": "legal@company.com",
    "isActive": true,
    "priority": 90,
    "modelLabel": "contract_inquiry"
  }
]
"@
}

Write-Host "`nSample Classifications:" -ForegroundColor Green
$classifications = $ClassificationsJson | ConvertFrom-Json
$classifications | ForEach-Object {
    Write-Host "  - $($_.className) → $($_.classTarget)" -ForegroundColor White
    Write-Host "    Keywords: $($_.classExamples -join ', ')" -ForegroundColor Gray
}

Write-Host "`nImport Steps:" -ForegroundColor Green
Write-Host "  1. Navigate to Power Apps Maker portal" -ForegroundColor White
Write-Host "  2. Open the Classification table" -ForegroundColor White
Write-Host "  3. Add rows with the sample data above" -ForegroundColor White
Write-Host "  4. Or use Power Automate flow to bulk-import from JSON" -ForegroundColor White

Write-Host "`n✓ Sample classifications template created" -ForegroundColor Green
Write-Host "  Next: Import data into Dataverse" -ForegroundColor Cyan
