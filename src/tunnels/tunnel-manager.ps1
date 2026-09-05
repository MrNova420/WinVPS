#Requires -Version 5.1
<#
.SYNOPSIS
    WinVPS Tunnel Manager v2.0 - Tailscale, Cloudflare, ngrok, bore tunnel management.
.DESCRIPTION
    Downloads and manages tunnel binaries for public access to the WinVPS.
    Supports Tailscale Funnel (requires pre-installed tailscale.exe).
#>
param(
    [Parameter(Position=0)]
    [ValidateSet('start','stop','restart','status')]
    [string]$Action = 'status',

    [string]$TunnelType = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

$WinVPSDir = $env:WINVPS_DIR
if (-not $WinVPSDir) { $WinVPSDir = 'C:\WinVPS' }
$TunnelDir   = Join-Path $WinVPSDir 'tunnels'
$ServicesDir = Join-Path $WinVPSDir 'services'
$LogDir      = Join-Path $WinVPSDir 'logs'
$ConfigFile  = Join-Path $WinVPSDir 'config\winvps.conf'

# Detect VT100/ANSI support — fall back to plain text on legacy terminals
$script:UseAnsi = $false
try { $script:UseAnsi = [bool]$Host.UI.SupportsVirtualTerminal } catch {}
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

if ($script:UseAnsi) {
    $Green  = "`e[38;5;114m"
    $Yellow = "`e[38;5;221m"
    $Red    = "`e[38;5;203m"
    $Dim    = "`e[38;5;243m"
    $Bold   = "`e[1m"
    $NC     = "`e[0m"
} else {
    $Green  = ''; $Yellow = ''; $Red = ''
    $Dim    = ''; $Bold   = ''; $NC  = ''
}

function Log($msg)  { Write-Host "${Green}[tunnel]${NC} $msg" }
function Warn($msg) { Write-Host "${Yellow}[tunnel]${NC} $msg" }
function Err($msg)  { Write-Host "${Red}[tunnel]${NC} $msg" }

if (-not (Test-Path $TunnelDir)) { New-Item -ItemType Directory -Path $TunnelDir -Force | Out-Null }
if (-not (Test-Path $ServicesDir)) { New-Item -ItemType Directory -Path $ServicesDir -Force | Out-Null }
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }

function Load-Config {
    $config = @{ Type = 'cloudflare'; Port = 7080; Token = ''; NgrokToken = ''; TailscaleHostname = '' }
    if (Test-Path $ConfigFile) {
        $lines = Get-Content $ConfigFile
        $type = $lines | Where-Object { $_ -match '^WINVPS_TUNNEL_TYPE=' }
        $port = $lines | Where-Object { $_ -match '^WINVPS_WEB_PORT=' }
        $token = $lines | Where-Object { $_ -match '^WINVPS_TUNNEL_TOKEN=' }
        $ngrok = $lines | Where-Object { $_ -match '^WINVPS_NGROK_TOKEN=' }
        $ts = $lines | Where-Object { $_ -match '^WINVPS_TAILSCALE_HOSTNAME=' }
        if ($type)  { $config.Type = ($type -split '=',2)[1].Trim('"') }
        if ($port)  { $config.Port = [int](($port -split '=',2)[1].Trim('"')) }
        if ($token) { $config.Token = ($token -split '=',2)[1].Trim('"') }
        if ($ngrok) { $config.NgrokToken = ($ngrok -split '=',2)[1].Trim('"') }
        if ($ts)    { $config.TailscaleHostname = ($ts -split '=',2)[1].Trim('"') }
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

# --- Tailscale Funnel ---
function Start-Tailscale {
    $tailscale = Get-Command tailscale -ErrorAction SilentlyContinue
    if (-not $tailscale) {
        Err "tailscale.exe not found in PATH"
        Write-Host "  ${Dim}Install Tailscale: https://tailscale.com/download${NC}"
        return
    }

    if (Test-TunnelRunning 'tailscale') {
        Warn "Tailscale tunnel already running"
        return
    }

    try {
        $status = & tailscale status --json 2>&1
        if ($status -match '"BackendState":"Running"') {
            Log "Tailscale connected"
        } else {
            Warn "Tailscale not connected - please connect first"
            Write-Host "  ${Dim}Run: tailscale up${NC}"
            return
        }
    } catch {
        Warn "Could not check Tailscale status"
        return
    }

    $config = Load-Config
    $port = $config.Port

    Log "Starting Tailscale Funnel on port $port..."
    try {
        $logFile = Join-Path $LogDir 'tailscale.log'
        $proc = Start-Process -FilePath 'tailscale' -ArgumentList "funnel $port" `
            -RedirectStandardOutput $logFile -NoNewWindow -PassThru
        $proc.Id | Out-File -FilePath (Get-PidFile 'tailscale') -Encoding ascii -Force
        Start-Sleep -Seconds 3
        if (Test-TunnelRunning 'tailscale') {
            Log "Tailscale Funnel started on port $port"
            Write-Host "  ${Green}URL:${NC} https://$($config.TailscaleHostname)/"
        } else {
            Warn "Tailscale Funnel failed to start - check logs"
        }
    } catch {
        Err "Failed to start Tailscale Funnel: $_"
    }
}

function Stop-Tailscale {
    try { & tailscale funnel --off 2>&1 | Out-Null } catch {}
    Stop-Tunnel -Name 'tailscale'
}

# --- Cloudflare Tunnel ---
function Start-Cloudflare {
    $bin = Join-Path $TunnelDir 'cloudflared.exe'
    $config = Load-Config

    if (-not (Test-Path $bin)) {
        Log "Downloading cloudflared..."
        try {
            $url = 'https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe'
            Invoke-WebRequest -Uri $url -OutFile $bin -UseBasicParsing -TimeoutSec 60
        } catch {
            Err "Download failed: $_"; return
        }
    }

    if (Test-TunnelRunning 'cloudflared') {
        Warn "Cloudflare already running"; return
    }

    if (-not $config.Token) {
        Err "WINVPS_TUNNEL_TOKEN not set in config"
        Write-Host "  ${Dim}Get a token: https://developers.cloudflare.com/cloudflare-one/connections/connect-networks/${NC}"
        return
    }

    $logFile = Join-Path $LogDir 'cloudflared.log'
    Start-Process -FilePath $bin -ArgumentList "tunnel --no-autoupdate run --token $($config.Token)" `
        -RedirectStandardOutput $logFile -NoNewWindow -PassThru |
        ForEach-Object { $_.Id | Out-File -FilePath (Get-PidFile 'cloudflared') -Encoding ascii -Force }
    Start-Sleep -Seconds 3
    if (Test-TunnelRunning 'cloudflared') {
        Log "Cloudflare tunnel started"
    } else {
        Err "Cloudflare failed - check token and logs"
    }
}

# --- ngrok Tunnel ---
function Start-Ngrok {
    $bin = Join-Path $TunnelDir 'ngrok.exe'
    $config = Load-Config

    if (-not (Test-Path $bin)) {
        Log "Downloading ngrok..."
        try {
            $url = 'https://bin.equinox.io/c/bNyj1mQVY4c/ngrok-v3-stable-windows-amd64.zip'
            $zipFile = Join-Path $env:TEMP 'ngrok.zip'
            Invoke-WebRequest -Uri $url -OutFile $zipFile -UseBasicParsing -TimeoutSec 60
            Expand-Archive -Path $zipFile -DestinationPath $TunnelDir -Force
            Remove-Item $zipFile -Force -ErrorAction SilentlyContinue
        } catch {
            Err "Download failed: $_"; return
        }
    }

    if (Test-TunnelRunning 'ngrok') {
        Warn "ngrok already running"; return
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
        Log "ngrok tunnel started (port $($config.Port))"
    } else {
        Err "ngrok failed to start"
    }
}

# --- bore Tunnel ---
function Start-Bore {
    $bin = Join-Path $TunnelDir 'bore.exe'
    $config = Load-Config

    if (-not (Test-Path $bin)) {
        Log "Downloading bore..."
        try {
            $ver = (Invoke-RestMethod 'https://api.github.com/repos/ekzhang/bore/releases/latest' -ErrorAction SilentlyContinue).tag_name
            if (-not $ver) { $ver = 'v0.5.2' }
            $url = "https://github.com/ekzhang/bore/releases/download/$ver/bore-x86_64-pc-windows-msvc.exe"
            Invoke-WebRequest -Uri $url -OutFile $bin -UseBasicParsing -TimeoutSec 60
        } catch {
            Err "Download failed: $_"; return
        }
    }

    if (Test-TunnelRunning 'bore') {
        Warn "bore already running"; return
    }

    $logFile = Join-Path $LogDir 'bore.log'
    Start-Process -FilePath $bin -ArgumentList "local $($config.Port) --to bore.pub" `
        -RedirectStandardOutput $logFile -NoNewWindow -PassThru |
        ForEach-Object { $_.Id | Out-File -FilePath (Get-PidFile 'bore') -Encoding ascii -Force }
    Start-Sleep -Seconds 3
    if (Test-TunnelRunning 'bore') {
        Log "bore tunnel started (local port $($config.Port))"
    } else {
        Err "bore failed to start"
    }
}

# --- Stop / Status ---
function Stop-Tunnel {
    param([string]$Name)
    $pf = Get-PidFile $Name
    if (Test-Path $pf) {
        $pid = Get-Content $pf -ErrorAction SilentlyContinue
        if ($pid) {
            try {
                $proc = Get-Process -Id ([int]$pid) -ErrorAction SilentlyContinue
                if ($proc) { $proc.Kill() }
            } catch {}
        }
        Remove-Item $pf -Force
        Log "$Name stopped"
    }
}

function Stop-AllTunnels {
    foreach ($t in @('tailscale', 'cloudflared', 'ngrok', 'bore')) { Stop-Tunnel -Name $t }
    Log "All tunnels stopped"
}

function Show-AllStatus {
    Write-Host ''
    Write-Host "  ${Bold}Tunnel Status${NC}"
    Write-Host "  ${Dim}---${NC}"
    foreach ($t in @('tailscale', 'cloudflared', 'ngrok', 'bore')) {
        $running = Test-TunnelRunning $t
        $icon = if ($running) { "${Green}*${NC}" } else { "${Dim}o${NC}" }
        $status = if ($running) { "${Green}running${NC}" } else { "${Dim}stopped${NC}" }
        Write-Host "  $icon $t $status"
    }
    Write-Host ''
}

# --- Main ---
switch ($Action) {
    'start' {
        $type = if ($TunnelType) { $TunnelType } else { (Load-Config).Type }
        switch ($type) {
            'tailscale'  { Start-Tailscale }
            'cloudflare' { Start-Cloudflare }
            'ngrok'      { Start-Ngrok }
            'bore'       { Start-Bore }
            'all'        { Start-Tailscale; Start-Cloudflare; Start-Ngrok; Start-Bore }
            default      { Err "Unknown tunnel type: $type" }
        }
    }
    'stop'    { if ($TunnelType) { Stop-Tunnel -Name $TunnelType } else { Stop-AllTunnels } }
    'restart' { Stop-AllTunnels; Start-Sleep -Seconds 2; $type = (Load-Config).Type; & $PSCommandPath start $type }
    'status'  { Show-AllStatus }
    default   { Write-Host "  Usage: tunnel-manager.ps1 {start|stop|restart|status} [tailscale|cloudflare|ngrok|bore|all]" }
}
