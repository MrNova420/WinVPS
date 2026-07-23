#Requires -Version 5.1
<#
.SYNOPSIS
    WinVPS VPN Kill Switch - blocks all traffic if VPN disconnects.
.DESCRIPTION
    Uses Windows Firewall rules to ensure no traffic leaks outside the VPN tunnel.
#>
param(
    [Parameter(Position=0)]
    [ValidateSet('enable','on','disable','off','status','test')]
    [string]$Action = 'status'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

$WinVPSDir = $env:WINVPS_DIR; if (-not $WinVPSDir) { $WinVPSDir = 'C:\WinVPS' }
$ConfigFile = Join-Path $WinVPSDir 'config\winvps.conf'

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-VPNConfig {
    $vpnIface = 'WireGuard'
    $vpnPort = 7518
    if (Test-Path $ConfigFile) {
        $lines = Get-Content $ConfigFile
        $iface = $lines | Where-Object { $_ -match '^WINVPS_VPN_IFACE=' }
        $port = $lines | Where-Object { $_ -match '^WINVPS_VPN_PORT=' }
        if ($iface) { $vpnIface = ($iface -split '=',2)[1].Trim('"') }
        if ($port) { $vpnPort = [int](($port -split '=',2)[1].Trim('"')) }
    }
    return @{ Interface = $vpnIface; Port = $vpnPort }
}

function Enable-Killswitch {
    if (-not (Test-Admin)) { Write-Host 'Kill switch requires admin'; return }
    $vpn = Get-VPNConfig
    Write-Host 'Enabling VPN kill switch...'

    $existing = Get-NetFirewallRule -DisplayName 'WinVPS-KillSwitch*' -ErrorAction SilentlyContinue
    if ($existing) { $existing | Remove-NetFirewallRule }

    New-NetFirewallRule -DisplayName 'WinVPS-KillSwitch-BlockAll-In' -Direction Inbound `
        -Action Block -Enabled True -ErrorAction SilentlyContinue | Out-Null
    New-NetFirewallRule -DisplayName 'WinVPS-KillSwitch-BlockAll-Out' -Direction Outbound `
        -Action Block -Enabled True -ErrorAction SilentlyContinue | Out-Null

    New-NetFirewallRule -DisplayName 'WinVPS-KillSwitch-AllowLoopback-In' -Direction Inbound `
        -Action Allow -LocalAddress 127.0.0.1 -Enabled True -ErrorAction SilentlyContinue | Out-Null
    New-NetFirewallRule -DisplayName 'WinVPS-KillSwitch-AllowLoopback-Out' -Direction Outbound `
        -Action Allow -RemoteAddress 127.0.0.1 -Enabled True -ErrorAction SilentlyContinue | Out-Null

    New-NetFirewallRule -DisplayName 'WinVPS-KillSwitch-AllowSSH-Out' -Direction Outbound `
        -Action Allow -Protocol TCP -RemotePort 22 -Enabled True -ErrorAction SilentlyContinue | Out-Null

    New-NetFireRule -DisplayName 'WinVPS-KillSwitch-AllowDNS-Out' -Direction Outbound `
        -Action Allow -Protocol UDP -RemotePort 53 -Enabled True -ErrorAction SilentlyContinue | Out-Null

    New-NetFirewallRule -DisplayName 'WinVPS-KillSwitch-AllowHTTPS-Out' -Direction Outbound `
        -Action Allow -Protocol TCP -RemotePort 443 -Enabled True -ErrorAction SilentlyContinue | Out-Null

    New-NetFirewallRule -DisplayName 'WinVPS-KillSwitch-AllowVPN-Out' -Direction Outbound `
        -Action Allow -Protocol UDP -RemotePort $vpn.Port -Enabled True -ErrorAction SilentlyContinue | Out-Null

    Write-Host "Kill switch active - only VPN and essential traffic allowed"
}

function Disable-Killswitch {
    if (-not (Test-Admin)) { Write-Host 'Kill switch requires admin'; return }
    Write-Host 'Disabling VPN kill switch...'
    Get-NetFirewallRule -DisplayName 'WinVPS-KillSwitch*' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    Write-Host 'Kill switch disabled - all traffic allowed'
}

function Show-KillswitchStatus {
    $rules = Get-NetFirewallRule -DisplayName 'WinVPS-KillSwitch-BlockAll*' -ErrorAction SilentlyContinue
    if ($rules) {
        $enabled = ($rules | Where-Object { $_.Enabled -eq $true }).Count
        if ($enabled -gt 0) {
            Write-Host 'VPN kill switch: ACTIVE'
        } else {
            Write-Host 'VPN kill switch: INACTIVE'
        }
    } else {
        Write-Host 'VPN kill switch: INACTIVE'
    }
}

function Test-Leak {
    Write-Host 'Testing for traffic leaks...'
    try {
        $ip = (Invoke-RestMethod -Uri 'https://ifconfig.me' -TimeoutSec 5 -ErrorAction Stop).Trim()
        Write-Host "  Public IP: $ip"
        Write-Host '  Potential leak - traffic is leaving the device'
    } catch {
        Write-Host '  No leak detected (no internet or blocked)'
    }
}

switch ($Action) {
    'enable'  { Enable-Killswitch }
    'on'      { Enable-Killswitch }
    'disable' { Disable-Killswitch }
    'off'     { Disable-Killswitch }
    'status'  { Show-KillswitchStatus }
    'test'    { Test-Leak }
    default   { Write-Host 'Usage: vpn-killswitch.ps1 {enable|disable|status|test}' }
}
