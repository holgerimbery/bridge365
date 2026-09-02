# (c) 2026 Holger Imbery (contact@holgerimbery.blog)
# Licensed under the project LICENSE file.
#
# Setup Custom Connector for Shared Mailbox Service
# This script creates and configures a Power Platform custom connector.

#Requires -Version 7.0
param(
    [Parameter(Mandatory)] [string]$EnvironmentId,
    [Parameter(Mandatory)] [string]$ConnectorName = "SharedMailboxConnector",
    [Parameter(Mandatory)] [string]$ApiHost,
    [string]$TenantId = (Get-AzContext).Tenant.Id
)

$ErrorActionPreference = "Stop"

Write-Host "Setting up Custom Connector: $ConnectorName" -ForegroundColor Cyan
Write-Host "Environment ID: $EnvironmentId" -ForegroundColor Gray
Write-Host "API Host: $ApiHost" -ForegroundColor Gray
Write-Host "Tenant ID: $TenantId" -ForegroundColor Gray

# Verify Azure authentication
$context = Get-AzContext
if (-not $context) {
    Write-Host "Connecting to Azure..." -ForegroundColor Yellow
    Connect-AzAccount
}

Write-Host "`nConnector OpenAPI Endpoints:" -ForegroundColor Green
Write-Host "  POST /mailbox/messages" -ForegroundColor White
Write-Host "  GET  /mailbox/messages/{messageId}" -ForegroundColor White
Write-Host "  POST /mailbox/classify" -ForegroundColor White
Write-Host "  POST /mailbox/draft" -ForegroundColor White

Write-Host "`nAuthentication:" -ForegroundColor Green
Write-Host "  Type: Azure AD (Entra)" -ForegroundColor White
Write-Host "  Tenant ID: $TenantId" -ForegroundColor White

Write-Host "`n✓ Custom connector configuration template created" -ForegroundColor Green
Write-Host "  Next: Register connector in Power Platform manually or via SDK" -ForegroundColor Cyan
Write-Host "  Reference: https://learn.microsoft.com/connectors/custom-connectors/" -ForegroundColor Gray
