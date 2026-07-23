#Requires -Version 5.1
<#
.SYNOPSIS
    WinVPS service module installer - installs and enables a specific optional service.
.DESCRIPTION
    Registers a service module with WinVPS so it appears in 'winvps service list'.
    Creates a PID file, status file, and start/stop scripts under services/.
.PARAMETER Service
    The service module name.
.EXAMPLE
    .\service-installer.ps1 nginx
#>
param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$Service,
    [Parameter(Position=1)]
    [ValidateSet('install','uninstall','enable','disable')]
    [string]$Action = 'install'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$WinVPSDir = $env:WINVPS_DIR; if (-not $WinVPSDir) { $WinVPSDir = 'C:\WinVPS' }
$ServicesDir = Join-Path $WinVPSDir 'services'
$ServiceDir = Join-Path $ServicesDir $Service
$ServiceConf = Join-Path $ServiceDir 'config.ini'
$ServiceLog = Join-Path $ServiceDir "$Service.log"

function Ensure-Dirs {
    if (-not (Test-Path $ServicesDir)) { New-Item -ItemType Directory -Path $ServicesDir -Force | Out-Null }
    if (-not (Test-Path $ServiceDir)) { New-Item -ItemType Directory -Path $ServiceDir -Force | Out-Null }
}

function Install-Service {
    Ensure-Dirs
    $svc = Get-Content $ServiceConf -ErrorAction SilentlyContinue | Where-Object { $_ -match '^service:' }
    $port = Get-Content $ServiceConf -ErrorAction SilentlyContinue | Where-Object { $_ -match '^port:' }

    "# WinVPS Service: $Service`n# Installed: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" |
        Out-File -FilePath (Join-Path $ServiceDir 'status') -Encoding ascii -Force

    "disabled" | Out-File -FilePath (Join-Path $ServiceDir '.disabled') -Encoding ascii -Force

    $installScript = Join-Path $WinVPSDir "src\modules\$Service\install.ps1"
    if (Test-Path $installScript) {
        Write-Host "[+] Running $Service installer..."
        & powershell -NoProfile -ExecutionPolicy Bypass -File $installScript
    }

    Remove-Item (Join-Path $ServiceDir '.disabled') -Force -ErrorAction SilentlyContinue
    Write-Host "[+] Service '$Service' installed"
}

function Uninstall-Service {
    $disableScript = Join-Path $WinVPSDir "src\modules\$Service\disable.ps1"
    if (Test-Path $disableScript) { & powershell -NoProfile -ExecutionPolicy Bypass -File $disableScript }
    $pidFile = Join-Path $ServiceDir "$Service.pid"
    if (Test-Path $pidFile) {
        $pid = Get-Content $pidFile -ErrorAction SilentlyContinue
        if ($pid) { Stop-Process -Id ([int]$pid) -Force -ErrorAction SilentlyContinue }
    }
    if (Test-Path $ServiceDir) { Remove-Item $ServiceDir -Recurse -Force }
    Write-Host "[+] Service '$Service' removed"
}

function Enable-Service {
    $disabled = Join-Path $ServiceDir '.disabled'
    if (Test-Path $disabled) { Remove-Item $disabled -Force }
    $startScript = Join-Path $WinVPSDir "src\modules\$Service\start.ps1"
    if (Test-Path $startScript) { & powershell -NoProfile -ExecutionPolicy Bypass -File $startScript }
    Write-Host "[+] Service '$Service' enabled"
}

function Disable-Service {
    $stopScript = Join-Path $WinVPSDir "src\modules\$Service\disable.ps1"
    if (Test-Path $stopScript) { & powershell -NoProfile -ExecutionPolicy Bypass -File $stopScript }
    if (-not (Test-Path (Join-Path $ServiceDir '.disabled'))) {
        New-Item -ItemType File -Path (Join-Path $ServiceDir '.disabled') -Force | Out-Null
    }
    Write-Host "[+] Service '$Service' disabled"
}

switch ($Action) {
    'install'   { Install-Service }
    'uninstall' { Uninstall-Service }
    'enable'    { Enable-Service }
    'disable'   { Disable-Service }
}
