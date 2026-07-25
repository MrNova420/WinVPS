#Requires -Version 5.1
<#
.SYNOPSIS
    WinVPS v2.0 - Windows Virtual Private Server Management CLI.
.DESCRIPTION
    Main entry point for managing WinVPS services, security, tunnels, and configuration.
    Type "winvps help" for all commands.
.EXAMPLE
    winvps status
    winvps service list
    winvps service add my-app "D:\projects\app\server.js" --port 3000 --type node
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

# --- Version ---
$WinVPSVersion = '2.0.0'

# --- Paths ---
$WinVPSDir  = $env:WINVPS_DIR; if (-not $WinVPSDir) { $WinVPSDir = 'C:\WinVPS' }
$SrcDir     = Join-Path $WinVPSDir 'src'
$CoreDir    = Join-Path $SrcDir 'core'
$ConfigDir  = Join-Path $WinVPSDir 'config'
$ConfigFile = Join-Path $ConfigDir 'winvps.conf'
$ServicesDir = Join-Path $WinVPSDir 'services'
$LogDir     = Join-Path $WinVPSDir 'logs'
$BackupDir  = Join-Path $WinVPSDir 'backup'

# --- Theme ---
$Theme = @{
    Primary   = "`e[38;5;75m"
    Success   = "`e[38;5;114m"
    Warning   = "`e[38;5;221m"
    Error     = "`e[38;5;203m"
    Info      = "`e[38;5;252m"
    Dim       = "`e[38;5;243m"
    Accent    = "`e[38;5;141m"
    Reset     = "`e[0m"
    Bold      = "`e[1m"
}

function Log($msg)  { Write-Host "$($Theme.Success)[-]$($Theme.Reset) $msg" }
function Warn($msg) { Write-Host "$($Theme.Warning)[!]$($Theme.Reset) $msg" }
function Err($msg)  { Write-Host "$($Theme.Error)[x]$($Theme.Reset) $msg" }
function Info($msg)  { Write-Host "$($Theme.Primary)[i]$($Theme.Reset) $msg" }

function Ensure-Dirs {
    $dirs = @(
        $ConfigDir, (Join-Path $WinVPSDir 'data'), $LogDir, $ServicesDir, $BackupDir,
        (Join-Path $WinVPSDir 'tmp'), (Join-Path $WinVPSDir 'ssl'),
        (Join-Path $WinVPSDir 'tunnels'), $ConfigDir, (Join-Path $ConfigDir 'profiles')
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

function Get-PidFile($name) { Join-Path $ServicesDir "$name.pid" }

function Test-ServiceRunning($name) {
    $pf = Get-PidFile $name
    if (-not (Test-Path $pf)) { return $false }
    $pid = [int](Get-Content $pf -ErrorAction SilentlyContinue)
    if ($pid -le 0) { return $false }
    return ($null -ne (Get-Process -Id $pid -ErrorAction SilentlyContinue))
}

function Get-ServicePid($name) {
    $pf = Get-PidFile $name
    if (-not (Test-Path $pf)) { return 0 }
    return [int](Get-Content $pf -ErrorAction SilentlyContinue)
}

# --- Parse Named Args ---
function Parse-Args {
    param([string[]]$ArgsList, [string[]]$FlagNames)
    $result = @{}
    for ($i = 0; $i -lt $ArgsList.Count; $i++) {
        $arg = $ArgsList[$i]
        if ($arg -match '^--(\w+)$') {
            $key = $matches[1]
            if ($FlagNames -contains $key -and $i + 1 -lt $ArgsList.Count) {
                $result[$key] = $ArgsList[$i + 1]
                $i++
            } else {
                $result[$key] = $true
            }
        }
    }
    return $result
}

# ============================================================
# --- STATUS ---
# ============================================================
function Show-Status {
    Load-Config
    Write-Host ''
    Write-Host "  $($Theme.Bold)WinVPS v$WinVPSVersion - System Status$($Theme.Reset)"
    Write-Host "  $($Dim)------------------------------------------$($Theme.Reset)"
    Write-Host ''

    # System
    Write-Host "  $($Theme.Primary)SYSTEM$($Theme.Reset)"
    $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    if ($os) {
        $uptime = (Get-Date) - $os.LastBootUpTime
        Write-Host "  Uptime:    $($Theme.Bold)$([math]::Floor($uptime.TotalHours))h $($uptime.Minutes)m$($Theme.Reset)"
    }
    if ($cs) {
        $totalMB = [math]::Round($cs.TotalPhysicalMemory / 1MB)
        $freeMB = [math]::Round($os.FreePhysicalMemory / 1024)
        $usedMB = $totalMB - $freeMB
        $pct = [math]::Round($usedMB / $totalMB * 100)
        $color = if ($pct -gt 80) { $Theme.Error } elseif ($pct -gt 60) { $Theme.Warning } else { $Theme.Success }
        Write-Host "  Memory:    $color$pct%$Theme.Reset ($($usedMB)MB/$($totalMB)MB)"
    }
    $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue
    if ($cpu) {
        $cpct = $cpu.LoadPercentage
        $color = if ($cpct -gt 80) { $Theme.Error } elseif ($cpct -gt 60) { $Theme.Warning } else { $Theme.Success }
        Write-Host "  CPU:       ${color}${cpct}%$Theme.Reset ($($cpu.NumberOfCores) cores)"
    }

    # Services
    Write-Host ''
    Write-Host "  $($Theme.Primary)SERVICES$($Theme.Reset)"
    $running = 0
    Get-ChildItem -Path $ServicesDir -Filter '*.pid' -ErrorAction SilentlyContinue | ForEach-Object {
        $name = $_.BaseName
        $pid = [int](Get-Content $_.FullName -ErrorAction SilentlyContinue)
        $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
        if ($proc) {
            $mem = [math]::Round($proc.WorkingSet64 / 1MB, 1)
            Write-Host "  $($Theme.Success)*$($Theme.Reset) ${name} $($Theme.Dim)PID $pid, ${mem}MB$($Theme.Reset)"
            $running++
        }
    }
    if ($running -eq 0) { Write-Host "  $($Theme.Dim)(no services running)$($Theme.Reset)" }

    # Network
    Write-Host ''
    Write-Host "  $($Theme.Primary)NETWORK$($Theme.Reset)"
    $sshListening = Get-NetTCPConnection -LocalPort $script:SSHPort -State Listen -ErrorAction SilentlyContinue
    $webListening = Get-NetTCPConnection -LocalPort $script:WebPort -State Listen -ErrorAction SilentlyContinue
    Write-Host "  SSH:  port $($script:SSHPort) $(if ($sshListening) { "$($Theme.Success)active$($Theme.Reset)" } else { "$($Theme.Dim)inactive$($Theme.Reset)" })"
    Write-Host "  Web:  port $($script:WebPort) $(if ($webListening) { "$($Theme.Success)active$($Theme.Reset)" } else { "$($Theme.Dim)inactive$($Theme.Reset)" })"

    # Security
    Write-Host ''
    Write-Host "  $($Theme.Primary)SECURITY$($Theme.Reset)"
    $stealth = Test-Path (Join-Path $ConfigDir '.stealth_enabled')
    $obfuscate = Test-Path (Join-Path $ConfigDir '.obfuscated')
    Write-Host "  Stealth:   $(if ($stealth) { "$($Theme.Success)ACTIVE$($Theme.Reset)" } else { "$($Theme.Dim)inactive$($Theme.Reset)" })"
    Write-Host "  Obfuscate: $(if ($obfuscate) { "$($Theme.Success)ACTIVE$($Theme.Reset)" } else { "$($Theme.Dim)inactive$($Theme.Reset)" })"
    Write-Host ''
}

# ============================================================
# --- SERVICE ---
# ============================================================
function Invoke-Service {
    param([string]$Action, [string]$Name = '')
    Load-Config

    $supervisor = Join-Path $CoreDir 'supervisor.ps1'

    switch ($Action) {
        'list' {
            & powershell -NoProfile -ExecutionPolicy Bypass -File $supervisor list
        }
        'start' {
            if (-not $Name) { Err "Service name required"; return }
            & powershell -NoProfile -ExecutionPolicy Bypass -File $supervisor start -ServiceName $Name
        }
        'stop' {
            if (-not $Name) { Err "Service name required"; return }
            & powershell -NoProfile -ExecutionPolicy Bypass -File $supervisor stop -ServiceName $Name
        }
        'restart' {
            if (-not $Name) { Err "Service name required"; return }
            & powershell -NoProfile -ExecutionPolicy Bypass -File $supervisor restart -ServiceName $Name
        }
        'add' {
            $parsed = Parse-Args $CmdArgs @('port','type','health','depends','desc')
            $scriptArg = $CmdArgs | Where-Object { $_ -notmatch '^--' } | Select-Object -First 1

            if (-not $Name) {
                # Interactive mode
                Write-Host ''
                Write-Host "  $($Theme.Primary)Add Service - Interactive$($Theme.Reset)"
                Write-Host "  $($Dim)---------------------------$($Theme.Reset)"
                Write-Host ''
                $Name = Read-Host "  Service name"
                if (-not $Name) { Err "Name required"; return }
                $scriptArg = Read-Host "  Script path"
                if (-not $scriptArg) { Err "Script path required"; return }

                # Auto-detect type
                $ext = [System.IO.Path]::GetExtension($scriptArg).ToLower()
                $detectedType = switch ($ext) {
                    '.js'  { 'node' }
                    '.mjs' { 'node' }
                    '.ts'  { 'node' }
                    '.py'  { 'python' }
                    '.ps1' { 'ps' }
                    '.cmd' { 'cmd' }
                    '.bat' { 'cmd' }
                    '.go'  { 'go' }
                    default { 'ps' }
                }
                $typeInput = Read-Host "  Type [$detectedType]"
                $Type = if ($typeInput) { $typeInput } else { $detectedType }

                $portInput = Read-Host "  Port [0]"
                $Port = if ($portInput) { [int]$portInput } else { 0 }

                $autoInput = Read-Host "  Auto-start on boot? [y/N]"
                $AutoStart = ($autoInput -eq 'y' -or $autoInput -eq 'Y')

                $healthInput = Read-Host "  Health check URL (optional)"
                $HealthCheck = $healthInput

                $depsInput = Read-Host "  Dependencies (comma-separated, optional)"
                $DependsOn = $depsInput

                $descInput = Read-Host "  Description (optional)"
                $Description = $descInput
            } else {
                # Flag mode
                $scriptArg = $CmdArgs | Where-Object { $_ -notmatch '^--' } | Select-Object -Skip 1 -First 1
                if (-not $scriptArg) { Err "Script path required"; return }
                $Type = if ($parsed['type']) { $parsed['type'] } else { 'auto' }
                $Port = if ($parsed['port']) { [int]$parsed['port'] } else { 0 }
                $AutoStart = [bool]$parsed['auto']
                $HealthCheck = if ($parsed['health']) { $parsed['health'] } else { '' }
                $DependsOn = if ($parsed['depends']) { $parsed['depends'] } else { '' }
                $Description = if ($parsed['desc']) { $parsed['desc'] } else { '' }
            }

            & powershell -NoProfile -ExecutionPolicy Bypass -File $supervisor add `
                -ServiceName $Name -ScriptPath $scriptArg -Type $Type -Port $Port `
                -AutoStart $AutoStart -HealthCheck $HealthCheck -DependsOn $DependsOn -Description $Description
        }
        'remove' {
            if (-not $Name) { Err "Service name required"; return }
            & powershell -NoProfile -ExecutionPolicy Bypass -File $supervisor remove -ServiceName $Name
        }
        'setup' {
            Log 'Running initial service setup...'
            & powershell -NoProfile -ExecutionPolicy Bypass -File $supervisor start
            Log 'Initial setup complete'
        }
        default { Write-Host "  Usage: winvps service {list|start|stop|restart|add|remove|setup} [name]" }
    }
}

# ============================================================
# --- MONITOR ---
# ============================================================
function Show-Monitor {
    $delay = if ($CmdArgs.Count -gt 0) { [int]$CmdArgs[0] } else { 3 }
    while ($true) {
        Clear-Host
        Write-Host "  $($Theme.Bold)WinVPS Monitor$($Theme.Reset) - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
        Write-Host "  $($Dim)------------------------------------------$($Theme.Reset)"
        Write-Host ''
        $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue
        if ($cpu) { Write-Host "  $($Theme.Primary)CPU:$($Theme.Reset)    $($cpu.LoadPercentage)%" }
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        if ($os) {
            $totalMB = [math]::Round($os.TotalPhysicalMemory / 1MB)
            $freeMB = [math]::Round($os.FreePhysicalMemory / 1024)
            Write-Host "  $($Theme.Primary)Memory:$($Theme.Reset) $([math]::Round(($totalMB - $freeMB) / $totalMB * 100))% ($($totalMB - $freeMB)MB/${totalMB}MB)"
        }
        Write-Host ''
        Write-Host "  $($Theme.Primary)Services:$($Theme.Reset)"
        Get-ChildItem -Path $ServicesDir -Filter '*.pid' -ErrorAction SilentlyContinue | ForEach-Object {
            $pid = [int](Get-Content $_.FullName -ErrorAction SilentlyContinue)
            $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
            if ($proc) {
                $mem = [math]::Round($proc.WorkingSet64 / 1MB, 1)
                Write-Host "    $($Theme.Success)*$($Theme.Reset) $($_.BaseName) $($Theme.Dim)PID $pid, ${mem}MB$($Theme.Reset)"
            }
        }
        Write-Host ''
        Write-Host "  $($Theme.Dim)Press Ctrl+C to exit$($Theme.Reset)"
        Start-Sleep -Seconds $delay
    }
}

# ============================================================
# --- BACKUP ---
# ============================================================
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
                ForEach-Object { Write-Host "  $($_.Name) $($Theme.Dim)($([math]::Round($_.Length/1MB,2)) MB)$($Theme.Reset)" }
        }
        'restore' {
            $latest = Get-ChildItem -Path $BackupDir -Filter '*.zip' -ErrorAction SilentlyContinue |
                Sort-Object LastWriteTime -Descending | Select-Object -First 1
            if ($latest) {
                Expand-Archive -Path $latest.FullName -DestinationPath $WinVPSDir -Force
                Log "Restored from $($latest.Name)"
            } else { Warn 'No backups found' }
        }
        default { Write-Host '  Usage: winvps backup {create|list|restore}' }
    }
}

# ============================================================
# --- CONFIG ---
# ============================================================
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
            $profile = if ($CmdArgs.Count -gt 0) { $CmdArgs[0] } else { 'full' }
            $pf = Join-Path $ConfigDir "profiles\$profile.conf"
            if (Test-Path $pf) {
                Copy-Item $pf $ConfigFile -Force
                Log "Loaded profile: $profile"
            } else { Err "Profile not found: $profile" }
        }
        default { Write-Host '  Usage: winvps config {show|get|set|load} [key] [value]' }
    }
}

# ============================================================
# --- LOGS ---
# ============================================================
function Show-Logs {
    param([string]$Service = '', [int]$Lines = 50)
    if ($Service) {
        $logFile = Join-Path $LogDir "$Service.log"
        if (Test-Path $logFile) {
            Get-Content $logFile -Tail $Lines
        } else { Err "No logs for '$Service'" }
    } else {
        Write-Host ''
        Write-Host "  $($Theme.Primary)Available Logs$($Theme.Reset)"
        Write-Host "  $($Dim)------------------------------------------$($Theme.Reset)"
        Get-ChildItem -Path $LogDir -Filter '*.log' -ErrorAction SilentlyContinue |
            ForEach-Object { Write-Host "  $($_.Name) $($Theme.Dim)($([math]::Round($_.Length/1KB))KB)$($Theme.Reset)" }
    }
}

# ============================================================
# --- TUNNEL ---
# ============================================================
function Invoke-Tunnel {
    $script = Join-Path $SrcDir 'tunnels\tunnel-manager.ps1'
    if (Test-Path $script) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $script @CmdArgs
    } else { Err 'Tunnel manager not installed' }
}

# ============================================================
# --- SECURITY ---
# ============================================================
function Invoke-SecurityCmd {
    param([string]$Action = 'status')
    $script = Join-Path $CoreDir 'security.ps1'
    if (Test-Path $script) { & powershell -NoProfile -ExecutionPolicy Bypass -File $script $Action }
}

function Invoke-StealthCmd {
    param([string]$Action = 'status')
    $script = Join-Path $CoreDir 'stealth.ps1'
    if (Test-Path $script) { & powershell -NoProfile -ExecutionPolicy Bypass -File $script $Action @CmdArgs }
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

# ============================================================
# --- DOCTOR ---
# ============================================================
function Show-Doctor {
    Write-Host ''
    Write-Host "  $($Theme.Bold)WinVPS Diagnostics$($Theme.Reset)"
    Write-Host "  $($Dim)------------------------------------------$($Theme.Reset)"
    Write-Host ''
    $checks = 0; $passed = 0
    function Check($desc, $result) {
        $script:checks++
        if ($result) { Write-Host "  $($Theme.Success)[PASS]$($Theme.Reset) $desc"; $script:passed++ }
        else { Write-Host "  $($Theme.Error)[FAIL]$($Theme.Reset) $desc" }
    }
    Check 'WinVPS directory' (Test-Path $WinVPSDir)
    Check 'Config file' (Test-Path $ConfigFile)
    Check 'Services.conf' (Test-Path (Join-Path $ConfigDir 'services.conf'))
    Check 'PowerShell 5.1+' ($PSVersionTable.PSVersion.Major -ge 5)
    Check 'OpenSSH' ((Get-Service -Name 'sshd' -ErrorAction SilentlyContinue) -ne $null)
    Get-ChildItem -Path $ServicesDir -Filter '*.pid' -ErrorAction SilentlyContinue | ForEach-Object {
        $pid = [int](Get-Content $_.FullName -ErrorAction SilentlyContinue)
        Check "$($_.BaseName) running" ((Get-Process -Id $pid -ErrorAction SilentlyContinue) -ne $null)
    }
    Write-Host ''
    $pct = [math]::Round($passed / $checks * 100)
    $color = if ($pct -eq 100) { $Theme.Success } elseif ($pct -ge 75) { $Theme.Warning } else { $Theme.Error }
    Write-Host "  Results: ${color}$passed/$checks$Theme.Reset ($pct%)"
    Write-Host ''
}

# ============================================================
# --- HELP ---
# ============================================================
function Show-Help {
    Write-Host ''
    Write-Host "  $($Theme.Bold)WinVPS v$WinVPSVersion - Windows VPS Management$($Theme.Reset)"
    Write-Host "  $($Dim)------------------------------------------------------$($Theme.Reset)"
    Write-Host ''
    Write-Host "  $($Theme.Primary)CORE$($Theme.Reset)"
    Write-Host "    shell               Natural language shell (ask in plain English)"
    Write-Host "    status              System overview (CPU, RAM, services, network)"
    Write-Host "    service list        List all registered services"
    Write-Host "    service add         Add any project as a managed service"
    Write-Host "    service remove      Remove a service"
    Write-Host "    service start/stop  Start or stop a service"
    Write-Host "    monitor             Live resource monitor"
    Write-Host "    doctor              Run diagnostics"
    Write-Host ''
    Write-Host "  $($Theme.Primary)NETWORKING$($Theme.Reset)"
    Write-Host "    tunnel start        Start tunnel (tailscale|cloudflare|ngrok|bore)"
    Write-Host "    tunnel stop         Stop active tunnel"
    Write-Host "    tor                 Tor gateway"
    Write-Host "    killswitch          VPN kill switch"
    Write-Host ''
    Write-Host "  $($Theme.Primary)SECURITY$($Theme.Reset)"
    Write-Host "    security            Security tools (status|scan|harden)"
    Write-Host "    stealth             Stealth mode (enable|disable|status)"
    Write-Host "    obfuscate           Device obfuscation"
    Write-Host "    encrypt             Encrypted storage"
    Write-Host "    tamper              Tamper detection"
    Write-Host "    fail2ban            Brute-force protection"
    Write-Host ''
    Write-Host "  $($Theme.Primary)DATA$($Theme.Reset)"
    Write-Host "    backup              Backup management (create|list|restore)"
    Write-Host "    logs                View logs"
    Write-Host "    config              Configuration (show|get|set|load)"
    Write-Host "    tier                RAM tier info"
    Write-Host ''
    Write-Host "  $($Theme.Primary)OTHER$($Theme.Reset)"
    Write-Host "    uninstall           Remove WinVPS"
    Write-Host "    version             Show version"
    Write-Host "    help                This help"
    Write-Host ''
}

# ============================================================
# --- UNINSTALL ---
# ============================================================
function Invoke-Uninstall {
    $uninstaller = Join-Path $WinVPSDir 'setup\Uninstall-WinVPS.ps1'
    if (Test-Path $uninstaller) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $uninstaller
    } else { Warn 'Uninstaller not found - remove C:\WinVPS manually' }
}

# ============================================================
# --- SHELL (Natural Language) ---
# ============================================================
function Invoke-Shell {
    $shellScript = Join-Path $SrcDir 'shell\shell.ps1'
    if (Test-Path $shellScript) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $shellScript @CmdArgs
    } else { Err 'Natural language shell not found' }
}

# ============================================================
# --- BANNER ---
# ============================================================
function Show-Banner {
    Write-Host ''
    Write-Host "  $($Theme.Bold)$($Theme.Primary)WinVPS$($Theme.Reset)" -NoNewline
    Write-Host " $($Theme.Dim)v$WinVPSVersion$($Theme.Reset)"
    Write-Host "  $($Theme.Dim)Natural Language VPS Manager$($Theme.Reset)"
    Write-Host ''
}

# ============================================================
# --- MAIN ---
# ============================================================
Ensure-Dirs

switch ($Command) {
    'status'     { Show-Status }
    'service'    { Invoke-Service -Action ($CmdArgs | Select-Object -First 1) -Name ($CmdArgs | Select-Object -Skip 1 | Select-Object -First 1) }
    'monitor'    { Show-Monitor }
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
    'shell'      { Invoke-Shell }
    'uninstall'  { Invoke-Uninstall }
    'version'    { Show-Banner; Write-Host "  $($Theme.Dim)Version $WinVPSVersion$($Theme.Reset)" }
    '--help'     { Show-Help }
    '-h'         { Show-Help }
    'help'       { Show-Help }
    ''           { Show-Banner; Show-Status }
    default      { Err "Unknown: $Command"; Show-Help }
}
