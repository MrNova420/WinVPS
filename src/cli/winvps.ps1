#Requires -Version 5.1
<#
.SYNOPSIS
    WinVPS - Windows Virtual Private Server Management CLI.
.DESCRIPTION
    Main entry point for managing WinVPS services, security, tunnels, and configuration.
.EXAMPLE
    winvps status
    winvps service list
    winvps security harden
#>
param(
    [Parameter(Position=0)]
    [string]$Command = '',

    [Parameter(Position=1, ValueFromRemainingArguments)]
    [string[]]$CmdArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

$WinVPSVersion = '1.0.0'
$WinVPSDir = $env:WINVPS_DIR; if (-not $WinVPSDir) { $WinVPSDir = 'C:\WinVPS' }
$SrcDir = Join-Path $WinVPSDir 'src'
$CoreDir = Join-Path $SrcDir 'core'
$ConfigDir = Join-Path $WinVPSDir 'config'
$ConfigFile = Join-Path $ConfigDir 'winvps.conf'
$ServicesDir = Join-Path $WinVPSDir 'services'
$LogDir = Join-Path $WinVPSDir 'logs'
$BackupDir = Join-Path $WinVPSDir 'backup'

$Green = "`e[0;32m"; $Yellow = "`e[1;33m"; $Red = "`e[0;31m"; $Cyan = "`e[0;36m"; $Bold = "`e[1m"; $NC = "`e[0m"
function Log($msg)  { Write-Host "${Green}[-]${NC} $msg" }
function Warn($msg) { Write-Host "${Yellow}[!]${NC} $msg" }
function Err($msg)  { Write-Host "${Red}[x]${NC} $msg" }
function Info($msg)  { Write-Host "${Cyan}[i]${NC} $msg" }

function Ensure-Dirs {
    $dirs = @(
        $ConfigDir
        Join-Path $WinVPSDir 'data'
        $LogDir
        $ServicesDir
        $BackupDir
        Join-Path $WinVPSDir 'tmp'
        Join-Path $WinVPSDir 'ssl'
        Join-Path $WinVPSDir 'tunnels'
        Join-Path $ConfigDir 'profiles'
    )
    foreach ($d in $dirs) {
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }
}

function Load-Config {
    $script:Config = @{}
    if (Test-Path $ConfigFile) {
        Get-Content $ConfigFile | Where-Object { $_ -match '^\w+=' } | ForEach-Object {
            $key, $val = $_ -split '=', 2
            $script:Config[$key.Trim()] = $val.Trim('"').Trim("'")
        }
    }
    $script:SSHPort = if ($script:Config['WINVPS_SSH_PORT']) { [int]$script:Config['WINVPS_SSH_PORT'] } else { 7022 }
    $script:WebPort = if ($script:Config['WINVPS_WEB_PORT']) { [int]$script:Config['WINVPS_WEB_PORT'] } else { 7080 }
}

# --- STATUS ---
function Show-Status {
    Load-Config
    Write-Host ''
    Write-Host "  WinVPS v$WinVPSVersion - System Status"
    Write-Host '  ----------------------------------------'
    Write-Host ''

    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    Write-Host '  SYSTEM'
    if ($os) {
        $uptime = (Get-Date) - $os.LastBootUpTime
        Write-Host "  Uptime:    $([math]::Floor($uptime.TotalHours))h $($uptime.Minutes)m"
    }
    if ($cs) {
        $totalMB = [math]::Round($cs.TotalPhysicalMemory / 1MB)
        $freeMB = [math]::Round($os.FreePhysicalMemory / 1024)
        Write-Host "  Memory:    $([math]::Round(($totalMB - $freeMB) / $totalMB * 100))% ($($totalMB - $freeMB)MB/${totalMB}MB)"
    }
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue
    if ($cpu) { Write-Host "  CPU:       $($cpu.LoadPercentage)% ($($cpu.NumberOfCores) cores)" }

    Write-Host ''
    Write-Host '  SERVICES'
    $running = 0
    Get-ChildItem -Path $ServicesDir -Filter '*.pid' -ErrorAction SilentlyContinue | ForEach-Object {
        $name = $_.BaseName
        $pid = [int](Get-Content $_.FullName -ErrorAction SilentlyContinue)
        $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
        if ($proc) {
            $mem = [math]::Round($proc.WorkingSet64 / 1MB, 1)
            Write-Host "  ${name}: running (PID $pid, ${mem}MB)"
            $running++
        } else {
            Write-Host "  ${name}: stopped" -ForegroundColor DarkGray
        }
    }
    if ($running -eq 0) { Write-Host '  (no services running)' -ForegroundColor DarkGray }

    Write-Host ''
    Write-Host '  NETWORK'
    $sshListening = Get-NetTCPConnection -LocalPort $script:SSHPort -State Listen -ErrorAction SilentlyContinue
    $webListening = Get-NetTCPConnection -LocalPort $script:WebPort -State Listen -ErrorAction SilentlyContinue
    Write-Host "  SSH:       port $($script:SSHPort) ($(if ($sshListening) { 'active' } else { 'inactive' }))"
    Write-Host "  Web:       port $($script:WebPort) ($(if ($webListening) { 'active' } else { 'inactive' }))"

    Write-Host ''
    Write-Host '  SECURITY'
    Write-Host "  Stealth:   $(if (Test-Path (Join-Path $ConfigDir '.stealth_enabled')) { 'ACTIVE' } else { 'inactive' })"
    Write-Host "  Obfuscate: $(if (Test-Path (Join-Path $ConfigDir '.obfuscated')) { 'ACTIVE' } else { 'inactive' })"
    Write-Host ''
}

# --- SERVICE ---
function Invoke-Service {
    param([string]$Action, [string]$Name = '')
    Load-Config
    switch ($Action) {
        'list' {
            Write-Host '  Available services:'
            Write-Host "    ssh        - OpenSSH server (port $($script:SSHPort))"
            Write-Host "    web        - Web dashboard (port $($script:WebPort))"
            Write-Host "    fail2ban   - Brute-force protection"
            Write-Host "    code-server - VS Code in browser"
            Write-Host "    files      - File server"
            Write-Host "    tunnel     - Public tunnels"
            Write-Host "    tor        - Tor gateway"
            Write-Host "    vpn        - WireGuard VPN"
            Write-Host ''
            Write-Host '  Running:'
            $any = $false
            Get-ChildItem -Path $ServicesDir -Filter '*.pid' -ErrorAction SilentlyContinue | ForEach-Object {
                $pid = [int](Get-Content $_.FullName -ErrorAction SilentlyContinue)
                if ($pid -and (Get-Process -Id $pid -ErrorAction SilentlyContinue)) {
                    Write-Host "    * $($_.BaseName) (PID $pid)"
                    $any = $true
                }
            }
            if (-not $any) { Write-Host '    (none)' -ForegroundColor DarkGray }
        }
        'start' {
            $script = Join-Path $CoreDir "$Name.ps1"
            if (Test-Path $script) {
                & powershell -NoProfile -ExecutionPolicy Bypass -File $script start
            } else { Warn "No script for $Name" }
        }
        'stop' {
            $pf = Join-Path $ServicesDir "$Name.pid"
            if (Test-Path $pf) {
                $pid = [int](Get-Content $pf)
                Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue
                Remove-Item $pf -Force
                Log "$Name stopped"
            } else { Warn "$Name not running" }
        }
        'restart' {
            Invoke-Service -Action stop -Name $Name
            Start-Sleep -Seconds 2
            Invoke-Service -Action start -Name $Name
        }
        'setup' {
            Log 'Running initial service setup...'
            foreach ($svc in @('ssh', 'web', 'fail2ban')) {
                $script = Join-Path $CoreDir "$svc.ps1"
                if (Test-Path $script) {
                    & powershell -NoProfile -ExecutionPolicy Bypass -File $script start 2>&1 | Out-Null
                }
            }
            Log 'Initial setup complete'
        }
        default { Write-Host 'Usage: winvps service {list|install|start|stop|restart|setup} [name]' }
    }
}

# --- MONITOR ---
function Show-Monitor {
    $delay = if ($Args.Count -gt 0) { [int]$Args[0] } else { 3 }
    while ($true) {
        Clear-Host
        Write-Host "  WinVPS Monitor - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        Write-Host '  ----------------------------------------'
        Write-Host ''
        $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue
        if ($cpu) { Write-Host "  CPU:    $($cpu.LoadPercentage)%" }
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($os) {
            $totalMB = [math]::Round($os.TotalPhysicalMemory / 1MB)
            $freeMB = [math]::Round($os.FreePhysicalMemory / 1024)
            Write-Host "  Memory: $([math]::Round(($totalMB - $freeMB) / $totalMB * 100))% ($($totalMB - $freeMB)MB/${totalMB}MB)"
        }
        Write-Host ''
        Write-Host '  Services:'
        Get-ChildItem -Path $ServicesDir -Filter '*.pid' -ErrorAction SilentlyContinue | ForEach-Object {
            $pid = [int](Get-Content $_.FullName -ErrorAction SilentlyContinue)
            $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
            if ($proc) {
                $mem = [math]::Round($proc.WorkingSet64 / 1MB, 1)
                Write-Host "    * $($_.BaseName) (PID $pid, ${mem}MB)"
            }
        }
        Write-Host ''
        Start-Sleep -Seconds $delay
    }
}

# --- BACKUP ---
function Invoke-Backup {
    param([string]$Action = 'create')
    switch ($Action) {
        'create' {
            $ts = Get-Date -Format 'yyyyMMdd_HHmmss'
            $file = Join-Path $BackupDir "winvps_backup_$ts.zip"
            Compress-Archive -Path (Join-Path $WinVPSDir 'config'), (Join-Path $WinVPSDir 'data') `
                -DestinationPath $file -Force -ErrorAction SilentlyContinue
            $size = [math]::Round((Get-Item $file).Length / 1MB, 2)
            Log "Backup created: $file ($size MB)"
        }
        'list' {
            Get-ChildItem -Path $BackupDir -Filter '*.zip' -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending |
                ForEach-Object { Write-Host "  $($_.Name) ($([math]::Round($_.Length/1MB,2)) MB)" }
        }
        'restore' {
            $latest = Get-ChildItem -Path $BackupDir -Filter '*.zip' -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($latest) {
                Expand-Archive -Path $latest.FullName -DestinationPath $WinVPSDir -Force
                Log "Restored from $($latest.Name)"
            } else { Warn 'No backups found' }
        }
        default { Write-Host 'Usage: winvps backup {create|list|restore}' }
    }
}

# --- CONFIG ---
function Invoke-Config {
    param([string]$Action = 'show', [string]$Key = '', [string]$Value = '')
    switch ($Action) {
        'show' { if (Test-Path $ConfigFile) { Get-Content $ConfigFile } else { Write-Host 'No config found' } }
        'get'  {
            if (-not $Key) { Err 'Specify key'; return }
            $line = Get-Content $ConfigFile | Where-Object { $_ -match "^$Key=" }
            if ($line) { ($line -split '=',2)[1].Trim('"') }
        }
        'set'  {
            if (-not $Key -or -not $Value) { Err 'Usage: winvps config set KEY VALUE'; return }
            if (Test-Path $ConfigFile) {
                $content = Get-Content $ConfigFile -Raw
                if ($content -match "^$Key=") {
                    $content = $content -replace "(?m)^$Key=.*", "$Key=`"$Value`""
                } else {
                    $content += "`n$Key=`"$Value`""
                }
                $content | Out-File -FilePath $ConfigFile -Encoding ascii -Force
            } else {
                "$Key=`"$Value`"" | Out-File -FilePath $ConfigFile -Encoding ascii -Force
            }
            Log "$Key=$Value"
        }
        'load' {
            $profile = if ($Args.Count -gt 0) { $Args[0] } else { 'full' }
            $pf = Join-Path $ConfigDir "profiles\$profile.conf"
            if (Test-Path $pf) {
                Copy-Item $pf $ConfigFile -Force
                Log "Loaded profile: $profile"
            } else { Err "Profile not found: $profile" }
        }
        default { Write-Host 'Usage: winvps config {show|get|set|load} [key] [value]' }
    }
}

# --- LOGS ---
function Show-Logs {
    param([string]$Service = '', [int]$Lines = 50)
    if ($Service) {
        $logFile = Join-Path $LogDir "$Service.log"
        if (Test-Path $logFile) {
            Get-Content $logFile -Tail $Lines
        } else { Err "No logs for '$Service'" }
    } else {
        Write-Host '  Available logs:'
        Get-ChildItem -Path $LogDir -Filter '*.log' -ErrorAction SilentlyContinue |
            ForEach-Object { Write-Host "  $($_.Name) ($([math]::Round($_.Length/1KB))KB)" }
    }
}

# --- TUNNEL ---
function Invoke-Tunnel {
    $script = Join-Path $SrcDir 'tunnels\tunnel-manager.ps1'
    if (Test-Path $script) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $script @Args
    } else { Err 'Tunnel manager not installed' }
}

# --- SECURITY ---
function Invoke-SecurityCmd {
    param([string]$Action = 'status')
    $script = Join-Path $CoreDir 'security.ps1'
    if (Test-Path $script) { & powershell -NoProfile -ExecutionPolicy Bypass -File $script $Action }
}

function Invoke-StealthCmd {
    param([string]$Action = 'status')
    $script = Join-Path $CoreDir 'stealth.ps1'
    if (Test-Path $script) { & powershell -NoProfile -ExecutionPolicy Bypass -File $script $Action @Args }
}

function Invoke-ObfuscateCmd {
    param([string]$Action = 'status')
    $script = Join-Path $CoreDir 'obfuscate.ps1'
    if (Test-Path $script) { & powershell -NoProfile -ExecutionPolicy Bypass -File $script $Action }
}

function Invoke-EncryptCmd {
    param([string]$Action = 'status')
    $script = Join-Path $CoreDir 'encrypt.ps1'
    if (Test-Path $script) { & powershell -NoProfile -ExecutionPolicy Bypass -File $script $Action }
}

function Invoke-TorCmd {
    param([string]$Action = 'status')
    $script = Join-Path $CoreDir 'tor.ps1'
    if (Test-Path $script) { & powershell -NoProfile -ExecutionPolicy Bypass -File $script $Action }
}

function Invoke-TamperCmd {
    param([string]$Action = 'status')
    $script = Join-Path $CoreDir 'tamper.ps1'
    if (Test-Path $script) { & powershell -NoProfile -ExecutionPolicy Bypass -File $script $Action }
}

function Invoke-KillswitchCmd {
    param([string]$Action = 'status')
    $script = Join-Path $CoreDir 'vpn-killswitch.ps1'
    if (Test-Path $script) { & powershell -NoProfile -ExecutionPolicy Bypass -File $script $Action }
}

function Invoke-Fail2banCmd {
    param([string]$Action = 'status')
    $script = Join-Path $CoreDir 'fail2ban.ps1'
    if (Test-Path $script) { & powershell -NoProfile -ExecutionPolicy Bypass -File $script $Action }
}

function Invoke-TierCmd {
    param([string]$Action = 'info')
    $script = Join-Path $CoreDir 'lightweight.ps1'
    if (Test-Path $script) { & powershell -NoProfile -ExecutionPolicy Bypass -File $script $Action }
}

# --- DOCTOR ---
function Show-Doctor {
    Write-Host '  WinVPS Diagnostic'
    Write-Host '  ----------------------------------------'
    Write-Host ''
    $checks = 0; $passed = 0
    function Check($desc, $result) {
        $script:checks++
        if ($result) { Write-Host "  [PASS] $desc"; $script:passed++ }
        else { Write-Host "  [FAIL] $desc" }
    }
    Check 'WinVPS directory' (Test-Path $WinVPSDir)
    Check 'Config file' (Test-Path $ConfigFile)
    Check 'PowerShell' ($PSVersionTable.PSVersion.Major -ge 5)
    Check 'OpenSSH' ((Get-Service -Name 'sshd' -ErrorAction SilentlyContinue) -ne $null)
    Get-ChildItem -Path $ServicesDir -Filter '*.pid' -ErrorAction SilentlyContinue | ForEach-Object {
        $pid = [int](Get-Content $_.FullName -ErrorAction SilentlyContinue)
        Check "$($_.BaseName) running" ((Get-Process -Id $pid -ErrorAction SilentlyContinue) -ne $null)
    }
    Write-Host ''
    Write-Host "  Results: $passed/$checks"
}

# --- HELP ---
function Show-Help {
    Write-Host "  WinVPS v$WinVPSVersion - Windows VPS Management"
    Write-Host ''
    Write-Host '  Usage: winvps <command> [options]'
    Write-Host ''
    Write-Host '  Core:'
    Write-Host '    status              Show system status'
    Write-Host '    service             Manage services (list|start|stop|restart|setup)'
    Write-Host '    monitor [interval]  Live resource monitor'
    Write-Host '    backup              Backup management (create|list|restore)'
    Write-Host '    logs [service] [n]  View logs'
    Write-Host '    doctor              Run diagnostics'
    Write-Host ''
    Write-Host '  Networking:'
    Write-Host '    tunnel              Tunnel management (start|stop|status)'
    Write-Host '    tor                 Tor gateway (start|stop|status|install)'
    Write-Host '    killswitch          VPN kill switch (enable|disable|status|test)'
    Write-Host ''
    Write-Host '  Security:'
    Write-Host '    security            Security tools (status|scan|harden)'
    Write-Host '    stealth             Stealth mode (enable|disable|status)'
    Write-Host '    obfuscate           Device obfuscation (all|hostname|ssh|mac|http|status)'
    Write-Host '    encrypt             Encrypted storage (init|unmount|status)'
    Write-Host '    tamper              Tamper detection (init|verify|check|status)'
    Write-Host '    fail2ban            Brute-force protection (start|stop|status)'
    Write-Host ''
    Write-Host '  Config:'
    Write-Host '    config              Configuration (show|get|set|load)'
    Write-Host '    tier                RAM tier detection (detect|info)'
    Write-Host '    uninstall           Remove WinVPS'
    Write-Host '    help                This help'
    Write-Host '    version             Show version'
}

# --- UNINSTALL ---
function Invoke-Uninstall {
    $uninstaller = Join-Path $WinVPSDir 'setup\Uninstall-WinVPS.ps1'
    if (Test-Path $uninstaller) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $uninstaller
    } else { Warn 'Uninstaller not found - remove C:\WinVPS manually' }
}

# --- MAIN ---
Ensure-Dirs

switch ($Command) {
    'status'     { Show-Status }
    'service'    { Invoke-Service -Action ($CmdArgs | Select-Object -First 1) -Name ($CmdArgs | Select-Object -Skip 1 | Select-Object -First 1) }
    'monitor'    { Show-Monitor @CmdArgs }
    'backup'     { Invoke-Backup -Action ($CmdArgs | Select-Object -First 1) }
    'config'     { Invoke-Config -Action ($CmdArgs | Select-Object -First 1) -Key ($CmdArgs | Select-Object -Skip 1 | Select-Object -First 1) -Value ($CmdArgs | Select-Object -Skip 2 | Select-Object -First 1) }
    'logs'       { Show-Logs -Service ($CmdArgs | Select-Object -First 1) -Lines (if ($CmdArgs.Count -gt 1) { [int]$CmdArgs[1] } else { 50 }) }
    'doctor'     { Show-Doctor }
    'tunnel'     { Invoke-Tunnel @CmdArgs }
    'security'   { Invoke-SecurityCmd -Action ($CmdArgs | Select-Object -First 1) }
    'stealth'    { Invoke-StealthCmd -Action ($CmdArgs | Select-Object -First 1) }
    'obfuscate'  { Invoke-ObfuscateCmd -Action ($CmdArgs | Select-Object -First 1) }
    'encrypt'    { Invoke-EncryptCmd -Action ($CmdArgs | Select-Object -First 1) }
    'tor'        { Invoke-TorCmd -Action ($CmdArgs | Select-Object -First 1) }
    'tamper'     { Invoke-TamperCmd -Action ($CmdArgs | Select-Object -First 1) }
    'killswitch' { Invoke-KillswitchCmd -Action ($CmdArgs | Select-Object -First 1) }
    'fail2ban'   { Invoke-Fail2banCmd -Action ($CmdArgs | Select-Object -First 1) }
    'tier'       { Invoke-TierCmd -Action ($CmdArgs | Select-Object -First 1) }
    'uninstall'  { Invoke-Uninstall }
    'version'    { Write-Host "WinVPS v$WinVPSVersion" }
    '--help'     { Show-Help }
    '-h'         { Show-Help }
    'help'       { Show-Help }
    ''           { Show-Status }
    default      { Err "Unknown: $Command"; Show-Help }
}
