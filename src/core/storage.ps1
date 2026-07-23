#Requires -Version 5.1
<#
.SYNOPSIS
    WinVPS Storage Manager - disk usage, cleanup, and analysis.
.DESCRIPTION
    Monitors disk usage, cleans up logs and temp files, and provides storage analysis.
#>
param(
    [Parameter(Position=0)]
    [ValidateSet('status','cleanup','analyze')]
    [string]$Action = 'status'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

$WinVPSDir = $env:WINVPS_DIR; if (-not $WinVPSDir) { $WinVPSDir = 'C:\WinVPS' }
$LogDir = Join-Path $WinVPSDir 'logs'

function Get-DirSize {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return '0B' }
    $bytes = (Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    if ($null -eq $bytes) { return '0B' }
    if ($bytes -gt 1GB) { return "$([math]::Round($bytes/1GB,2))GB" }
    if ($bytes -gt 1MB) { return "$([math]::Round($bytes/1MB,2))MB" }
    if ($bytes -gt 1KB) { return "$([math]::Round($bytes/1KB,2))KB" }
    return "${bytes}B"
}

function Show-StorageStatus {
    Write-Host ''
    Write-Host '  Storage Status'
    Write-Host '  ----------------------------------------'
    Write-Host ''
    Write-Host "  WinVPS Home:  $(Get-DirSize $WinVPSDir)"
    Write-Host "  Data:         $(Get-DirSize (Join-Path $WinVPSDir 'data'))"
    Write-Host "  Logs:         $(Get-DirSize $LogDir)"
    Write-Host "  Backups:      $(Get-DirSize (Join-Path $WinVPSDir 'backup'))"
    $drive = Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='$($WinVPSDir.Substring(0,2))'" -ErrorAction SilentlyContinue
    if ($drive) {
        $used = $drive.Size - $drive.FreeSpace
        $pct = [math]::Round(($used / $drive.Size) * 100)
        Write-Host "  Total Disk:   $([math]::Round($used/1GB,1))GB / $([math]::Round($drive.Size/1GB,1))GB ($pct%)"
    }
    Write-Host ''
}

function Invoke-Cleanup {
    Write-Host '  Running storage cleanup...'
    $freed = 0

    Get-ChildItem -Path $LogDir -Filter '*.log' -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -gt 5MB } | ForEach-Object {
            Set-Content -Path $_.FullName -Value '' -Force
            $freed++
        }

    Get-ChildItem -Path $LogDir -Filter '*.old' -ErrorAction SilentlyContinue | Remove-Item -Force
    $freed++

    $tmpDir = Join-Path $WinVPSDir 'tmp'
    if (Test-Path $tmpDir) {
        Get-ChildItem -Path $tmpDir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-1) } | Remove-Item -Force
        $freed++
    }

    Write-Host "  Cleanup complete - cleaned $freed areas"
}

function Show-Analysis {
    Write-Host '  Storage Analysis'
    Write-Host '  ----------------------------------------'
    Write-Host ''
    Get-ChildItem -Path $WinVPSDir -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $size = Get-DirSize $_.FullName
        $count = (Get-ChildItem -Path $_.FullName -Recurse -File -ErrorAction SilentlyContinue).Count
        Write-Host ("  {0,-15} {1,10} ({2} files)" -f $_.Name, $size, $count)
    }
    Write-Host ''
}

switch ($Action) {
    'status'  { Show-StorageStatus }
    'cleanup' { Invoke-Cleanup }
    'analyze' { Show-Analysis }
    default   { Write-Host 'Usage: storage.ps1 {status|cleanup|analyze}' }
}
