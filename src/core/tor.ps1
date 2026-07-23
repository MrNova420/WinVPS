#Requires -Version 5.1
<#
.SYNOPSIS
    WinVPS Tor Gateway - route traffic through Tor for anonymity.
.DESCRIPTION
    Manages the Tor Expert Bundle for anonymous routing on Windows.
#>
param(
    [Parameter(Position=0)]
    [ValidateSet('start','up','stop','down','restart','status','install')]
    [string]$Action = 'status'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

$WinVPSDir = $env:WINVPS_DIR; if (-not $WinVPSDir) { $WinVPSDir = 'C:\WinVPS' }
$ServicesDir = Join-Path $WinVPSDir 'services'
$LogDir = Join-Path $WinVPSDir 'logs'
$TunnelDir = Join-Path $WinVPSDir 'tunnels'
$ConfigDir = Join-Path $WinVPSDir 'config'
$PidFile = Join-Path $ServicesDir 'tor.pid'
$LogFile = Join-Path $LogDir 'tor.log'
$TorrcFile = Join-Path $ConfigDir 'torrc'
$TorDataDir = Join-Path $WinVPSDir 'data\tor'
$TorBinary = Join-Path $TunnelDir 'tor\tor.exe'

if (-not (Test-Path $ServicesDir)) { New-Item -ItemType Directory -Path $ServicesDir -Force | Out-Null }
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
if (-not (Test-Path $TorDataDir)) { New-Item -ItemType Directory -Path $TorDataDir -Force | Out-Null }

function Test-TorInstalled {
    return (Test-Path $TorBinary)
}

function Install-Tor {
    Write-Host '[tor] Downloading Tor Expert Bundle...'
    if (-not (Test-Path $TunnelDir)) { New-Item -ItemType Directory -Path $TunnelDir -Force | Out-Null }
    $torDir = Join-Path $TunnelDir 'tor'
    if (-not (Test-Path $torDir)) { New-Item -ItemType Directory -Path $torDir -Force | Out-Null }
    try {
        $url = 'https://www.torproject.org/dist/torbrowser/14.0.4/tor-expert-bundle-windows-x86_64-14.0.4-all.zip'
        $zipFile = Join-Path $env:TEMP 'tor-bundle.zip'
        Invoke-WebRequest -Uri $url -OutFile $zipFile -UseBasicParsing -TimeoutSec 60
        Expand-Archive -Path $zipFile -DestinationPath $torDir -Force
        Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
        Write-Host '[tor] Tor installed'
    } catch {
        Write-Host "[tor] Download failed: $_"
        Write-Host '[tor] Download manually from: https://www.torproject.org/download/tor/'
    }
}

function Start-Tor {
    if (Test-Path $PidFile) {
        $pid = Get-Content $PidFile -ErrorAction SilentlyContinue
        if ($pid -and (Get-Process -Id ([int]$pid) -ErrorAction SilentlyContinue)) {
            Write-Host "[tor] Already running (PID $pid)"
            return
        }
    }

    if (-not (Test-TorInstalled)) {
        Write-Host '[tor] Not installed - run: winvps tor install'
        return
    }

    if (-not (Test-Path $TorrcFile)) {
        @"
SocksPort 9050
ControlPort 9051
CookieAuthentication 1
DataDirectory $TorDataDir
Log notice file $LogFile
RunAsDaemon 0
"@ | Out-File -FilePath $TorrcFile -Encoding ascii -Force
    }

    Write-Host '[tor] Starting Tor...'
    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = $TorBinary
    $pinfo.Arguments = "-f `"$TorrcFile`""
    $pinfo.UseShellExecute = $false
    $pinfo.CreateNoWindow = $true
    $proc = [System.Diagnostics.Process]::Start($pinfo)
    $proc.Id | Out-File -FilePath $PidFile -Encoding ascii -Force
    Start-Sleep -Seconds 5
    if (-not $proc.HasExited) {
        Write-Host "[tor] Tor started (PID $($proc.Id), SOCKS5 127.0.0.1:9050)"
    } else {
        Write-Host '[tor] Tor failed to start'
        Remove-Item $PidFile -Force -ErrorAction SilentlyContinue
    }
}

function Stop-Tor {
    if (Test-Path $PidFile) {
        $pid = Get-Content $PidFile -ErrorAction SilentlyContinue
        if ($pid -and $pid -ne 'system') {
            Stop-Process -Id ([int]$pid) -Force -ErrorAction SilentlyContinue
        }
        Remove-Item $PidFile -Force
    }
    Write-Host '[tor] Tor stopped'
}

function Show-TorStatus {
    if (Test-Path $PidFile) {
        $pid = Get-Content $PidFile -ErrorAction SilentlyContinue
        if ($pid -and (Get-Process -Id ([int]$pid) -ErrorAction SilentlyContinue)) {
            Write-Host "[tor] Tor: running (PID $pid, SOCKS5 127.0.0.1:9050)"
            return
        }
    }
    Write-Host '[tor] Tor: stopped'
}

switch ($Action) {
    'start'   { Start-Tor }
    'up'      { Start-Tor }
    'stop'    { Stop-Tor }
    'down'    { Stop-Tor }
    'restart' { Stop-Tor; Start-Sleep -Seconds 2; Start-Tor }
    'status'  { Show-TorStatus }
    'install' { Install-Tor }
    default   { Write-Host 'Usage: tor.ps1 {start|stop|restart|status|install}' }
}
