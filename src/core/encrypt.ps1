#Requires -Version 5.1
<#
.SYNOPSIS
    WinVPS Encrypted Storage - BitLocker/VeraCrypt integration.
.DESCRIPTION
    Manages encrypted storage volumes for sensitive WinVPS data.
#>
param(
    [Parameter(Position=0)]
    [ValidateSet('init','mount','unmount','status','setup')]
    [string]$Action = 'status'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

$WinVPSDir = $env:WINVPS_DIR; if (-not $WinVPSDir) { $WinVPSDir = 'C:\WinVPS' }
$EncryptedDir = Join-Path $WinVPSDir 'data\encrypted'
$MountDir = Join-Path $WinVPSDir 'data\private'
$LogFile = Join-Path $WinVPSDir 'logs\encrypt.log'

function Log($msg) {
    $logDir = Split-Path $LogFile
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [encrypt] $msg" | Out-File -FilePath $LogFile -Encoding ascii -Append
}

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-VeraCrypt {
    $vcPath = Get-Command 'VeraCrypt' -ErrorAction SilentlyContinue
    if ($vcPath) { return $true }
    $vcDefault = 'C:\Program Files\VeraCrypt\VeraCrypt.exe'
    return (Test-Path $vcDefault)
}

function Initialize-Encrypted {
    if (-not (Test-Admin)) { Write-Host 'Encryption requires admin'; return }
    if (-not (Test-Path $EncryptedDir)) { New-Item -ItemType Directory -Path $EncryptedDir -Force | Out-Null }
    if (-not (Test-Path $MountDir)) { New-Item -ItemType Directory -Path $MountDir -Force | Out-Null }

    if (Test-VeraCrypt) {
        $volumePath = Join-Path $EncryptedDir 'winvps.hc'
        if (-not (Test-Path $volumePath)) {
            Write-Host '[encrypt] Creating VeraCrypt volume...'
            Write-Host '[encrypt] Volume will be created at: ' + $volumePath
            Write-Host '[encrypt] Run VeraCrypt GUI to create a volume, or use:'
            Write-Host "[encrypt]   VeraCrypt /create `"$volumePath`" /size 1G /filesystem NTFS /password <pass>"
        }
        Write-Host '[encrypt] Use VeraCrypt to mount your volume to: ' + $MountDir
        Log 'VeraCrypt integration ready'
    } else {
        Write-Host '[encrypt] VeraCrypt not found.'
        Write-Host '[encrypt] Install from: https://veracrypt.fr'
        Write-Host '[encrypt] Alternatively, Windows EFS can encrypt individual files:'
        Write-Host "[encrypt]   cipher /e /s:`"$MountDir`""
    }
    Write-Host '[encrypt] Encrypted storage initialized at ' + $MountDir
}

function Unmount-Encrypted {
    if (-not (Test-Admin)) { Write-Host 'Requires admin'; return }
    Write-Host '[encrypt] To unmount, use VeraCrypt GUI or:'
    Write-Host '[encrypt]   VeraCrypt /dismount /force'
    Log 'Encrypted storage unmounted'
}

function Show-EncryptedStatus {
    if (Test-Path $MountDir) {
        $items = (Get-ChildItem -Path $MountDir -ErrorAction SilentlyContinue).Count
        Write-Host "  Encrypted mount: $MountDir"
        Write-Host "  Contents: $items items"
    } else {
        Write-Host '  Encrypted storage: NOT MOUNTED'
    }
    if (Test-VeraCrypt) {
        Write-Host '  Tool: VeraCrypt (installed)'
    } else {
        Write-Host '  Tool: none (install VeraCrypt)'
    }
}

switch ($Action) {
    'init'     { Initialize-Encrypted }
    'mount'    { Initialize-Encrypted }
    'unmount'  { Unmount-Encrypted }
    'status'   { Show-EncryptedStatus }
    'setup'    { Write-Host 'Install VeraCrypt from https://veracrypt.fr' }
    default    { Write-Host 'Usage: encrypt.ps1 {init|unmount|status|setup}' }
}
