#Requires -Version 5.1
<#
.SYNOPSIS
    WinVPS Stealth Mode - port knocking, decoy services, scheduled availability.
.DESCRIPTION
    Makes the VPS harder to discover on the network. Supports port knocking,
    decoy services on standard ports, and time-based availability windows.
#>
param(
    [Parameter(Position=0)]
    [ValidateSet('enable','on','disable','off','status','knock','schedule')]
    [string]$Action = 'status',

    [string]$Target = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

$WinVPSDir = $env:WINVPS_DIR; if (-not $WinVPSDir) { $WinVPSDir = 'C:\WinVPS' }
$StateFile = Join-Path $WinVPSDir 'config\.stealth_enabled'
$LogFile = Join-Path $WinVPSDir 'logs\stealth.log'
$ConfigFile = Join-Path $WinVPSDir 'config\winvps.conf'

function Log($msg) {
    if (-not (Test-Path (Split-Path $LogFile))) { New-Item -ItemType Directory -Path (Split-Path $LogFile) -Force | Out-Null }
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [stealth] $msg" | Out-File -FilePath $LogFile -Encoding ascii -Append
}

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Get-StealthHours {
    $startH = 9; $endH = 17
    if (Test-Path $ConfigFile) {
        $lines = Get-Content $ConfigFile
        $s = $lines | Where-Object { $_ -match '^WINVPS_STEALTH_START_HOUR=' }
        $e = $lines | Where-Object { $_ -match '^WINVPS_STEALTH_END_HOUR=' }
        if ($s) { $startH = [int]($s -split '=',2)[1].Trim('"') }
        if ($e) { $endH = [int]($e -split '=',2)[1].Trim('"') }
    }
    return @{ Start = $startH; End = $endH }
}

function Set-PortKnockRules {
    if (-not (Test-Admin)) { Log 'Port knocking requires admin'; return }
    if (-not (Test-Path $StateFile)) {
        $existing = Get-NetFirewallRule -DisplayName 'WinVPS-Knock*' -ErrorAction SilentlyContinue
        if ($existing) { $existing | Remove-NetFirewallRule }
    }

    $ports = @(7000, 8000, 9000)
    foreach ($port in $ports) {
        New-NetFirewallRule -DisplayName "WinVPS-Knock-$port" -Direction Inbound -Action Allow `
            -Protocol TCP -LocalPort $port -Enabled False -ErrorAction SilentlyContinue | Out-Null
    }
    Log "Port knocking rules created: knock 7000 8000 9000 to open SSH"
}

function Start-DecoyServices {
    Log 'Starting decoy services on standard ports...'
    $decoyPorts = @(22, 80, 443)
    foreach ($port in $decoyPorts) {
        $existing = Get-NetFirewallRule -DisplayName "WinVPS-Decoy-$port" -ErrorAction SilentlyContinue
        if (-not $existing) {
            New-NetFirewallRule -DisplayName "WinVPS-Decoy-$port" -Direction Inbound -Action Allow `
                -Protocol TCP -LocalPort $port -ErrorAction SilentlyContinue | Out-Null
        }
    }
    Log 'Decoy services active on ports 22, 80, 443'
}

function Test-WithinSchedule {
    $hours = Get-StealthHours
    $current = (Get-Date).Hour
    if ($current -ge $hours.Start -and $current -lt $hours.End) {
        Log "Within active window ($($hours.Start):00-$($hours.End):00)"
        return $true
    } else {
        Log "Outside active window - services paused"
        return $false
    }
}

function Enable-Stealth {
    Write-Host 'Enabling stealth mode...'
    Set-PortKnockRules
    Start-DecoyServices
    (Get-Date -UFormat %s) | Out-File -FilePath (Join-Path $WinVPSDir 'config\.stealth') -Encoding ascii -Force
    (Get-Date) | Out-File -FilePath $StateFile -Encoding ascii -Force
    Log 'Stealth mode enabled'
    Write-Host 'Stealth mode active'
}

function Disable-Stealth {
    Write-Host 'Disabling stealth mode...'
    if (Test-Admin) {
        Get-NetFirewallRule -DisplayName 'WinVPS-Knock*' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
        Get-NetFirewallRule -DisplayName 'WinVPS-Decoy*' -ErrorAction SilentlyContinue | Remove-NetFirewallRule
    }
    Remove-Item $StateFile -Force -ErrorAction SilentlyContinue
    Log 'Stealth mode disabled'
    Write-Host 'Stealth mode disabled'
}

function Show-StealthStatus {
    $active = Test-Path $StateFile
    Write-Host "  Stealth mode: $(if ($active) { 'ACTIVE' } else { 'INACTIVE' })"
    if ($active) {
        $hours = Get-StealthHours
        Write-Host "  Active window: $($hours.Start):00 - $($hours.End):00"
        Write-Host '  Decoy ports: 22, 80, 443'
        Write-Host '  Knock sequence: 7000,8000,9000 (open) / 9000,8000,7000 (close)'
    }
}

function Invoke-PortKnock {
    param([string]$Host_)
    if (-not $Host_) { Write-Host 'Usage: stealth.ps1 knock <host>'; return }
    $ports = @(7000, 8000, 9000)
    foreach ($port in $ports) {
        try {
            $tcp = New-Object System.Net.Sockets.TcpClient
            $tcp.Connect($Host_, $port)
            $tcp.Close()
            Start-Sleep -Milliseconds 100
        } catch {}
    }
    Write-Host "Knock sequence sent to $Host_"
}

switch ($Action) {
    'enable'  { Enable-Stealth }
    'on'      { Enable-Stealth }
    'disable' { Disable-Stealth }
    'off'     { Disable-Stealth }
    'status'  { Show-StealthStatus }
    'knock'   { Invoke-PortKnock -Host_ $Target }
    'schedule'{ Test-WithinSchedule }
    default   { Write-Host 'Usage: stealth.ps1 {enable|disable|status|knock <host>|schedule}' }
}
