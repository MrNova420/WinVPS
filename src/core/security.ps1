#Requires -Version 5.1
<#
.SYNOPSIS
    WinVPS Security Module - hardening, scanning, and Windows Firewall management.
.DESCRIPTION
    Scans for security issues, applies hardening rules (SSH config, firewall, permissions),
    and provides security status reporting.
#>
param(
    [Parameter(Position=0)]
    [ValidateSet('status','scan','harden')]
    [string]$Action = 'status'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

$WinVPSDir = $env:WINVPS_DIR; if (-not $WinVPSDir) { $WinVPSDir = 'C:\WinVPS' }
$LogDir = Join-Path $WinVPSDir 'logs'
$ConfigFile = Join-Path $WinVPSDir 'config\winvps.conf'

$Green = "`e[0;32m"; $Yellow = "`e[1;33m"; $Red = "`e[0;31m"; $NC = "`e[0m"
function Log($msg)  { Write-Host "${Green}[security]${NC} $msg" }
function Warn($msg) { Write-Host "${Yellow}[security]${NC} $msg" }
function Err($msg)  { Write-Host "${Red}[security]${NC} $msg" }

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-SshPort {
    $port = 7022
    if (Test-Path $ConfigFile) {
        $line = Get-Content $ConfigFile | Where-Object { $_ -match '^WINVPS_SSH_PORT=' }
        if ($line) { $port = [int]($line -split '=',2)[1].Trim('"') }
    }
    return $port
}

function Show-SecurityStatus {
    Write-Host ''
    Write-Host '  Security Status'
    Write-Host '  ----------------------------------------'
    Write-Host ''
    Write-Host "  Admin:        $(if (Test-Admin) { 'YES' } else { 'NO' })"
    Write-Host "  SSH Port:     $(Get-SshPort)"

    $fwProfiles = Get-NetFirewallProfile -ErrorAction SilentlyContinue
    if ($fwProfiles) {
        $enabled = ($fwProfiles | Where-Object { $_.Enabled -eq $true }).Count
        Write-Host "  Firewall:     $enabled/$($fwProfiles.Count) profiles active"
    } else {
        Write-Host '  Firewall:     unavailable'
    }

    $hardenFile = Join-Path $WinVPSDir 'config\.harden_done'
    Write-Host "  Lockdown:     $(if (Test-Path $hardenFile) { 'active' } else { 'inactive' })"
    $stealthFile = Join-Path $WinVPSDir 'config\.stealth_enabled'
    Write-Host "  Stealth:      $(if (Test-Path $stealthFile) { 'ACTIVE' } else { 'inactive' })"
    $obfFile = Join-Path $WinVPSDir 'config\.obfuscated'
    Write-Host "  Obfuscation:  $(if (Test-Path $obfFile) { 'ACTIVE' } else { 'inactive' })"
    Write-Host ''
}

function Invoke-SecurityScan {
    Log 'Running security scan...'
    $reportFile = Join-Path $LogDir 'security_scan.log'
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

    $issues = 0
    $report = @()
    $report += "=== Security Scan: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="

    $sshdConfig = Join-Path $env:ProgramData 'ssh\sshd_config'
    if (Test-Path $sshdConfig) {
        $content = Get-Content $sshdConfig -ErrorAction SilentlyContinue
        if ($content -match 'PermitRootLogin\s+yes') {
            $report += 'WARN: Root login enabled via SSH'
            $issues++
        }
        if ($content -notmatch 'PasswordAuthentication\s+no') {
            $report += 'WARN: Password authentication enabled'
            $issues++
        }
        if ($content -match '^Port\s+22\b') {
            $report += 'INFO: SSH on default port 22 - consider changing'
        }
    }

    $riskyPorts = @(23, 21, 110, 143, 445, 554, 3306, 3389, 5900)
    $listening = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue |
        Select-Object -ExpandProperty LocalPort -Unique
    foreach ($port in $riskyPorts) {
        if ($listening -contains $port) {
            $report += "WARN: Risky port open: $port"
            $issues++
        }
    }

    $sshDir = Join-Path $WinVPSDir 'config'
    if (Test-Path $sshDir) {
        $acl = Get-Acl $sshDir
        $access = $acl.Access | Where-Object { $_.IdentityReference -notmatch 'SYSTEM|Administrators' -and $_.FileSystemRights -match 'FullControl|Write' }
        if ($access) {
            $report += "WARN: Overly permissive ACL on $sshDir"
            $issues++
        }
    }

    $sshLog = Join-Path $LogDir 'ssh.log'
    if (Test-Path $sshLog) {
        $failed = (Select-String -Path $sshLog -Pattern 'Failed password|auth failure' -ErrorAction SilentlyContinue).Count
        if ($failed -gt 10) {
            $report += "WARN: $failed failed SSH login attempts"
            $issues++
        }
    }

    $report += '---'
    $report += "Issues found: $issues"
    $report += "Scan completed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    $report | Out-File -FilePath $reportFile -Encoding ascii -Force

    foreach ($line in $report) { Write-Host "  $line" }

    if ($issues -gt 0) {
        Warn "$issues security issue(s) found - review $reportFile"
    } else {
        Log 'No security issues found'
    }
}

function Invoke-SecurityHarden {
    Log 'Applying security hardening...'
    $changes = 0

    $sshdConfig = Join-Path $env:ProgramData 'ssh\sshd_config'
    if (Test-Path $sshdConfig) {
        $content = Get-Content $sshdConfig -Raw
        $original = $content
        $content = $content -replace '(?m)^PermitRootLogin\s+yes', 'PermitRootLogin prohibit-password'
        $content = $content -replace '(?m)^#PermitRootLogin\s+yes', 'PermitRootLogin prohibit-password'
        $content = $content -replace '(?m)^PasswordAuthentication\s+yes', 'PasswordAuthentication no'
        if ($content -notmatch 'MaxAuthTries') { $content += "`nMaxAuthTries 3" }
        if ($content -notmatch 'ClientAliveInterval') {
            $content += "`nClientAliveInterval 300`nClientAliveCountMax 2"
        }
        if ($content -ne $original) {
            $content | Out-File -FilePath $sshdConfig -Encoding ascii -Force
            $changes++
            Log 'SSH hardened'
        }
    }

    if (Test-Admin) {
        $createFw = Read-Host '  Create firewall rules for WinVPS ports? (y/N)'
        if ($createFw -eq 'y' -or $createFw -eq 'Y') {
            $sshPort = Get-SshPort
            $webPort = 7080
            $httpsPort = 7443
            $filePort = 7444

            $existing = Get-NetFirewallRule -DisplayName 'WinVPS*' -ErrorAction SilentlyContinue
            if ($existing) { $existing | Remove-NetFirewallRule -ErrorAction SilentlyContinue }

            $rules = @(
                @{ Name="WinVPS-SSH-$sshPort"; LocalPort=$sshPort; Protocol='TCP' },
                @{ Name="WinVPS-Web-$webPort"; LocalPort=$webPort; Protocol='TCP' },
                @{ Name="WinVPS-HTTPS-$httpsPort"; LocalPort=$httpsPort; Protocol='TCP' },
            @{ Name="WinVPS-File-$filePort"; LocalPort=$filePort; Protocol='TCP' }
        )
        foreach ($rule in $rules) {
            New-NetFirewallRule -DisplayName $rule.Name -Direction Inbound -Action Allow `
                -Protocol $rule.Protocol -LocalPort $rule.LocalPort -ErrorAction SilentlyContinue | Out-Null
        }
        $changes++
        Log 'Firewall rules applied'
        } else {
            Log 'Skipping firewall rules'
        }
    } else {
        Warn 'No admin - skipping firewall rules'
    }

    $dirs = @(
        (Join-Path $WinVPSDir 'config'),
        (Join-Path $WinVPSDir 'config\ssh')
    )
    foreach ($dir in $dirs) {
        if (Test-Path $dir) {
            icacls.exe $dir /grant "${env:USERNAME}:(OI)(CI)F" /inheritance:r /grant 'SYSTEM:(OI)(CI)F' /grant 'Administrators:(OI)(CI)F' 2>&1 | Out-Null
            $changes++
        }
    }
    Log "Permissions tightened"
    $changes++
    Log "Hardening complete ($changes changes applied)"
    (Get-Date -Format 'yyyy-MM-dd HH:mm:ss') | Out-File (Join-Path $WinVPSDir 'config\.harden_done') -Encoding ascii -Force
}

switch ($Action) {
    'status' { Show-SecurityStatus }
    'scan'   { Invoke-SecurityScan }
    'harden' { Invoke-SecurityHarden }
    default  { Write-Host 'Usage: security.ps1 {status|scan|harden}' }
}
