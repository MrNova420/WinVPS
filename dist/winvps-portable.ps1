#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    WinVPS Portable Installer - one-command full install.
.DESCRIPTION
    Downloads WinVPS from GitHub and runs the installer in one step.
    Run as Administrator: irm https://raw.githubusercontent.com/WinVPS/WinVPS/main/dist/winvps-portable.ps1 | iex
    Or save and run locally: .\winvps-portable.ps1
#>
param(
    [string]$Branch = 'main'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoUrl = "https://github.com/WinVPS/WinVPS/archive/refs/heads/$Branch.zip"
$WinVPSDir = 'C:\WinVPS'
$TmpDir = "$env:TEMP\winvps-install-$(Get-Random)"

# Detect VT100/ANSI support — fall back to plain text on legacy terminals
$script:UseAnsi = $false
try { $script:UseAnsi = [bool]$Host.UI.SupportsVirtualTerminal } catch {}
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

if ($script:UseAnsi) {
    $Green = "`e[0;32m"; $Yellow = "`e[1;33m"; $Red = "`e[0;31m"; $NC = "`e[0m"
} else {
    $Green = ''; $Yellow = ''; $Red = ''; $NC = ''
}
function Log($m)  { Write-Host "${Green}[+]${NC} $m" }
function Warn($m) { Write-Host "${Yellow}[!]${NC} $m" }
function Err($m)  { Write-Host "${Red}[x]${NC} $m" }

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    Err 'This installer requires Administrator privileges.'
    Err 'Run: Start-Process powershell -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$PSCommandPath`""'
    exit 1
}

Write-Host ''
Write-Host '  WinVPS Portable Installer' -ForegroundColor Cyan
Write-Host '  ========================================'
Write-Host ''

# Check if already installed
if (Test-Path "$WinVPSDir\src\cli\winvps.ps1") {
    Warn "WinVPS already installed at $WinVPSDir"
    $reinstall = Read-Host "  Reinstall? (y/N)"
    if ($reinstall -ne 'y') { Write-Host '  Cancelled.'; return }
    Log 'Reinstalling...'
}

# Download
Log "Downloading WinVPS ($Branch)..."
if (-not (Test-Path $TmpDir)) { New-Item -ItemType Directory -Path $TmpDir -Force | Out-Null }
$zipPath = Join-Path $TmpDir 'winvps.zip'

try {
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Invoke-WebRequest -Uri $RepoUrl -OutFile $zipPath -UseBasicParsing -TimeoutSec 60
} catch {
    Err "Download failed: $_"
    Err "Check your internet connection or try: git clone https://github.com/WinVPS/WinVPS.git $WinVPSDir"
    exit 1
}

# Extract
Log 'Extracting...'
Expand-Archive -Path $zipPath -DestinationPath $TmpDir -Force
$extractedDir = Get-ChildItem -Path $TmpDir -Directory | Where-Object { $_.Name -like 'WinVPS-*' } | Select-Object -First 1
if (-not $extractedDir) { Err 'Extraction failed'; exit 1 }

# Deploy
Log "Deploying to $WinVPSDir..."
if (-not (Test-Path $WinVPSDir)) { New-Item -ItemType Directory -Path $WinVPSDir -Force | Out-Null }
Copy-Item -Path "$($extractedDir.FullName)\*" -Destination $WinVPSDir -Recurse -Force

# Run installer
Log 'Running full installer...'
$installer = Join-Path $WinVPSDir 'setup\Install-WinVPS.ps1'
if (Test-Path $installer) {
    & powershell -NoProfile -ExecutionPolicy Bypass -File $installer
} else {
    Err 'Installer not found - files may not have extracted correctly'
    exit 1
}

# Cleanup
Log 'Cleaning up...'
Remove-Item $TmpDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host ''
Log 'Portable install complete!'
Write-Host ''
