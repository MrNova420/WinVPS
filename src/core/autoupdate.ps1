#Requires -Version 5.1
<#
.SYNOPSIS
    WinVPS Auto-Update - self-update from GitHub, package updates, log rotation.
.DESCRIPTION
    Checks for WinVPS updates, updates packages, rotates logs, and manages backups.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

$WinVPSDir = $env:WINVPS_DIR; if (-not $WinVPSDir) { $WinVPSDir = 'C:\WinVPS' }
$LogDir = Join-Path $WinVPSDir 'logs'
$ConfigFile = Join-Path $WinVPSDir 'config\winvps.conf'
$UpdateStateFile = Join-Path $WinVPSDir 'config\.last_update'

function Log($msg) {
    $logFile = Join-Path $LogDir 'update.log'
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [autoupdate] $msg" | Out-File -FilePath $logFile -Encoding ascii -Append
    Write-Host "[autoupdate] $msg"
}

function Load-Config {
    $config = @{ AutoUpdate = $true; Interval = 'weekly'; AutoBackup = $true }
    if (Test-Path $ConfigFile) {
        $lines = Get-Content $ConfigFile
        $au = $lines | Where-Object { $_ -match '^WINVPS_AUTO_UPDATE=' }
        $iv = $lines | Where-Object { $_ -match '^WINVPS_UPDATE_INTERVAL=' }
        $ab = $lines | Where-Object { $_ -match '^WINVPS_AUTO_BACKUP=' }
        if ($au) { $config.AutoUpdate = ($au -split '=',2)[1].Trim('"') -eq 'true' }
        if ($iv) { $config.Interval = ($iv -split '=',2)[1].Trim('"') }
        if ($ab) { $config.AutoBackup = ($ab -split '=',2)[1].Trim('"') -eq 'true' }
    }
    return $config
}

function Test-UpdateDue {
    if (-not (Test-Path $UpdateStateFile)) {
        (Get-Date -UFormat %s) | Out-File -FilePath $UpdateStateFile -Encoding ascii -Force
        return $true
    }
    $last = [double](Get-Content $UpdateStateFile)
    $now = [double][int][double]::Parse((Get-Date -UFormat %s))
    $interval = switch ((Load-Config).Interval) {
        'daily'   { 86400 }
        'weekly'  { 604800 }
        'monthly' { 2592000 }
        default   { 604800 }
    }
    return (($now - $last) -ge $interval)
}

function Update-Packages {
    Log 'Checking for package updates...'
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        & winget upgrade --all --accept-source-agreements 2>&1 | Out-Null
        Log 'winget packages updated'
    }
}

function Update-Self {
    Log 'Checking for WinVPS updates...'
    try {
        $release = Invoke-RestMethod 'https://api.github.com/repos/MrNova420/AnVPS/releases/latest' -TimeoutSec 10 -ErrorAction Stop
        $latest = $release.tag_name
        $currentVersion = '1.0.0'
        if (Test-Path $ConfigFile) {
            $line = Get-Content $ConfigFile | Where-Object { $_ -match '^WINVPS_VERSION=' }
            if ($line) { $currentVersion = ($line -split '=',2)[1].Trim('"') }
        }
        if ($latest -ne "v$currentVersion") {
            Log "New version available: $latest (current: v$currentVersion)"
            $tmpDir = Join-Path $env:TEMP 'winvps-update'
            if (-not (Test-Path $tmpDir)) { New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null }
            $url = "https://github.com/MrNova420/AnVPS/archive/refs/tags/$latest.zip"
            $zipFile = Join-Path $tmpDir 'update.zip'
            Invoke-WebRequest -Uri $url -OutFile $zipFile -UseBasicParsing -TimeoutSec 30
            Expand-Archive -Path $zipFile -DestinationPath $tmpDir -Force
            $src = Get-ChildItem -Path $tmpDir -Directory | Where-Object { $_.Name -match 'AnVPS' } | Select-Object -First 1
            if ($src) {
                Copy-Item -Path "$($src.FullName)\src\*" -Destination (Join-Path $WinVPSDir 'src') -Recurse -Force
                Log "WinVPS updated to $latest"
            }
            Remove-Item $tmpDir -Recurse -Force -ErrorAction SilentlyContinue
        } else {
            Log 'WinVPS is up to date'
        }
    } catch {
        Log "Update check failed: $_"
    }
}

function Invoke-LogRotation {
    Log 'Rotating logs...'
    if (-not (Test-Path $LogDir)) { return }
    Get-ChildItem -Path $LogDir -Filter '*.log' -ErrorAction SilentlyContinue |
        Where-Object { $_.Length -gt 10MB } | ForEach-Object {
            $old = Join-Path $LogDir "$($_.BaseName).old.log"
            Move-Item -Path $_.FullName -Destination $old -Force
            New-Item -ItemType File -Path $_.FullName -Force | Out-Null
        }
    Get-ChildItem -Path $LogDir -Filter '*.old.log' -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-7) } | Remove-Item -Force
    Get-ChildItem -Path $LogDir -Filter '*.log' -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } | Remove-Item -Force
    Log 'Log rotation complete'
}

function Invoke-TempCleanup {
    Log 'Cleaning temp files...'
    $tmpDir = Join-Path $WinVPSDir 'tmp'
    if (Test-Path $tmpDir) {
        Get-ChildItem -Path $tmpDir -File -ErrorAction SilentlyContinue |
            Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-1) } | Remove-Item -Force
    }
    Log 'Temp cleanup complete'
}

function Invoke-AutoBackup {
    $config = Load-Config
    if (-not $config.AutoBackup) { return }
    $backupScript = Join-Path $WinVPSDir 'src\cli\winvps.ps1'
    if (Test-Path $backupScript) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $backupScript backup create 2>&1 | Out-Null
    }
}

function Invoke-UpdateCycle {
    $config = Load-Config
    if (-not $config.AutoUpdate) { Log 'Auto-update disabled'; return }
    if (-not (Test-UpdateDue)) { Log 'Skipping - not yet time for update'; return }

    Log 'Starting auto-update cycle...'
    Update-Packages
    Update-Self
    Invoke-LogRotation
    Invoke-TempCleanup
    Invoke-AutoBackup
    (Get-Date -UFormat %s) | Out-File -FilePath $UpdateStateFile -Encoding ascii -Force
    Log 'Auto-update cycle complete'
}

Invoke-UpdateCycle
