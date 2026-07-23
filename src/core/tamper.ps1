#Requires -Version 5.1
<#
.SYNOPSIS
    WinVPS Tamper Detection - integrity checking, dead man switch, auto-wipe trigger.
.DESCRIPTION
    Monitors file integrity via SHA256 checksums, tracks failed auth attempts,
    and implements a dead man switch that triggers secure wipe if offline too long.
#>
param(
    [Parameter(Position=0)]
    [ValidateSet('init','verify','check','wipe','reset','status')]
    [string]$Action = 'status'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

$WinVPSDir = $env:WINVPS_DIR; if (-not $WinVPSDir) { $WinVPSDir = 'C:\WinVPS' }
$ConfigDir = Join-Path $WinVPSDir 'config'
$ChecksumFile = Join-Path $ConfigDir '.checksums'
$TimerFile = Join-Path $ConfigDir '.last_seen'
$WipeFlag = Join-Path $ConfigDir '.wipe_triggered'
$WipePending = Join-Path $WinVPSDir 'tmp\wipe_pending'
$ConfigFile = Join-Path $ConfigDir 'winvps.conf'
$LogFile = Join-Path $WinVPSDir 'logs\tamper.log'

function Log($msg) {
    $logDir = Split-Path $LogFile
    if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [tamper] $msg" | Out-File -FilePath $LogFile -Encoding ascii -Append
}

function Get-MaxFailedAuth {
    $max = 10
    if (Test-Path $ConfigFile) {
        $line = Get-Content $ConfigFile | Where-Object { $_ -match '^WINVPS_TAMPER_MAX_FAILED=' }
        if ($line) { $max = [int]($line -split '=',2)[1].Trim('"') }
    }
    return $max
}

function Get-DeadManDays {
    $days = 30
    if (Test-Path $ConfigFile) {
        $line = Get-Content $ConfigFile | Where-Object { $_ -match '^WINVPS_DEAD_MAN_DAYS=' }
        if ($line) { $days = [int]($line -split '=',2)[1].Trim('"') }
    }
    return $days
}

function Initialize-Checksums {
    Write-Host 'Initializing integrity checksums...'
    $checksums = @()
    $filesToCheck = @(
        (Join-Path $ConfigDir 'winvps.conf'),
        (Join-Path $ConfigDir 'services.conf')
    )
    foreach ($f in $filesToCheck) {
        if (Test-Path $f) {
            $hash = (Get-FileHash -Path $f -Algorithm SHA256).Hash
            $checksums += "$hash  $f"
        }
    }
    $coreDir = Join-Path $WinVPSDir 'src\core'
    if (Test-Path $coreDir) {
        Get-ChildItem -Path $coreDir -Filter '*.ps1' | ForEach-Object {
            $hash = (Get-FileHash -Path $_.FullName -Algorithm SHA256).Hash
            $checksums += "$hash  $($_.FullName)"
        }
    }
    $cliFile = Join-Path $WinVPSDir 'src\cli\winvps.ps1'
    if (Test-Path $cliFile) {
        $hash = (Get-FileHash -Path $cliFile -Algorithm SHA256).Hash
        $checksums += "$hash  $cliFile"
    }
    $checksums | Out-File -FilePath $ChecksumFile -Encoding ascii -Force
    Log 'Checksums initialized'
    Write-Host "  Checksums recorded for $($checksums.Count) files"
}

function Test-Integrity {
    if (-not (Test-Path $ChecksumFile)) {
        Log 'No checksum file - initializing first run'
        Initialize-Checksums
        return $true
    }
    $violations = 0
    Get-Content $ChecksumFile | Where-Object { $_.Trim() } | ForEach-Object {
        $parts = $_ -split '\s+', 2
        if ($parts.Count -eq 2) {
            $expectedHash = $parts[0]
            $file = $parts[1]
            if (-not (Test-Path $file)) {
                Log "MISSING: $file"
                $violations++
                return
            }
            $actualHash = (Get-FileHash -Path $file -Algorithm SHA256).Hash
            if ($expectedHash -ne $actualHash) {
                Log "TAMPER DETECTED: $file (hash mismatch)"
                $violations++
            }
        }
    }
    if ($violations -gt 0) {
        Log "INTEGRITY FAILURE: $violations file(s) tampered"
        Invoke-Wipe -Reason 'integrity_check'
        return $false
    }
    Log 'Integrity check passed'
    return $true
}

function Test-FailedAuth {
    $maxFailed = Get-MaxFailedAuth
    $sshLog = Join-Path $WinVPSDir 'logs\ssh.log'
    if (-not (Test-Path $sshLog)) { return }
    $failed = (Select-String -Path $sshLog -Pattern 'Failed password|auth failure|Bad protocol' -ErrorAction SilentlyContinue).Count
    if ($failed -gt $maxFailed) {
        Log "BRUTE FORCE DETECTED: $failed failed auth attempts"
        Invoke-Wipe -Reason 'brute_force'
    }
}

function Test-DeadMan {
    $maxDays = Get-DeadManDays
    if (-not (Test-Path $TimerFile)) {
        [int][double]::Parse((Get-Date -UFormat %s)) | Out-File -FilePath $TimerFile -Encoding ascii -Force
        return
    }
    $last = [int](Get-Content $TimerFile)
    $now = [int][double]::Parse((Get-Date -UFormat %s))
    $elapsedDays = [math]::Floor(($now - $last) / 86400)
    if ($elapsedDays -gt $maxDays) {
        Log "DEAD MAN SWITCH: device offline $elapsedDays days"
        Invoke-Wipe -Reason 'dead_man'
    }
    [int][double]::Parse((Get-Date -UFormat %s)) | Out-File -FilePath $TimerFile -Encoding ascii -Force
}

function Invoke-Wipe {
    param([string]$Reason = 'manual')
    Log "WIPE TRIGGERED: $Reason"
    $Reason | Out-File -FilePath $WipeFlag -Encoding ascii -Force
    $tmpDir = Split-Path $WipePending
    if (-not (Test-Path $tmpDir)) { New-Item -ItemType Directory -Path $tmpDir -Force | Out-Null }
    'pending' | Out-File -FilePath $WipePending -Encoding ascii -Force
    $wipeScript = Join-Path $WinVPSDir 'src\core\wipe.ps1'
    if (Test-Path $wipeScript) {
        Log 'Executing wipe...'
        Start-Process powershell -ArgumentList "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$wipeScript`" auto $Reason" -WindowStyle Hidden
    }
}

function Reset-TamperState {
    Remove-Item $ChecksumFile -Force -ErrorAction SilentlyContinue
    Initialize-Checksums
    Remove-Item $WipeFlag -Force -ErrorAction SilentlyContinue
    Remove-Item $WipePending -Force -ErrorAction SilentlyContinue
    [int][double]::Parse((Get-Date -UFormat %s)) | Out-File -FilePath $TimerFile -Encoding ascii -Force
    Log 'Tamper state reset'
    Write-Host 'Tamper state reset'
}

function Show-TamperStatus {
    Write-Host "  Integrity:    $(if (Test-Path $ChecksumFile) { 'initialized' } else { 'uninitialized' })"
    Write-Host "  Wipe pending: $(if (Test-Path $WipePending) { 'YES' } else { 'no' })"
    Write-Host "  Max failed auth: $(Get-MaxFailedAuth)"
    Write-Host "  Dead man days:   $(Get-DeadManDays)"
    if (Test-Path $TimerFile) {
        $last = [int](Get-Content $TimerFile)
        $now = [int][double]::Parse((Get-Date -UFormat %s))
        $ago = [math]::Floor(($now - $last) / 86400)
        Write-Host "  Last seen: $ago days ago"
    }
}

switch ($Action) {
    'init'   { Initialize-Checksums }
    'verify' { Test-Integrity | Out-Null }
    'check'  { Test-FailedAuth; Test-DeadMan }
    'wipe'   { Invoke-Wipe -Reason 'manual' }
    'reset'  { Reset-TamperState }
    'status' { Show-TamperStatus }
    default  { Write-Host 'Usage: tamper.ps1 {init|verify|check|wipe|reset|status}' }
}
