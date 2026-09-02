# (c) 2026 Holger Imbery (contact@holgerimbery.blog)
# Licensed under the project LICENSE file.
# Enforces HTTPS-only traffic and restricts inbound access to an
# allowlisted set of IP ranges (e.g. Power Platform / your office egress).

param(
    [string]$ResourceGroup,
    [string]$AppServiceName,
    [string[]]$AllowedIpRanges
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
    if (-not $ResourceGroup) { $ResourceGroup = $env_vars['RESOURCE_GROUP'] }
    if (-not $AppServiceName) { $AppServiceName = $env_vars['APP_SERVICE_NAME'] }
    if (-not $AllowedIpRanges) { $AllowedIpRanges = $env_vars['ALLOWED_IP_RANGES']?.Split(',') | ForEach-Object { $_.Trim() } }
}

# Validate
if (-not $ResourceGroup -or -not $AppServiceName -or -not $AllowedIpRanges) {
    Write-Error "Missing required parameters: ResourceGroup, AppServiceName, AllowedIpRanges"
    Write-Host "Provide via CLI parameters or .env file in the repo root" -ForegroundColor Yellow
    exit 1
}

az webapp update --resource-group $ResourceGroup --name $AppServiceName --https-only true

$Priority = 100
foreach ($Range in $AllowedIpRanges) {
    az webapp config access-restriction add `
        --resource-group $ResourceGroup `
        --name $AppServiceName `
        --rule-name "Allow-$Range" `
        --action Allow `
        --ip-address $Range `
        --priority $Priority
    $Priority += 10
}

Write-Host "HTTPS-only enforced and ingress restricted on $AppServiceName" -ForegroundColor Green
