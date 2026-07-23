#Requires -Version 5.1
<#
.SYNOPSIS
    WinVPS Service Supervisor - manages, monitors, and auto-heals services.
.DESCRIPTION
    Starts/stops services, runs a watchdog loop that restarts crashed services,
    and maintains PID tracking for all managed services.
#>
param(
    [Parameter(Position=0)]
    [ValidateSet('start','stop','restart','status','watchdog')]
    [string]$Action = 'status',

    [switch]$Watchdog
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$WinVPSDir = $env:WINVPS_DIR; if (-not $WinVPSDir) { $WinVPSDir = 'C:\WinVPS' }
$SrcDir    = Join-Path $WinVPSDir 'src\core'
$ServicesDir = Join-Path $WinVPSDir 'services'
$LogDir    = Join-Path $WinVPSDir 'logs'
$ConfigFile = Join-Path $WinVPSDir 'config\winvps.conf'

$Green = "`e[0;32m"; $Yellow = "`e[1;33m"; $Red = "`e[0;31m"; $NC = "`e[0m"
function Log($msg)  { Write-Host "${Green}[supervisor]${NC} $msg" }
function Warn($msg) { Write-Host "${Yellow}[supervisor]${NC} $msg" }
function Err($msg)  { Write-Host "${Red}[supervisor]${NC} $msg" }

function Ensure-Dirs {
    foreach ($d in @($ServicesDir, $LogDir, (Join-Path $WinVPSDir 'tmp'))) {
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }
}

function Load-Config {
    if (Test-Path $ConfigFile) {
        Get-Content $ConfigFile | Where-Object { $_ -match '^\w+=' } | ForEach-Object {
            $key, $val = $_ -split '=', 2
            $val = $val.Trim('"').Trim("'")
            Set-Item -Path "env:WINVPS_$($key.ToUpper().Replace('WINVPS_',''))" -Value $val -ErrorAction SilentlyContinue
        }
    }
}

function Get-ServiceDefinitions {
    $services = @()

    $services += [PSCustomObject]@{
        Name    = 'ssh'
        Command = 'ssh'
        Script  = Join-Path $SrcDir 'ssh.ps1'
        Args    = @('start')
    }

    $services += [PSCustomObject]@{
        Name    = 'web'
        Command = 'web'
        Script  = Join-Path $SrcDir 'httpd.ps1'
        Args    = @('start')
    }

    $services += [PSCustomObject]@{
        Name    = 'fail2ban'
        Command = 'fail2ban'
        Script  = Join-Path $SrcDir 'fail2ban.ps1'
        Args    = @('start')
    }

    $customFile = Join-Path $WinVPSDir 'config\services.conf'
    if (Test-Path $customFile) {
        Get-Content $customFile | Where-Object { $_ -match '^\w' } | ForEach-Object {
            $parts = $_ -split '=', 2
            if ($parts.Count -eq 2) {
                $services += [PSCustomObject]@{
                    Name    = $parts[0].Trim()
                    Command = $parts[0].Trim()
                    Script  = $parts[1].Trim()
                    Args    = @()
                }
            }
        }
    }

    return $services
}

function Get-PidFile($name) { Join-Path $ServicesDir "$name.pid" }

function Test-ServiceRunning($name) {
    $pidFile = Get-PidFile $name
    if (-not (Test-Path $pidFile)) { return $false }
    $pid = [int](Get-Content $pidFile -ErrorAction SilentlyContinue)
    if ($pid -le 0) { return $false }
    $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
    return ($null -ne $proc)
}

function Start-SingleService {
    param(
        [string]$Name,
        [string]$ScriptPath,
        [string[]]$ScriptArgs
    )
    $pidFile = Get-PidFile $Name
    $logFile = Join-Path $LogDir "$Name.log"

    if (Test-ServiceRunning $Name) {
        $pid = [int](Get-Content $pidFile)
        Log "$Name already running (PID $pid)"
        return $true
    }

    if (Test-Path $pidFile) { Remove-Item $pidFile -Force -ErrorAction SilentlyContinue }

    if ($ScriptPath -and (Test-Path $ScriptPath)) {
        try {
            $pinfo = New-Object System.Diagnostics.ProcessStartInfo
            $pinfo.FileName = 'powershell.exe'
            $pinfo.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$ScriptPath`" $($ScriptArgs -join ' ')"
            $pinfo.UseShellExecute = $false
            $pinfo.CreateNoWindow = $true
            $pinfo.RedirectStandardOutput = $true
            $pinfo.RedirectStandardError = $true
            $proc = [System.Diagnostics.Process]::Start($pinfo)
            $proc.Id | Out-File -FilePath $pidFile -Encoding ascii -Force
            Start-Sleep -Seconds 2
            if (-not $proc.HasExited) {
                Log "$Name started (PID $($proc.Id))"
                return $true
            } else {
                Warn "$Name exited immediately"
                Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
                return $false
            }
        } catch {
            Warn "$Name failed to start: $_"
            return $false
        }
    } else {
        Warn "No script for $Name at $ScriptPath"
        return $false
    }
}

function Stop-SingleService {
    param([string]$Name)
    $pidFile = Get-PidFile $Name
    if (-not (Test-Path $pidFile)) { Warn "$Name not running"; return }

    $pid = [int](Get-Content $pidFile -ErrorAction SilentlyContinue)
    if ($pid -gt 0) {
        $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
        if ($proc) {
            try {
                $proc.Kill()
                Start-Sleep -Milliseconds 500
                Log "$Name stopped (PID $pid)"
            } catch {
                Warn "Could not stop $Name : $_"
            }
        }
    }
    Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
}

function Start-AllServices {
    Log "Starting all services..."
    $services = Get-ServiceDefinitions
    $running = 0
    foreach ($svc in $services) {
        if (Start-SingleService -Name $svc.Name -ScriptPath $svc.Script -ScriptArgs $svc.Args) {
            $running++
        }
    }
    Log "Supervisor active - $running/$($services.Count) services running"
}

function Stop-AllServices {
    Log "Stopping all services..."
    Get-ChildItem -Path $ServicesDir -Filter '*.pid' -ErrorAction SilentlyContinue | ForEach-Object {
        $name = $_.BaseName
        Stop-SingleService -Name $name
    }
    Log "All services stopped"
}

function Show-Status {
    $services = Get-ServiceDefinitions
    $running = 0
    foreach ($svc in $services) {
        if (Test-ServiceRunning $svc.Name) {
            $pid = [int](Get-Content (Get-PidFile $svc.Name))
            $mem = (Get-Process -Id $pid -ErrorAction SilentlyContinue).WorkingSet64 / 1MB
            Log "$svc.Name is running (PID $pid, $([math]::Round($mem,1))MB)"
            $running++
        } else {
            Warn "$svc.Name is stopped"
        }
    }
    Write-Host "  Services: $running/$($services.Count) running"
}

function Invoke-Watchdog {
    Log "Watchdog started - monitoring every 30s"
    while ($true) {
        $services = Get-ServiceDefinitions
        foreach ($svc in $services) {
            if (-not (Test-ServiceRunning $svc.Name)) {
                Warn "$svc.Name crashed - restarting"
                $pidFile = Get-PidFile $svc.Name
                if (Test-Path $pidFile) { Remove-Item $pidFile -Force }
                Start-SingleService -Name $svc.Name -ScriptPath $svc.Script -ScriptArgs $svc.Args | Out-Null
            }
        }
        Start-Sleep -Seconds 30
    }
}

Ensure-Dirs
Load-Config

switch ($Action) {
    'start'    { Start-AllServices; if ($Watchdog) { Invoke-Watchdog } }
    'stop'     { Stop-AllServices }
    'restart'  { Stop-AllServices; Start-Sleep -Seconds 2; Start-AllServices }
    'status'   { Show-Status }
    'watchdog' { Start-AllServices; Invoke-Watchdog }
    default    { Write-Host "Usage: supervisor.ps1 {start|stop|restart|status|watchdog} [-Watchdog]" }
}
