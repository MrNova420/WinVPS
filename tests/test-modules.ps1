# WinVPS Module Tests
# Verifies each core module loads without syntax errors

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

$WinVPSDir = $env:WINVPS_DIR; if (-not $WinVPSDir) { $WinVPSDir = 'C:\WinVPS' }

$script:Passed = 0
$script:Failed = 0

function Assert($cond, $msg) {
    if ($cond) { $script:Passed++; Write-Host "  PASS: $msg" -ForegroundColor Green }
    else { $script:Failed++; Write-Host "  FAIL: $msg" -ForegroundColor Red }
}

Write-Host ''
Write-Host '  WinVPS Module Load Tests' -ForegroundColor Cyan
Write-Host '  ========================='
Write-Host ''

$coreModules = @(
    'supervisor', 'healthcheck', 'ssh', 'httpd', 'security',
    'fail2ban', 'stealth', 'obfuscate', 'tamper', 'wipe',
    'vpn-killswitch', 'encrypt', 'tor', 'storage', 'autoupdate', 'lightweight'
)

foreach ($mod in $coreModules) {
    $scriptPath = Join-Path $WinVPSDir "src\core\$mod.ps1"
    if (Test-Path $scriptPath) {
        try {
            $tokens = $null; $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$errors)
            Assert ($errors.Count -eq 0) "$mod.ps1 parses without errors"
        } catch {
            Assert $false "$mod.ps1 parses without errors: $_"
        }
    } else {
        Assert $false "$mod.ps1 exists"
    }
}

# Parse CLI
$cliPath = Join-Path $WinVPSDir 'src\cli\winvps.ps1'
if (Test-Path $cliPath) {
    try {
        $tokens = $null; $errors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($cliPath, [ref]$tokens, [ref]$errors)
        Assert ($errors.Count -eq 0) "winvps.ps1 (CLI) parses without errors"
    } catch {
        Assert $false "winvps.ps1 (CLI) parses without errors: $_"
    }
}

# Parse bots
foreach ($bot in @('shell-telegram.ps1', 'shell-discord.ps1')) {
    $botPath = Join-Path $WinVPSDir "src\bots\$bot"
    if (Test-Path $botPath) {
        try {
            $tokens = $null; $errors = $null
            [System.Management.Automation.Language.Parser]::ParseFile($botPath, [ref]$tokens, [ref]$errors)
            Assert ($errors.Count -eq 0) "$bot parses without errors"
        } catch {
            Assert $false "$bot parses without errors: $_"
        }
    } else {
        Assert $false "$bot exists"
    }
}

Write-Host ''
Write-Host "  Results: $script:Passed passed, $script:Failed failed" -ForegroundColor $(if ($script:Failed -eq 0) { 'Green' } else { 'Red' })
Write-Host ''

if ($script:Failed -gt 0) { exit 1 }
