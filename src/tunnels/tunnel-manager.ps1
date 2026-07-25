#Requires -Version 5.1
<#
.SYNOPSIS
    WinVPS Tunnel Manager - Cloudflare, ngrok, bore tunnel management.
.DESCRIPTION
    Downloads and manages tunnel binaries for public access to the WinVPS.
#>
param(
    [Parameter(Position=0)]
    [ValidateSet('start','stop','restart','status')]
    [string]$Action = 'status',

    [string]$TunnelType = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

$WinVPSDir = $env:WINVPS_DIR; if (-not $WinVPSDir) { $WinVPSDir = 'C:\WinVPS' }
$TunnelDir = Join-Path $WinVPSDir 'tunnels'
$ServicesDir = Join-Path $WinVPSDir 'services'
$LogDir = Join-Path $WinVPSDir 'logs'
$ConfigFile = Join-Path $WinVPSDir 'config\winvps.conf'

if (-not (Test-Path $TunnelDir)) { New-Item -ItemType Directory -Path $TunnelDir -Force | Out-Null }
if (-not (Test-Path $ServicesDir)) { New-Item -ItemType Directory -Path $ServicesDir -Force | Out-Null }
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

function Load-Config {
    $config = @{ Type = 'cloudflare'; Port = 7080; Token = ''; NgrokToken = '' }
    if (Test-Path $ConfigFile) {
        $lines = Get-Content $ConfigFile
        $type = $lines | Where-Object { $_ -match '^WINVPS_TUNNEL_TYPE=' }
        $port = $lines | Where-Object { $_ -match '^WINVPS_WEB_PORT=' }
        $token = $lines | Where-Object { $_ -match '^WINVPS_TUNNEL_TOKEN=' }
        $ngrok = $lines | Where-Object { $_ -match '^WINVPS_NGROK_TOKEN=' }
        if ($type)  { $config.Type = ($type -split '=',2)[1].Trim('"') }
        if ($port)  { $config.Port = [int](($port -split '=',2)[1].Trim('"')) }
        if ($token) { $config.Token = ($token -split '=',2)[1].Trim('"') }
        if ($ngrok) { $config.NgrokToken = ($ngrok -split '=',2)[1].Trim('"') }
    }
    return $config
}

function Get-PidFile($name) { Join-Path $ServicesDir "$name.pid" }

function Test-TunnelRunning($name) {
    $pf = Get-PidFile $name
    if (-not (Test-Path $pf)) { return $false }
    $pid = [int](Get-Content $pf -ErrorAction SilentlyContinue)
    if ($pid -le 0) { return $false }
    return ($null -ne (Get-Process -Id $pid -ErrorAction SilentlyContinue))
}

function Start-Cloudflare {
    $bin = Join-Path $TunnelDir 'cloudflared.exe'
    $config = Load-Config

    if (-not (Test-Path $bin)) {
        Write-Host '[tunnel] Downloading cloudflared...'
        try {
            $url = 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe'
            Invoke-WebRequest -Uri $url -OutFile $bin -UseBasicParsing -TimeoutSec 60
        } catch {
            Write-Host "[tunnel] Download failed: $_"; return
        }
    }

    if (Test-TunnelRunning 'cloudflared') {
        Write-Host "[tunnel] Cloudflare already running"; return
    }

    if (-not $config.Token) {
        Write-Host '[tunnel] WINVPS_TUNNEL_TOKEN not set in config'
        Write-Host '[tunnel] Get a token: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/'
        return
    }

    $logFile = Join-Path $LogDir 'cloudflared.log'
    Start-Process -FilePath $bin -ArgumentList "tunnel --no-autoupdate run --token $($config.Token)" `
        -RedirectStandardOutput $logFile -NoNewWindow -PassThru |
        ForEach-Object { $_.Id | Out-File -FilePath (Get-PidFile 'cloudflared') -Encoding ascii -Force }
    Start-Sleep -Seconds 3
    if (Test-TunnelRunning 'cloudflared') {
        Write-Host '[tunnel] Cloudflare tunnel started'
    } else {
        Write-Host '[tunnel] Cloudflare failed - check token and logs'
    }
}

function Start-Ngrok {
    $bin = Join-Path $TunnelDir 'ngrok.exe'
    $config = Load-Config

    if (-not (Test-Path $bin)) {
        Write-Host '[tunnel] Downloading ngrok...'
        try {
            $url = 'https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-windows-amd64.zip'
            $zipFile = Join-Path $env:TEMP 'ngrok.zip'
            Invoke-WebRequest -Uri $url -OutFile $zipFile -UseBasicParsing -TimeoutSec 60
            Expand-Archive -Path $zipFile -DestinationPath $TunnelDir -Force
            Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
        } catch {
            Write-Host "[tunnel] Download failed: $_"; return
        }
    }

    if (Test-TunnelRunning 'ngrok') {
        Write-Host '[tunnel] ngrok already running'; return
    }

    if ($config.NgrokToken) {
        & $bin authtoken $config.NgrokToken 2>&1 | Out-Null
    }

    $logFile = Join-Path $LogDir 'ngrok.log'
    Start-Process -FilePath $bin -ArgumentList "http $($config.Port) --log=stdout" `
        -RedirectStandardOutput $logFile -NoNewWindow -PassThru |
        ForEach-Object { $_.Id | Out-File -FilePath (Get-PidFile 'ngrok') -Encoding ascii -Force }
    Start-Sleep -Seconds 3
    if (Test-TunnelRunning 'ngrok') {
        Write-Host "[tunnel] ngrok tunnel started (port $($config.Port))"
    } else {
        Write-Host '[tunnel] ngrok failed to start'
    }
}

function Start-Bore {
    $bin = Join-Path $TunnelDir 'bore.exe'
    $config = Load-Config

    if (-not (Test-Path $bin)) {
        Write-Host '[tunnel] Downloading bore...'
        try {
            $ver = (Invoke-RestMethod 'https://api.github.com/repos/ekzhang/bore/releases/latest' -ErrorAction SilentlyContinue).tag_name
            if (-not $ver) { $ver = 'v0.5.2' }
            $url = "https://github.com/ekzhang/bore/releases/download/$ver/bore-x86_64-pc-windows-msvc.exe"
            Invoke-WebRequest -Uri $url -OutFile $bin -UseBasicParsing -TimeoutSec 60
        } catch {
            Write-Host "[tunnel] Download failed: $_"; return
        }
    }

    if (Test-TunnelRunning 'bore') {
        Write-Host '[tunnel] bore already running'; return
    }

    $logFile = Join-Path $LogDir 'bore.log'
    Start-Process -FilePath $bin -ArgumentList "local $($config.Port) --to bore.pub" `
        -RedirectStandardOutput $logFile -NoNewWindow -PassThru |
        ForEach-Object { $_.Id | Out-File -FilePath (Get-PidFile 'bore') -Encoding ascii -Force }
    Start-Sleep -Seconds 3
    if (Test-TunnelRunning 'bore') {
        Write-Host "[tunnel] bore tunnel started (local port $($config.Port))"
    } else {
        Write-Host '[tunnel] bore failed to start'
    }
}

function Stop-Tunnel {
    param([string]$Name)
    $pf = Get-PidFile $Name
    if (Test-Path $pf) {
        $pid = Get-Content $pf -ErrorAction SilentlyContinue
        if ($pid) { Stop-Process -Id ([int]$pid) -Force -ErrorAction SilentlyContinue }
        Remove-Item $pf -Force
        Write-Host "[tunnel] $Name stopped"
    }
}

function Stop-AllTunnels {
    foreach ($t in @('cloudflared', 'ngrok', 'bore')) { Stop-Tunnel -Name $t }
    Write-Host '[tunnel] All tunnels stopped'
}

function Show-AllStatus {
    foreach ($t in @('cloudflared', 'ngrok', 'bore')) {
        $running = Test-TunnelRunning $t
        Write-Host "  ${t}: $(if ($running) { 'running' } else { 'stopped' })"
    }
}

switch ($Action) {
    'start' {
        $type = if ($TunnelType) { $TunnelType } else { (Load-Config).Type }
        switch ($type) {
            'cloudflare' { Start-Cloudflare }
            'ngrok'      { Start-Ngrok }
            'bore'       { Start-Bore }
            'all'        { Start-Cloudflare; Start-Ngrok; Start-Bore }
        }
    }
    'stop'    { if ($TunnelType) { Stop-Tunnel -Name $TunnelType } else { Stop-AllTunnels } }
    'restart' { Stop-AllTunnels; Start-Sleep -Seconds 2; Start-Cloudflare; Start-Ngrok; Start-Bore }
    'status'  { Show-AllStatus }
    default   { Write-Host 'Usage: tunnel-manager.ps1 {start|stop|restart|status} [cloudflare|ngrok|bore|all]' }
}
