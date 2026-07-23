#Requires -Version 5.1
<#
.SYNOPSIS
    WinVPS Obfuscation - mask device identity, randomize hostname, MAC, SSH keys.
.DESCRIPTION
    Randomizes various device identifiers to make the machine harder to fingerprint.
#>
param(
    [Parameter(Position=0)]
    [ValidateSet('all','hostname','ssh','mac','http','status')]
    [string]$Action = 'status'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

$WinVPSDir = $env:WINVPS_DIR; if (-not $WinVPSDir) { $WinVPSDir = 'C:\WinVPS' }
$StateFile = Join-Path $WinVPSDir 'config\.obfuscated'
$ConfigDir = Join-Path $WinVPSDir 'config'
$SshDataDir = Join-Path $WinVPSDir 'config\ssh'

function Get-RandomString {
    param([int]$Length = 8)
    $chars = 'abcdefghijklmnopqrstuvwxyz0123456789'
    $result = ''
    for ($i = 0; $i -lt $Length; $i++) {
        $result += $chars[(Get-Random -Maximum $chars.Length)]
    }
    return $result
}

function Set-Hostname {
    $newName = "winvps-$(Get-RandomString 6)"
    if (Test-Admin) {
        try {
            Rename-Computer -NewName $newName -Force -ErrorAction Stop
            Log "Hostname obfuscated: $newName"
        } catch {
            Log "Could not rename computer: $_"
        }
    }
    $newName | Out-File -FilePath (Join-Path $ConfigDir '.hostname') -Encoding ascii -Force
    Write-Host "Hostname obfuscated: $newName"
}

function Reset-SshKeys {
    Write-Host 'Rotating SSH host keys...'
    $sshDir = Join-Path $env:ProgramData 'ssh'
    if (Test-Path $sshDir) {
        Get-ChildItem -Path $sshDir -Filter 'ssh_host_*_key' -ErrorAction SilentlyContinue | ForEach-Object {
            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
        }
        & ssh-keygen -A 2>&1 | Out-Null
    }
    Write-Host 'SSH host keys rotated'
}

function Set-MacRandomization {
    if (-not (Test-Admin)) { Write-Host 'MAC randomization requires admin'; return }
    try {
        $adapters = Get-NetAdapter -Physical -ErrorAction SilentlyContinue | Where-Object { $_.Status -eq 'Up' }
        foreach ($adapter in $adapters) {
            Set-NetAdapter -Name $adapter.Name -MacAddress ('{0:X2}-{1:X2}-{2:X2}-{3:X2}-{4:X2}-{5:X2}' -f `
                (Get-Random -Minimum 0x02 -Maximum 0xFE),
                (Get-Random -Maximum 256), (Get-Random -Maximum 256),
                (Get-Random -Maximum 256), (Get-Random -Maximum 256),
                (Get-Random -Maximum 256)) -Confirm:$false -ErrorAction SilentlyContinue
            Write-Host "MAC randomized for $($adapter.Name)"
        }
    } catch {
        Write-Host "MAC randomization failed: $_"
    }
}

function Set-HttpUserAgent {
    $agents = @(
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 Chrome/120.0.0.0',
        'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 Safari/17.2',
        'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/120.0.0.0'
    )
    $agents[(Get-Random $agents.Count)] | Out-File -FilePath (Join-Path $ConfigDir '.user_agent') -Encoding ascii -Force
    Write-Host 'HTTP User-Agent randomized'
}

function Invoke-ObfuscateAll {
    Write-Host 'Running full device obfuscation...'
    Set-Hostname
    Reset-SshKeys
    Set-MacRandomization
    Set-HttpUserAgent
    (Get-Date -UFormat %s) | Out-File -FilePath $StateFile -Encoding ascii -Force
    Write-Host 'Device obfuscation complete'
}

function Show-ObfuscateStatus {
    if (Test-Path $StateFile) {
        $last = Get-Content $StateFile -ErrorAction SilentlyContinue
        Write-Host "  Device obfuscated (last: $last)"
    } else {
        Write-Host '  Device NOT obfuscated'
    }
    $hostFile = Join-Path $ConfigDir '.hostname'
    if (Test-Path $hostFile) {
        Write-Host "  Hostname: $(Get-Content $hostFile)"
    } else {
        Write-Host "  Hostname: $env:COMPUTERNAME"
    }
}

function Log($msg) {
    $logFile = Join-Path $WinVPSDir 'logs\obfuscate.log'
    if (-not (Test-Path (Split-Path $logFile))) { New-Item -ItemType Directory -Path (Split-Path $logFile) -Force | Out-Null }
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [obfuscate] $msg" | Out-File -FilePath $logFile -Encoding ascii -Append
}

switch ($Action) {
    'all'      { Invoke-ObfuscateAll }
    'hostname' { Set-Hostname }
    'ssh'      { Reset-SshKeys }
    'mac'      { Set-MacRandomization }
    'http'     { Set-HttpUserAgent }
    'status'   { Show-ObfuscateStatus }
    default    { Write-Host 'Usage: obfuscate.ps1 {all|hostname|ssh|mac|http|status}' }
}
