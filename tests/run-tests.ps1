#Requires -Version 5.1
<#
.SYNOPSIS
    WinVPS test suite - verifies all core modules.
.DESCRIPTION
    Runs unit tests for each core module.
    Use: .\run-tests.ps1
    Exit 0 = all pass, Exit 1 = failures.
#>
Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

$WinVPSDir = $env:WINVPS_DIR; if (-not $WinVPSDir) { $WinVPSDir = 'C:\WinVPS' }
$ScriptDir = Split-Path -Parent $MyInvocation.ScriptName
if (-not $ScriptDir) { $ScriptDir = Split-Path -Parent $PSCommandPath }

$script:Passed = 0
$script:Failed = 0
$script:Errors = @()

function Assert($cond, $msg) {
    if ($cond) { $script:Passed++; Write-Host "  PASS: $msg" -ForegroundColor Green }
    else { $script:Failed++; $script:Errors += $msg; Write-Host "  FAIL: $msg" -ForegroundColor Red }
}

function Assert-File($path, $desc) {
    Assert (Test-Path $path) "$desc exists at $path"
}

function Assert-Command($cmd, $desc) {
    $r = & $cmd 2>&1
    Assert ($LASTEXITCODE -eq 0 -or $null -eq $LASTEXITCODE) "$desc runs without error"
}

# --- File existence tests ---
Write-Host ''
Write-Host '  WinVPS Test Suite' -ForegroundColor Cyan
Write-Host '  ================='
Write-Host ''
Write-Host '  File Structure Tests' -ForegroundColor Yellow

Assert-File "$WinVPSDir\src\cli\winvps.ps1"            "Main CLI"
Assert-File "$WinVPSDir\src\core\supervisor.ps1"        "Supervisor module"
Assert-File "$WinVPSDir\src\core\healthcheck.ps1"       "Healthcheck module"
Assert-File "$WinVPSDir\src\core\ssh.ps1"                "SSH module"
Assert-File "$WinVPSDir\src\core\httpd.ps1"              "HTTP module"
Assert-File "$WinVPSDir\src\core\security.ps1"           "Security module"
Assert-File "$WinVPSDir\src\core\fail2ban.ps1"           "Fail2ban module"
Assert-File "$WinVPSDir\src\core\stealth.ps1"            "Stealth module"
Assert-File "$WinVPSDir\src\core\obfuscate.ps1"          "Obfuscation module"
Assert-File "$WinVPSDir\src\core\tamper.ps1"             "Tamper detection module"
Assert-File "$WinVPSDir\src\core\wipe.ps1"               "Wipe module"
Assert-File "$WinVPSDir\src\core\vpn-killswitch.ps1"     "VPN kill switch module"
Assert-File "$WinVPSDir\src\core\encrypt.ps1"            "Encryption module"
Assert-File "$WinVPSDir\src\core\tor.ps1"                "Tor module"
Assert-File "$WinVPSDir\src\core\storage.ps1"            "Storage module"
Assert-File "$WinVPSDir\src\core\autoupdate.ps1"         "Autoupdate module"
Assert-File "$WinVPSDir\src\core\lightweight.ps1"        "Lightweight module"
Assert-File "$WinVPSDir\src\web\backend\main.py"         "Web backend"
Assert-File "$WinVPSDir\src\web\frontend\index.html"     "Web frontend"
Assert-File "$WinVPSDir\src\bots\shell-telegram.ps1"     "Telegram bot"
Assert-File "$WinVPSDir\src\bots\shell-discord.ps1"      "Discord bot"
Assert-File "$WinVPSDir\src\tunnels\tunnel-manager.ps1"  "Tunnel manager"
Assert-File "$WinVPSDir\config\winvps.conf"              "Main config"
Assert-File "$WinVPSDir\config\winvps-tunnels.json"      "Tunnel config"
Assert-File "$WinVPSDir\config\profiles\minimal.conf"    "Minimal profile"
Assert-File "$WinVPSDir\config\profiles\dev.conf"        "Dev profile"
Assert-File "$WinVPSDir\config\profiles\full.conf"       "Full profile"
Assert-File "$WinVPSDir\config\profiles\stealth.conf"    "Stealth profile"
Assert-File "$WinVPSDir\config\profiles\ghost.conf"      "Ghost profile"
Assert-File "$WinVPSDir\config\profiles\hardened.conf"   "Hardened profile"
Assert-File "$WinVPSDir\config\profiles\shadow.conf"     "Shadow profile"
Assert-File "$WinVPSDir\config\profiles\lite.conf"       "Lite profile"
Assert-File "$WinVPSDir\config\profiles\webhost.conf"    "Webhost profile"
Assert-File "$WinVPSDir\setup\Install-WinVPS.ps1"        "Installer"
Assert-File "$WinVPSDir\setup\Uninstall-WinVPS.ps1"      "Uninstaller"
Assert-File "$WinVPSDir\setup\modules\service-installer.ps1"  "Service installer"
Assert-File "$WinVPSDir\setup\modules\register-services.ps1"  "Service registration"
Assert-File "$WinVPSDir\dist\winvps-portable.ps1"        "Portable installer"
Assert-File "$WinVPSDir\tasks\winvps-boot.xml"           "Task Scheduler XML"
Assert-File "$WinVPSDir\README.md"                       "README"
Assert-File "$WinVPSDir\LICENSE"                         "LICENSE"
Assert-File "$WinVPSDir\CHANGELOG.md"                    "CHANGELOG"
Assert-File "$WinVPSDir\SECURITY.md"                     "SECURITY"
Assert-File "$WinVPSDir\.gitignore"                      ".gitignore"

# --- Config content tests ---
Write-Host ''
Write-Host '  Config Content Tests' -ForegroundColor Yellow

$conf = Get-Content "$WinVPSDir\config\winvps.conf" -Raw
Assert ($conf -match 'WINVPS_SSH_PORT=') "Config has SSH port"
Assert ($conf -match 'WINVPS_WEB_PORT=') "Config has web port"
Assert ($conf -match 'WINVPS_AUTO_UPDATE=') "Config has auto update"
Assert ($conf -match 'WINVPS_WATCHDOG=') "Config has watchdog"

# --- Profile tests ---
Write-Host ''
Write-Host '  Profile Tests' -ForegroundColor Yellow

$profiles = @('minimal','dev','full','stealth','ghost','hardened','shadow','lite','webhost')
foreach ($p in $profiles) {
    $pc = Get-Content "$WinVPSDir\config\profiles\$p.conf" -Raw -ErrorAction SilentlyContinue
    Assert ($pc -and $pc.Length -gt 10) "Profile '$p' is valid"
}

# --- CLI help test ---
Write-Host ''
Write-Host '  CLI Tests' -ForegroundColor Yellow

$cliOut = & powershell -NoProfile -ExecutionPolicy Bypass -File "$WinVPSDir\src\cli\winvps.ps1" version 2>&1
Assert ($cliOut -match 'WinVPS') "CLI version command works"

$helpOut = & powershell -NoProfile -ExecutionPolicy Bypass -File "$WinVPSDir\src\cli\winvps.ps1" help 2>&1
Assert ($helpOut -match 'winvps') "CLI help command works"

# --- Web backend syntax test ---
Write-Host ''
Write-Host '  Web Backend Tests' -ForegroundColor Yellow

try {
    $pyOut = & python -c "import py_compile; py_compile.compile(r'$WinVPSDir\src\web\backend\main.py', doraise=True)" 2>&1
    Assert ($LASTEXITCODE -eq 0) "Python backend compiles without syntax errors"
} catch {
    Assert $false "Python backend compiles without syntax errors"
}

# --- Summary ---
Write-Host ''
Write-Host '  ================='
Write-Host "  Results: $script:Passed passed, $script:Failed failed" -ForegroundColor $(if ($script:Failed -eq 0) { 'Green' } else { 'Red' })
if ($script:Failed -gt 0) {
    Write-Host ''
    Write-Host '  Failed tests:' -ForegroundColor Red
    $script:Errors | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
}
Write-Host ''

if ($script:Failed -gt 0) { exit 1 }
