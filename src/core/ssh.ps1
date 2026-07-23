#Requires -Version 5.1
<#
.SYNOPSIS
    WinVPS SSH Server Manager - controls Windows OpenSSH server.
.DESCRIPTION
    Start/stop/restart the built-in Windows OpenSSH SSH server on a custom port.
#>
param(
    [Parameter(Position=0)]
    [ValidateSet('start','stop','restart','status')]
    [string]$Action = 'start'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$WinVPSDir = $env:WINVPS_DIR; if (-not $WinVPSDir) { $WinVPSDir = 'C:\WinVPS' }
$ServicesDir = Join-Path $WinVPSDir 'services'
$LogDir = Join-Path $WinVPSDir 'logs'
$ConfigFile = Join-Path $WinVPSDir 'config\winvps.conf'
$PidFile = Join-Path $ServicesDir 'ssh.pid'
$LogFile = Join-Path $LogDir 'ssh.log'

if (-not (Test-Path $ServicesDir)) { New-Item -ItemType Directory -Path $ServicesDir -Force | Out-Null }
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

function Load-Config {
    $port = 7022
    if (Test-Path $ConfigFile) {
        $line = Get-Content $ConfigFile | Where-Object { $_ -match '^WINVPS_SSH_PORT=' }
        if ($line) { $port = [int]($line -split '=',2)[1].Trim('"') }
    }
    return $port
}

function Get-SshService { Get-Service -Name 'sshd' -ErrorAction SilentlyContinue }

function Start-Ssh {
    $port = Load-Config
    $svc = Get-SshService

    if ($svc -and $svc.Status -eq 'Running') {
        Write-Host "[ssh] OpenSSH already running (port $port)"
        return
    }

    if (-not $svc) {
        Write-Host "[ssh] OpenSSH not installed - installing..."
        try {
            Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0 -ErrorAction Stop
            $svc = Get-SshService
        } catch {
            Write-Host "[ssh] Failed to install OpenSSH: $_"
            return
        }
    }

    try {
        if ($svc.Status -ne 'Running') {
            Start-Service -Name 'sshd' -ErrorAction Stop
        }

        $sshdConfig = Join-Path $env:ProgramData 'ssh\sshd_config'
        if (Test-Path $sshdConfig) {
            $content = Get-Content $sshdConfig -Raw
            if ($content -match '^Port\s+\d+') {
                $content = $content -replace '^Port\s+\d+', "Port $port"
            } else {
                $content = "Port $port`n" + $content
            }
            $content | Out-File -FilePath $sshdConfig -Encoding ascii -Force
            Restart-Service -Name 'sshd' -Force -ErrorAction SilentlyContinue
        }

        $proc = Get-Process -Name 'sshd' -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($proc) {
            $proc.Id | Out-File -FilePath $PidFile -Encoding ascii -Force
            Write-Host "[ssh] OpenSSH started (PID $($proc.Id), port $port)"
        } else {
            Write-Host "[ssh] OpenSSH started (port $port)"
            "system" | Out-File -FilePath $PidFile -Encoding ascii -Force
        }
    } catch {
        Write-Host "[ssh] Failed to start OpenSSH: $_"
    }
}

function Stop-Ssh {
    if (Test-Path $PidFile) {
        $pid = Get-Content $PidFile -ErrorAction SilentlyContinue
        if ($pid -and $pid -ne 'system') {
            $proc = Get-Process -Id ([int]$pid) -ErrorAction SilentlyContinue
            if ($proc) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
        }
        Remove-Item $PidFile -Force
    }
    Stop-Service -Name 'sshd' -Force -ErrorAction SilentlyContinue
    Write-Host "[ssh] OpenSSH stopped"
}

function Show-SshStatus {
    $svc = Get-SshService
    $port = Load-Config
    if ($svc) {
        Write-Host "[ssh] OpenSSH: $($svc.Status) (port $port)"
    } else {
        Write-Host "[ssh] OpenSSH: not installed"
    }
}

switch ($Action) {
    'start'   { Start-Ssh }
    'stop'    { Stop-Ssh }
    'restart' { Stop-Ssh; Start-Sleep -Seconds 2; Start-Ssh }
    'status'  { Show-SshStatus }
}
