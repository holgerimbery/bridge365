# (c) 2026 Holger Imbery (contact@holgerimbery.blog)
# Licensed under the project LICENSE file.
# Sets the tenant and client-id allowlist your backend code checks against
# on every incoming token, in addition to Easy Auth's signature validation.

param(
    [Parameter(Mandatory)] [string]$ResourceGroup,
    [Parameter(Mandatory)] [string]$AppServiceName,
    [Parameter(Mandatory)] [string]$AllowedTenantId,
    [Parameter(Mandatory)] [string]$AllowedClientIds
)

az webapp config appsettings set `
    --resource-group $ResourceGroup `
    --name $AppServiceName `
    --settings `
        ALLOWED_TENANT_ID="$AllowedTenantId" `
        ALLOWED_CLIENT_IDS="$AllowedClientIds"

Write-Host "Allowlist configured on $AppServiceName" -ForegroundColor Green
