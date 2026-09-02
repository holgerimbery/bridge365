# (c) 2026 Holger Imbery (contact@holgerimbery.blog)
# Licensed under the project LICENSE file.

param(
    [Parameter(Mandatory)] [string]$ResourceGroup,
    [Parameter(Mandatory)] [string]$AppServiceName,
    [Parameter(Mandatory)] [string]$ClientId,
    [Parameter(Mandatory)] [string]$ClientSecret,
    [Parameter(Mandatory)] [string]$TenantId
)

az webapp config appsettings set `
    --resource-group $ResourceGroup `
    --name $AppServiceName `
    --settings `
        AZURE_CLIENT_ID=$ClientId `
        AZURE_CLIENT_SECRET=$ClientSecret `
        AZURE_TENANT_ID=$TenantId

Write-Host "✓ Environment variables configured" -ForegroundColor Green
