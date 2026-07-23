#Requires -Version 5.1
<#
.SYNOPSIS
    Lightweight mode controller - auto-selects minimal components based on RAM.
.DESCRIPTION
    Detects system RAM and recommends optimal service configuration tier.
    Tiers: shadow (<=512MB), lite (<=2GB), standard (<=8GB), full (>8GB).
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$WinVPSDir = if ($env:WINVPS_DIR) { $env:WINVPS_DIR } else { 'C:\WinVPS' }

function Get-RamTier {
    $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction SilentlyContinue
    if (-not $cs) { return 'unknown' }
    $ramMB = [math]::Round($cs.TotalPhysicalMemory / 1MB)
    if ($ramMB -le 512)   { return 'shadow' }
    elseif ($ramMB -le 2048)  { return 'lite' }
    elseif ($ramMB -le 8192)  { return 'standard' }
    else { return 'full' }
}

function Get-TierName {
    param([string]$Tier)
    switch ($Tier) {
        'shadow'   { 'Shadow (512MB ultra-light)' }
        'lite'     { 'Lite (2GB minimal)' }
        'standard' { 'Standard (8GB balanced)' }
        'full'     { 'Full (16GB+ everything)' }
        default    { 'Unknown' }
    }
}

function Select-SshType {
    param([string]$Tier)
    switch ($Tier) {
        { $_ -in 'shadow','lite' } { 'openssh-basic' }
        default                    { 'openssh' }
    }
}

function Select-HttpdType {
    param([string]$Tier)
    switch ($Tier) {
        'shadow'   { 'shell' }
        'lite'     { 'python' }
        'standard' { 'python' }
        'full'     { 'python' }
    }
}

function Select-Monitoring {
    param([string]$Tier)
    switch ($Tier) {
        'shadow'   { 'minimal' }
        'lite'     { 'basic' }
        'standard' { 'standard' }
        'full'     { 'full' }
    }
}

function Get-RecommendedProfile {
    param([string]$Tier)
    switch ($Tier) {
        'shadow'   { 'shadow' }
        'lite'     { 'minimal' }
        'standard' { 'webhost' }
        'full'     { 'full' }
    }
}

function Show-Recommendations {
    $tier = Get-RamTier
    $ramMB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1MB)
    Write-Host ''
    Write-Host '  Lightweight Auto-Detection'
    Write-Host '  ----------------------------------------'
    Write-Host ''
    Write-Host "  Detected RAM:     ${ramMB}MB"
    Write-Host "  RAM Tier:         $(Get-TierName $tier)"
    Write-Host "  Recommended SSH:  $(Select-SshType $tier)"
    Write-Host "  Recommended HTTPD:$(Select-HttpdType $tier)"
    Write-Host "  Recommended Mon:  $(Select-Monitoring $tier)"
    Write-Host "  Profile:          $(Get-RecommendedProfile $tier)"
    Write-Host ''
    Write-Host "  Set with: winvps config set WINVPS_TIER $tier"
    Write-Host ''
}

$action = if ($args.Count -gt 0) { $args[0] } else { 'detect' }
switch ($action) {
    'detect'        { Get-RamTier }
    'tier'          { Get-TierName (Get-RamTier) }
    'recommend'     { Get-RecommendedProfile (Get-RamTier) }
    'info'          { Show-Recommendations }
    'select-ssh'    { Select-SshType (Get-RamTier) }
    'select-httpd'  { Select-HttpdType (Get-RamTier) }
    default         { Write-Host "Usage: lightweight.ps1 {detect|tier|recommend|info|select-ssh|select-httpd}" }
}
