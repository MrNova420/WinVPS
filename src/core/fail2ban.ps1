#Requires -Version 5.1
<#
.SYNOPSIS
    WinVPS Fail2ban - brute-force protection for SSH.
.DESCRIPTION
    Monitors SSH auth logs for repeated failed login attempts and bans
    offending IPs via Windows Firewall rules.
#>
param(
    [Parameter(Position=0)]
    [ValidateSet('start','stop','restart','status','loop')]
    [string]$Action = 'status'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

$WinVPSDir = $env:WINVPS_DIR; if (-not $WinVPSDir) { $WinVPSDir = 'C:\WinVPS' }
$ServicesDir = Join-Path $WinVPSDir 'services'
$LogDir = Join-Path $WinVPSDir 'logs'
$BanListFile = Join-Path $WinVPSDir 'config\.ban_list'
$PidFile = Join-Path $ServicesDir 'fail2ban.pid'
$LogFile = Join-Path $LogDir 'fail2ban.log'
$MaxAttempts = 5
$BanTime = 3600

if (-not (Test-Path $ServicesDir)) { New-Item -ItemType Directory -Path $ServicesDir -Force | Out-Null }
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

function Log($msg) {
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [fail2ban] $msg" | Out-File -FilePath $LogFile -Encoding ascii -Append
}

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Ban-IP {
    param([string]$IP)
    if (Test-Path $BanListFile) {
        $existing = Get-Content $BanListFile | Where-Object { $_ -match "^$IP " }
        if ($existing) { return }
    }
    "$IP $(Get-Date -Epoch) $BanTime" | Out-File -FilePath $BanListFile -Encoding ascii -Append
    if (Test-Admin) {
        New-NetFirewallRule -DisplayName "WinVPS-Fail2Ban-$IP" -Direction Inbound -Action Block `
            -RemoteAddress $IP -ErrorAction SilentlyContinue | Out-Null
    }
    Log "Banned $IP for ${BanTime}s"
}

function Unban-Expired {
    if (-not (Test-Path $BanListFile)) { return }
    $now = [int][double]::Parse((Get-Date -UFormat %s))
    $remaining = @()
    Get-Content $BanListFile | ForEach-Object {
        if ($_ -match '^(\S+)\s+(\d+)\s+(\d+)$') {
            $ip = $matches[1]
            $time = [int]$matches[2]
            $duration = [int]$matches[3]
            $elapsed = $now - $time
            if ($elapsed -ge $duration) {
                if (Test-Admin) {
                    Remove-NetFirewallRule -DisplayName "WinVPS-Fail2Ban-$ip" -ErrorAction SilentlyContinue
                }
                Log "Unbanned $ip (expired)"
            } else {
                $remaining += $_
            }
        }
    }
    $remaining | Out-File -FilePath $BanListFile -Encoding ascii -Force
}

function Check-Logs {
    $logFiles = @(
        (Join-Path $LogDir 'ssh.log'),
        (Join-Path $LogDir 'auth-failures.log')
    )
    foreach ($lf in $logFiles) {
        if (-not (Test-Path $lf)) { continue }
        $failures = Select-String -Path $lf -Pattern 'Failed password|auth failure|Bad protocol' -ErrorAction SilentlyContinue
        if ($failures) {
            $ipPattern = 'from\s+(\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})'
            $ips = @{}
            foreach ($line in $failures) {
                if ($line.Line -match $ipPattern) {
                    $ip = $matches[1]
                    if (-not $ips[$ip]) { $ips[$ip] = 0 }
                    $ips[$ip]++
                }
            }
            foreach ($ip in $ips.Keys) {
                if ($ips[$ip] -ge $MaxAttempts) {
                    Ban-IP -IP $ip
                }
            }
        }
    }
}

function Start-Fail2banLoop {
    while ($true) {
        Unban-Expired
        Check-Logs
        Start-Sleep -Seconds 60
    }
}

function Start-Fail2ban {
    if (Test-Path $PidFile) {
        $pid = Get-Content $PidFile -ErrorAction SilentlyContinue
        if ($pid -and (Get-Process -Id ([int]$pid) -ErrorAction SilentlyContinue)) {
            Write-Host "[fail2ban] Already running (PID $pid)"
            return
        }
    }
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = 'powershell.exe'
    $pinfo.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$PSCommandPath`" loop"
    $pinfo.UseShellExecute = $false
    $pinfo.CreateNoWindow = $true
    $proc = [System.Diagnostics.Process]::Start($pinfo)
    $proc.Id | Out-File -FilePath $PidFile -Encoding ascii -Force
    Start-Sleep -Seconds 2
    if (-not $proc.HasExited) {
        Write-Host "[fail2ban] Started (PID $($proc.Id))"
    } else {
        Write-Host "[fail2ban] Failed to start"
    }
}

function Stop-Fail2ban {
    if (Test-Path $PidFile) {
        $pid = Get-Content $PidFile -ErrorAction SilentlyContinue
        if ($pid) {
            Stop-Process -Id ([int]$pid) -Force -ErrorAction SilentlyContinue
        }
        Remove-Item $PidFile -Force
    }
    Write-Host "[fail2ban] Stopped"
}

function Show-Fail2banStatus {
    if (Test-Path $PidFile) {
        $pid = Get-Content $PidFile -ErrorAction SilentlyContinue
        if ($pid -and (Get-Process -Id ([int]$pid) -ErrorAction SilentlyContinue)) {
            Write-Host "[fail2ban] RUNNING (PID $pid)"
        } else {
            Write-Host "[fail2ban] STOPPED"
        }
    } else {
        Write-Host "[fail2ban] STOPPED"
    }
    $banned = 0
    if (Test-Path $BanListFile) {
        $banned = (Get-Content $BanListFile | Where-Object { $_.Trim() }).Count
    }
    Write-Host "  Banned IPs: $banned"
}

switch ($Action) {
    'start'   { Start-Fail2ban }
    'stop'    { Stop-Fail2ban }
    'restart' { Stop-Fail2ban; Start-Sleep -Seconds 2; Start-Fail2ban }
    'status'  { Show-Fail2banStatus }
    'loop'    { Start-Fail2banLoop }
    default   { Write-Host 'Usage: fail2ban.ps1 {start|stop|restart|status}' }
}
