# ============================================================
# 01-setup-primary-dc.ps1
# Run this on DEMO-DC-NE via Bastion if the Terraform extension fails.
# Installs AD DS, promotes to Primary DC, schedules post-reboot user creation.
# ============================================================

param(
    [string]$DomainName           = "demo.local",
    [string]$NetBiosName          = "DEMO",
    [string]$SafeModePassword     = "REPLACE_ME",
    [string]$DomainAdminPassword  = "REPLACE_ME",
    [string]$DomainUserPassword   = "REPLACE_ME"
)

$ErrorActionPreference = "Stop"

# ── Step 1: Install AD DS feature ───────────────────────────────────────────────
Write-Host "[1/4] Installing AD-Domain-Services feature..."
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools

# ── Step 2: Register post-reboot scheduled task ──────────────────────────────────
# This task runs after DC promotion reboots the VM, once AD is online.
Write-Host "[2/4] Registering post-reboot configuration task..."

$postScript = @"
Import-Module ActiveDirectory
Write-EventLog -LogName Application -Source 'DEMO-Setup' -EventId 1000 -Message 'Post-DC config started' -EntryType Information -EA SilentlyContinue

# Wait for AD DS to be fully operational
`$retry = 0
do {
    Start-Sleep 15
    `$retry++
    try { Get-ADDomain -EA Stop | Out-Null; break } catch {}
} while (`$retry -lt 20)

# Create domain admin user
try {
    New-ADUser ``
        -Name            'demo-admin' ``
        -SamAccountName  'demo-admin' ``
        -UserPrincipalName 'demo-admin@$DomainName' ``
        -AccountPassword (ConvertTo-SecureString '$DomainAdminPassword' -AsPlainText -Force) ``
        -Enabled         `$true ``
        -PasswordNeverExpires `$true ``
        -Description     'Demo Admin - Domain Admins member'
    Add-ADGroupMember -Identity 'Domain Admins' -Members 'demo-admin'
    Write-Host 'demo-admin created and added to Domain Admins'
} catch { Write-Warning "demo-admin: `$_" }

# Create regular Kerberos test user
try {
    New-ADUser ``
        -Name            'demo-user' ``
        -SamAccountName  'demo-user' ``
        -UserPrincipalName 'demo-user@$DomainName' ``
        -AccountPassword (ConvertTo-SecureString '$DomainUserPassword' -AsPlainText -Force) ``
        -Enabled         `$true ``
        -PasswordNeverExpires `$true ``
        -Description     'Demo User - standard Kerberos test account'
    Write-Host 'demo-user created'
} catch { Write-Warning "demo-user: `$_" }

# Clean up this scheduled task
Unregister-ScheduledTask -TaskName 'DEMO-PostDCConfig' -Confirm:`$false -EA SilentlyContinue
"@

$scriptPath = "C:\Windows\Temp\post-dc-config.ps1"
$postScript | Out-File -FilePath $scriptPath -Encoding UTF8

$action    = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-ExecutionPolicy Bypass -NonInteractive -File `"$scriptPath`""
$trigger   = New-ScheduledTaskTrigger -AtStartup
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Hours 1) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 2)

Register-ScheduledTask -TaskName "DEMO-PostDCConfig" -Action $action -Trigger $trigger `
    -Principal $principal -Settings $settings -Force | Out-Null

# ── Step 3: Promote to Primary DC ───────────────────────────────────────────────
Write-Host "[3/4] Promoting to Primary Domain Controller — VM will reboot automatically..."

Import-Module ADDSDeployment

Install-ADDSForest `
    -DomainName                    $DomainName `
    -DomainNetbiosName             $NetBiosName `
    -ForestMode                    "WinThreshold" `
    -DomainMode                    "WinThreshold" `
    -SafeModeAdministratorPassword (ConvertTo-SecureString $SafeModePassword -AsPlainText -Force) `
    -InstallDns:$true `
    -NoRebootOnCompletion:$false `
    -Force:$true

# VM reboots here — post-reboot task handles user creation
Write-Host "[4/4] Reboot triggered. Post-reboot task will create domain users."
