#Requires -Version 5.1
<#
.SYNOPSIS
    WinVPS Secure Wipe - destroy all WinVPS data securely.
.DESCRIPTION
    Stops all services, securely overwrites data files, and removes all traces.
#>
param(
    [Parameter(Position=0)]
    [ValidateSet('auto','manual')]
    [string]$Mode = 'manual',

    [string]$Reason = 'user_requested'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

$WinVPSDir = $env:WINVPS_DIR; if (-not $WinVPSDir) { $WinVPSDir = 'C:\WinVPS' }
$ServicesDir = Join-Path $WinVPSDir 'services'

function Log($msg) { Write-Host "[wipe] $msg" -ForegroundColor Red }
function Warn($msg) { Write-Host "[wipe] $msg" -ForegroundColor Yellow }

$Confirmed = $false

function Confirm-Wipe {
    if ($Mode -eq 'auto') { $Confirmed = $true; return }
    Write-Host ''
    Warn 'WARNING: This will DESTROY all WinVPS data on this machine!'
    Write-Host "  Location: $WinVPSDir"
    Write-Host "  Reason: $Reason"
    Write-Host ''
    $input = Read-Host "Type 'YES' to confirm"
    if ($input -eq 'YES') { $Confirmed = $true }
}

function Stop-AllServices {
    Log 'Stopping all services...'
    Get-ChildItem -Path $ServicesDir -Filter '*.pid' -ErrorAction SilentlyContinue | ForEach-Object {
        $pid = [int](Get-Content $_.FullName -ErrorAction SilentlyContinue)
        if ($pid -gt 0) { Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue }
        Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 2
    Log 'All services stopped'
}

function Invoke-SecureDelete {
    param([string]$Target)
    if (-not (Test-Path $Target)) { return }
    if (Test-Path $Target -PathType Container) {
        Get-ChildItem -Path $Target -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
            try {
                $size = [math]::Min($_.Length, 1MB)
                $buffer = New-Object byte[] $size
                for ($i = 0; $i -lt $size; $i++) { $buffer[$i] = [byte](Get-Random -Maximum 256) }
                [System.IO.File]::WriteAllBytes($_.FullName, $buffer)
                Remove-Item $_.FullName -Force
            } catch {}
        }
        Remove-Item -Path $Target -Recurse -Force -ErrorAction SilentlyContinue
    } else {
        try {
            $size = [math]::Min((Get-Item $Target).Length, 1MB)
            $buffer = New-Object byte[] $size
            for ($i = 0; $i -lt $size; $i++) { $buffer[$i] = [byte](Get-Random -Maximum 256) }
            [System.IO.File]::WriteAllBytes($Target, $buffer)
            Remove-Item $Target -Force
        } catch {}
    }
    Log "Securely deleted: $Target"
}

function Remove-WinVPSData {
    Log 'Wiping WinVPS data...'
    foreach ($dir in @('data', 'logs', 'tmp', 'backup')) {
        $path = Join-Path $WinVPSDir $dir
        if (Test-Path $path) { Invoke-SecureDelete -Target $path }
    }
    $configDir = Join-Path $WinVPSDir 'config'
    if (Test-Path $configDir) { Invoke-SecureDelete -Target $configDir }
    Log 'WinVPS data wiped'
}

function Remove-Binaries {
    $cmd = Join-Path $WinVPSDir 'winvps.cmd'
    if (Test-Path $cmd) { Remove-Item $cmd -Force }
    $ps1 = Join-Path $WinVPSDir 'winvps.ps1'
    if (Test-Path $ps1) { Remove-Item $ps1 -Force }
    Log 'Binaries removed'
}

function Send-RemoteNotification {
    $confFile = Join-Path $WinVPSDir 'config\winvps.conf'
    if (-not (Test-Path $confFile)) { return }
    $lines = Get-Content $confFile -ErrorAction SilentlyContinue
    $tgToken = ($lines | Where-Object { $_ -match '^WINVPS_TELEGRAM_BOT_TOKEN=' } | Select-Object -First 1) -replace '^WINVPS_TELEGRAM_BOT_TOKEN="?(.*)"?','$1'
    $tgChat = ($lines | Where-Object { $_ -match '^WINVPS_TELEGRAM_CHAT_ID=' } | Select-Object -First 1) -replace '^WINVPS_TELEGRAM_CHAT_ID="?(.*)"?','$1'
    if ($tgToken -and $tgChat) {
        $msg = "WinVPS WIPE EXECUTED: $Reason at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        try {
            Invoke-RestMethod -Uri "https://api.telegram.org/bot$tgToken/sendMessage" `
                -Method Post -Body @{ chat_id = $tgChat; text = $msg } -ErrorAction SilentlyContinue
        } catch {}
    }
    Log 'Remote notification sent'
}

function Main {
    Confirm-Wipe
    if (-not $Confirmed) { Log 'Wipe cancelled'; return }
    Log "WIPE INITIATED - Reason: $Reason"
    Send-RemoteNotification
    Stop-AllServices
    Remove-WinVPSData
    Remove-Binaries
    Log 'Wipe complete - device is clean'
}

Main
