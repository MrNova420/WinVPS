#Requires -Version 5.1
#Requires -RunAsAdministrator
<#
.SYNOPSIS
    WinVPS Installer - Full installation of WinVPS on Windows.
.DESCRIPTION
    Installs all dependencies, deploys files, configures services, and starts WinVPS.
    Must be run as Administrator.
.EXAMPLE
    .\Install-WinVPS.ps1
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$WinVPSVersion = '1.0.0'
$WinVPSDir = 'C:\WinVPS'

$Green = "`e[0;32m"; $Yellow = "`e[1;33m"; $Red = "`e[0;31m"; $Cyan = "`e[0;36m"; $NC = "`e[0m"
function Log($msg)  { Write-Host "${Green}[+]${NC} $msg" }
function Warn($msg) { Write-Host "${Yellow}[!]${NC} $msg" }
function Err($msg)  { Write-Host "${Red}[x]${NC} $msg" }
function Info($msg)  { Write-Host "${Cyan}[i]${NC} $msg" }

function Test-Admin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

if (-not (Test-Admin)) {
    Err 'This installer requires Administrator privileges.'
    Err 'Right-click PowerShell and select "Run as Administrator".'
    exit 1
}

function Detect-Environment {
    Info 'Detecting environment...'
    $os = Get-CimInstance Win32_OperatingSystem
    $cs = Get-CimInstance Win32_ComputerSystem
    $winVer = [System.Environment]::OSVersion.Version
    $arch = if ([Environment]::Is64BitOperatingSystem) { 'amd64' } else { 'x86' }
    $ramMB = [math]::Round($cs.TotalPhysicalMemory / 1MB)

    Log "Windows: $($os.Caption) ($($winVer.Major).$($winVer.Minor))"
    Log "Architecture: $arch"
    Log "RAM: ${ramMB}MB"

    if ($ramMB -le 512) { $script:Tier = 'shadow' }
    elseif ($ramMB -le 2048) { $script:Tier = 'lite' }
    elseif ($ramMB -le 8192) { $script:Tier = 'standard' }
    else { $script:Tier = 'full' }

    Log "Tier: $($script:Tier) ($ramMBMB)"
}

function Install-Dependencies {
    Log 'Installing dependencies...'

    $sshCapability = Get-WindowsCapability -Online | Where-Object { $_.Name -like 'OpenSSH.Server*' }
    if ($sshCapability -and $sshCapability.State -ne 'Installed') {
        Log 'Installing OpenSSH Server...'
        Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0
    }

    if (-not (Get-Service -Name 'sshd' -ErrorAction SilentlyContinue)) {
        Log 'Enabling SSH service...'
        Start-Process powershell -ArgumentList '-Command "Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0; Start-Service sshd; Set-Service -Name sshd -StartupType Automatic"' -Wait -Verb RunAs -ErrorAction SilentlyContinue
    } else {
        Set-Service -Name sshd -StartupType Automatic -ErrorAction SilentlyContinue
        Start-Service sshd -ErrorAction SilentlyContinue
    }
    Log 'OpenSSH Server ready'

    try {
        $pyVer = & python --version 2>&1
        if ($pyVer -match 'Python 3') { Log "Python: $pyVer" }
        else { throw 'not python3' }
    } catch {
        Log 'Python not found - installing via winget...'
        if (Get-Command winget -ErrorAction SilentlyContinue) {
            & winget install Python.Python.3.12 --silent --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
            $env:Path = [System.Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path', 'User')
        } else {
            Warn 'winget not available - install Python 3 manually from python.org'
        }
    }

    Log 'Dependencies installed'
}

function Setup-Directories {
    Log 'Creating directory structure...'
    $dirs = @(
        $WinVPSDir,
        "$WinVPSDir\src",
        "$WinVPSDir\src\cli",
        "$WinVPSDir\src\core",
        "$WinVPSDir\src\web\backend",
        "$WinVPSDir\src\web\frontend",
        "$WinVPSDir\src\bots",
        "$WinVPSDir\src\tunnels",
        "$WinVPSDir\config",
        "$WinVPSDir\config\profiles",
        "$WinVPSDir\config\ssh",
        "$WinVPSDir\data",
        "$WinVPSDir\data\sites\default",
        "$WinVPSDir\data\databases",
        "$WinVPSDir\logs",
        "$WinVPSDir\services",
        "$WinVPSDir\backup",
        "$WinVPSDir\tmp",
        "$WinVPSDir\ssl",
        "$WinVPSDir\tunnels",
        "$WinVPSDir\setup"
    )
    foreach ($d in $dirs) {
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }
    Log 'Directories created'
}

function Deploy-Files {
    Log 'Deploying WinVPS files...'
    $scriptDir = Split-Path -Parent $MyInvocation.ScriptName
    if (-not $scriptDir) { $scriptDir = Split-Path -Parent $PSCommandPath }
    if (-not $scriptDir) { $scriptDir = $PWD.Path }

    $srcRoot = Join-Path $scriptDir '..'
    if (Test-Path (Join-Path $srcRoot 'src')) {
        Copy-Item -Path (Join-Path $srcRoot 'src\*') -Destination "$WinVPSDir\src" -Recurse -Force
        if (Test-Path (Join-Path $srcRoot 'config')) {
            Copy-Item -Path (Join-Path $srcRoot 'config\*') -Destination "$WinVPSDir\config" -Recurse -Force
        }
        if (Test-Path (Join-Path $srcRoot 'setup')) {
            Copy-Item -Path (Join-Path $srcRoot 'setup\*') -Destination "$WinVPSDir\setup" -Recurse -Force
        }
        Log 'Deployed from local source'
    } else {
        Warn 'Running from non-source location - files should already be in place'
    }

    $cliScript = Join-Path $WinVPSDir 'src\cli\winvps.ps1'
    if (Test-Path $cliScript) {
        $cmdContent = "@echo off`r`npowershell.exe -NoProfile -ExecutionPolicy Bypass -File `"%~dp0src\cli\winvps.ps1`" %*"
        $cmdContent | Out-File -FilePath (Join-Path $WinVPSDir 'winvps.cmd') -Encoding ascii -Force
        Log 'Created winvps.cmd launcher'
    }

    $env:WINVPS_DIR = $WinVPSDir
    [System.Environment]::SetEnvironmentVariable('WINVPS_DIR', $WinVPSDir, 'Machine')
    Log 'WINVPS_DIR environment variable set'
}

function Setup-Config {
    Log 'Generating configuration...'
    $confFile = Join-Path $WinVPSDir 'config\winvps.conf'
    if (-not (Test-Path $confFile)) {
        $ramMB = [math]::Round((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1MB)
        $tier = 'full'
        if ($ramMB -le 512) { $tier = 'shadow' }
        elseif ($ramMB -le 2048) { $tier = 'lite' }
        elseif ($ramMB -le 8192) { $tier = 'standard' }

        @"
# WinVPS Configuration - v$WinVPSVersion
WINVPS_VERSION="$WinVPSVersion"
WINVPS_TIER="$tier"
WINVPS_DIR="$WinVPSDir"
WINVPS_HOSTNAME="$env:COMPUTERNAME"
WINVPS_SSH_PORT=7022
WINVPS_WEB_PORT=7080
WINVPS_HTTPS_PORT=7443
WINVPS_FILE_PORT=7444
WINVPS_AUTO_UPDATE=true
WINVPS_AUTO_BACKUP=true
WINVPS_BACKUP_INTERVAL="weekly"
WINVPS_LOG_LEVEL="info"
WINVPS_WATCHDOG=true
WINVPS_TUNNEL_TYPE="cloudflare"
"@ | Out-File -FilePath $confFile -Encoding ascii -Force
    }
    Log 'Configuration ready'
}

function Setup-Firewall {
    $createRules = Read-Host '  Create Windows Firewall rules for WinVPS ports? (y/N)'
    if ($createRules -ne 'y' -and $createRules -ne 'Y') {
        Log 'Skipping firewall rules (you can add them later with: winvps security harden)'
        return
    }
    Log 'Configuring Windows Firewall...'
    $existing = Get-NetFirewallRule -DisplayName 'WinVPS*' -ErrorAction SilentlyContinue
    if ($existing) { $existing | Remove-NetFirewallRule }

    $rules = @(
        @{ Name='WinVPS-SSH-7022'; Port=7022 },
        @{ Name='WinVPS-Web-7080'; Port=7080 },
        @{ Name='WinVPS-HTTPS-7443'; Port=7443 },
        @{ Name='WinVPS-File-7444'; Port=7444 }
    )
    foreach ($rule in $rules) {
        New-NetFirewallRule -DisplayName $rule.Name -Direction Inbound -Action Allow `
            -Protocol TCP -LocalPort $rule.Port -ErrorAction SilentlyContinue | Out-Null
    }
    Log 'Firewall rules created'
}

function Setup-BootTask {
    $createTask = Read-Host '  Register auto-start task on login? (y/N)'
    if ($createTask -ne 'y' -and $createTask -ne 'Y') {
        Log 'Skipping auto-start task (you can start services manually with: winvps service start)'
        return
    }
    Log 'Setting up auto-start via Task Scheduler...'
    $action = New-ScheduledTaskAction -Execute 'powershell.exe' `
        -Argument "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$WinVPSDir\src\core\supervisor.ps1`" start"
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest

    Unregister-ScheduledTask -TaskName 'WinVPS-Supervisor' -Confirm:$false -ErrorAction SilentlyContinue
    Register-ScheduledTask -TaskName 'WinVPS-Supervisor' -Action $action -Trigger $trigger `
        -Settings $settings -Principal $principal -Description 'WinVPS Service Supervisor' -Force | Out-Null
    Log 'Auto-start task registered'
}

function Start-Services {
    Log 'Starting WinVPS services...'
    $supervisor = Join-Path $WinVPSDir 'src\core\supervisor.ps1'
    if (Test-Path $supervisor) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $supervisor start
    }
}

function Print-Summary {
    $tierName = switch ($script:Tier) {
        'shadow'   { 'Shadow (512MB ultra-light)' }
        'lite'     { 'Lite (2GB minimal)' }
        'standard' { 'Standard (8GB balanced)' }
        'full'     { 'Full (16GB+ everything)' }
    }
    Write-Host ''
    Write-Host '============================================'
    Write-Host "  WinVPS v$WinVPSVersion - Installation Complete"
    Write-Host '============================================'
    Write-Host "  Directory:    $WinVPSDir"
    Write-Host "  Tier:         $tierName"
    Write-Host "  SSH Port:     7022"
    Write-Host "  Web UI:       http://localhost:7080"
    Write-Host "  SSH:          ssh -p 7022 $env:USERNAME@localhost"
    Write-Host ''
    Write-Host '  Quick start:'
    Write-Host '    winvps status        View system status'
    Write-Host '    winvps service list  List all services'
    Write-Host '    winvps security harden  Lock it down'
    Write-Host '    winvps tunnel start cloudflare  Public access'
    Write-Host ''
    Write-Host '  Run "winvps help" for all commands'
    Write-Host '============================================'
}

Write-Host ''
Write-Host '  ██╗    ██╗██╗███╗   ██╗██╗'
Write-Host '  ██║    ██║██║████╗  ██║██║'
Write-Host '  ██║ █╗ ██║██║██╔██╗ ██║██║'
Write-Host '  ██║███╗██║██║██║╚██╗██║╚═╝'
Write-Host '  ╚███╔███╔╝██║██║ ╚████║██╗'
Write-Host '   ╚══╝╚══╝ ╚═╝╚═╝  ╚═══╝╚═╝'
Write-Host "  Windows VPS - Auto-Managed Server Platform v$WinVPSVersion"
Write-Host ''

Detect-Environment
Install-Dependencies
Setup-Directories
Deploy-Files
Setup-Config
Setup-Firewall
Setup-BootTask
Start-Services
Print-Summary
