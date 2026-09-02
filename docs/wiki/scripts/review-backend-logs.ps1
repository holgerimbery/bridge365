# (c) 2026 Holger Imbery (contact@holgerimbery.blog)
# Licensed under the project LICENSE file.
# Pulls recent App Service log lines so you can manually verify no
# secrets or raw email content are present before going live.

param(
    [Parameter(Mandatory)] [string]$ResourceGroup,
    [Parameter(Mandatory)] [string]$AppServiceName
)

az webapp log tail --resource-group $ResourceGroup --name $AppServiceName
