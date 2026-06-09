# ============================================================
# 03-join-domain.ps1
# Run this on DEMO-CLIENT-US via Bastion AFTER the secondary DC
# is operational and Kerberos SRV records have been configured.
# Joins the client VM to the domain and reboots.
# ============================================================

param(
    [string]$DomainName     = "demo.local",
    [string]$NetBiosName    = "DEMO",
    [string]$DomainAdmin    = "demoadmin",
    [string]$DomainAdminPwd = "REPLACE_ME",
    [string]$PrimaryDNS     = "10.2.1.5",   # US DC (knows Kerberos SRV → NE)
    [string]$SecondaryDNS   = "10.1.1.4"    # NE DC as fallback
)

$ErrorActionPreference = "Stop"

# ── Step 1: Set DNS ──────────────────────────────────────────────────────────────
Write-Host "[1/4] Configuring DNS servers..."
$adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses $PrimaryDNS, $SecondaryDNS
Clear-DnsClientCache
Start-Sleep -Seconds 5

# ── Step 2: Verify domain reachability ──────────────────────────────────────────
Write-Host "[2/4] Verifying domain reachability..."
if (-not (Resolve-DnsName $DomainName -EA SilentlyContinue)) {
    throw "Cannot resolve $DomainName. Ensure DNS is configured and the VPN is up."
}

# ── Step 3: Join the domain ──────────────────────────────────────────────────────
Write-Host "[3/4] Joining domain $DomainName..."
$credential = New-Object PSCredential(
    "$NetBiosName\$DomainAdmin",
    (ConvertTo-SecureString $DomainAdminPwd -AsPlainText -Force)
)

Add-Computer -DomainName $DomainName -Credential $credential -Force

# ── Step 4: Reboot ──────────────────────────────────────────────────────────────
Write-Host "[4/4] Domain join complete. Rebooting..."
Restart-Computer -Force

# ── After reboot: Test Kerberos ──────────────────────────────────────────────────
# Log in as demo-user@demo.local via Bastion, then run:
#
#   klist
#   — Verify the KDC listed is 10.1.1.4 (DEMO-DC-NE / North Europe)
#
#   nltest /dsgetdc:demo.local /kdc
#   — Should return DEMO-DC-NE as the KDC
#
#   nslookup -type=srv _kerberos._tcp.demo.local
#   — SRV record should point only to DEMO-DC-NE.demo.local
