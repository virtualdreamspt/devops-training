# ============================================================
# 02-setup-secondary-dc.ps1
# Run this on DEMO-DC-US via Bastion AFTER the primary DC (DEMO-DC-NE)
# is fully operational and the S2S VPN is connected.
# Joins the domain, promotes to Secondary DC, and configures Kerberos
# DNS SRV records to redirect to the Primary DC (NE) only.
# ============================================================

param(
    [string]$DomainName        = "demo.local",
    [string]$NetBiosName       = "DEMO",
    [string]$SafeModePassword  = "REPLACE_ME",
    [string]$DomainAdmin       = "demoadmin",  # local admin on this VM
    [string]$DomainAdminPwd    = "REPLACE_ME",
    [string]$PrimaryDCIP       = "10.1.1.4",
    [string]$SecondaryDCIP     = "10.2.1.5"
)

$ErrorActionPreference = "Stop"

# ── Step 1: Point DNS at the Primary DC ─────────────────────────────────────────
Write-Host "[1/5] Configuring DNS to point at Primary DC ($PrimaryDCIP)..."

$adapter = Get-NetAdapter | Where-Object { $_.Status -eq "Up" } | Select-Object -First 1
Set-DnsClientServerAddress -InterfaceIndex $adapter.InterfaceIndex -ServerAddresses $PrimaryDCIP, "10.2.1.4"

# Flush DNS cache
Clear-DnsClientCache
Start-Sleep -Seconds 10

# ── Step 2: Verify connectivity to Primary DC ───────────────────────────────────
Write-Host "[2/5] Testing connectivity to Primary DC..."
if (-not (Test-Connection -ComputerName $PrimaryDCIP -Count 2 -Quiet)) {
    throw "Cannot reach Primary DC at $PrimaryDCIP. Ensure the S2S VPN is connected before running this script."
}

# ── Step 3: Install AD DS feature ───────────────────────────────────────────────
Write-Host "[3/5] Installing AD-Domain-Services feature..."
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools

# ── Step 4: Register post-reboot task to fix Kerberos SRV records ───────────────
# After promotion, remove this DC's KDC SRV entry so clients always
# resolve Kerberos to the North Europe DC (DEMO-DC-NE).
Write-Host "[4/5] Registering post-reboot Kerberos DNS fixup task..."

$kerbFixScript = @"
Import-Module DnsServer
Start-Sleep -Seconds 60  # Wait for DNS service to be fully up

`$zone = '$DomainName'
`$primaryDCFQDN = 'DEMO-DC-NE.$DomainName.'

Write-Host 'Fixing Kerberos SRV records to point only at DEMO-DC-NE...'

# Nodes where Kerberos SRV records are registered in AD DNS
`$kerbNodes = @('_kerberos._tcp', '_kerberos._udp', '_kdc._tcp', '_kpasswd._tcp', '_kpasswd._udp')

foreach (`$node in `$kerbNodes) {
    try {
        `$records = Get-DnsServerResourceRecord -ZoneName `$zone -Name `$node -RRType Srv -EA SilentlyContinue
        if (`$records) {
            # Remove any SRV record NOT pointing at the primary DC
            `$toRemove = `$records | Where-Object { `$_.RecordData.DomainName -ne `$primaryDCFQDN }
            foreach (`$r in `$toRemove) {
                Remove-DnsServerResourceRecord -ZoneName `$zone -InputObject `$r -Force -EA SilentlyContinue
                Write-Host "Removed `$node SRV: `$(`$r.RecordData.DomainName)"
            }
        }
    } catch {
        Write-Warning "Could not process `$node: `$_"
    }
}

# Also fix the site-specific records under _msdcs
try {
    `$msdcsRecords = Get-DnsServerResourceRecord -ZoneName "_msdcs.`$zone" -RRType Srv -EA SilentlyContinue | ``
        Where-Object { `$_.HostName -like '*kerberos*' -or `$_.HostName -like '*kdc*' }
    `$msdcsRecords | Where-Object { `$_.RecordData.DomainName -ne `$primaryDCFQDN } | ``
        ForEach-Object { Remove-DnsServerResourceRecord -ZoneName "_msdcs.`$zone" -InputObject `$_ -Force -EA SilentlyContinue }
} catch {}

Write-Host 'Kerberos SRV records updated. Clients in EastUS will authenticate against DEMO-DC-NE.'

# Unregister this task
Unregister-ScheduledTask -TaskName 'DEMO-KerberosDNSFix' -Confirm:`$false -EA SilentlyContinue
"@

$fixScriptPath = "C:\Windows\Temp\fix-kerberos-dns.ps1"
$kerbFixScript | Out-File -FilePath $fixScriptPath -Encoding UTF8

$action    = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -NonInteractive -File `"$fixScriptPath`""
$trigger   = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 1)

Register-ScheduledTask -TaskName "DEMO-KerberosDNSFix" -Action $action -Trigger $trigger `
    -Principal $principal -Settings $settings -Force | Out-Null

# ── Step 5: Promote to Secondary DC ─────────────────────────────────────────────
Write-Host "[5/5] Joining domain and promoting to Secondary Domain Controller..."

$domainCredential = New-Object PSCredential(
    "$NetBiosName\$DomainAdmin",
    (ConvertTo-SecureString $DomainAdminPwd -AsPlainText -Force)
)

Import-Module ADDSDeployment

Install-ADDSDomainController `
    -DomainName                    $DomainName `
    -Credential                    $domainCredential `
    -SafeModeAdministratorPassword (ConvertTo-SecureString $SafeModePassword -AsPlainText -Force) `
    -InstallDns:$true `
    -NoRebootOnCompletion:$false `
    -Force:$true

# VM reboots — post-reboot task will fix Kerberos SRV records
Write-Host "Reboot triggered. Post-reboot task will fix Kerberos SRV records."
