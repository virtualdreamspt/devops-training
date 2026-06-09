# ============================================================
# deploy.ps1  —  One-click deploy helper for the Bicep template
# Usage: .\deploy.ps1
# Requires: az CLI logged in, resource group pre-created
# ============================================================

param(
    [string]$ResourceGroup = "2605260050001177",
    [string]$AdminPassword       = "REPLACE_ME",
    [string]$SafeModePassword    = "REPLACE_ME",
    [string]$VpnSharedKey        = "REPLACE_ME",
    [string]$DomainAdminPassword = "REPLACE_ME",
    [string]$DomainUserPassword  = "REPLACE_ME"
)

$ErrorActionPreference = "Stop"
$templateFile = Join-Path $PSScriptRoot "main.bicep"

Write-Host "Deploying Kerberos Lab Bicep template to resource group: $ResourceGroup"
Write-Host "This will take ~45-60 minutes (VPN Gateways are the bottleneck).`n"

az deployment group create `
    --resource-group $ResourceGroup `
    --template-file $templateFile `
    --parameters adminPassword=$AdminPassword `
                 safeModePassword=$SafeModePassword `
                 vpnSharedKey=$VpnSharedKey `
                 domainAdminPassword=$DomainAdminPassword `
                 domainUserPassword=$DomainUserPassword `
    --verbose

if ($LASTEXITCODE -eq 0) {
    Write-Host "`nDeployment complete!" -ForegroundColor Green
    Write-Host "Next: connect via Bastion and run scripts in order:"
    Write-Host "  1. scripts\01-setup-primary-dc.ps1   (on DEMO-DC-NE)"
    Write-Host "  2. scripts\02-setup-secondary-dc.ps1 (on DEMO-DC-US)"
    Write-Host "  3. scripts\03-join-domain.ps1         (on DEMO-CLIENT-US)"
} else {
    Write-Host "`nDeployment failed. Check output above." -ForegroundColor Red
}
