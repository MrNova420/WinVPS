#Requires -Version 5.1
<#
.SYNOPSIS
    WinVPS Natural Language Shell.
.DESCRIPTION
    Type what you want in plain English. WinVPS translates to the correct command,
    shows it, and asks you to approve/edit/execute.
.EXAMPLE
    winvps shell
    winvps shell "how's my server doing"
    winvps shell "start the web server"
#>
param(
    [Parameter(Position=0, ValueFromRemainingArguments)]
    [string[]]$Query
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

$WinVPSVersion = '1.1.0'
$WinVPSDir = $env:WINVPS_DIR
if (-not $WinVPSDir) {
    if ($IsWindows -or $env:OS -eq 'Windows_NT') { $WinVPSDir = 'C:\WinVPS' }
    else { $WinVPSDir = Join-Path $HOME '.winvps' }
}
$SrcDir = Join-Path $WinVPSDir 'src'
$CLI    = Join-Path $SrcDir 'cli\winvps.ps1'

# --- Colors ---
$R  = "`e[0m"; $B  = "`e[1m"; $D  = "`e[2m"
$RD = "`e[31m"; $GN = "`e[32m"; $YL = "`e[33m"
$BL = "`e[34m"; $CY = "`e[36m"

$AllServices = @(
    'ssh','web','httpd','supervisor','healthcheck','security','fail2ban',
    'stealth','obfuscate','tamper','wipe','vpn-killswitch','encrypt','tor',
    'storage','autoupdate','lightweight','tunnel','telegram','discord',
    'nginx','apache','node','python','java','redis','postgres','mysql',
    'mongo','mail','ftp','dns','rdesktop','wireguard','tailscale'
)

function Find-Service {
    param([string]$Text)
    foreach ($s in $AllServices) {
        if ($Text -match "\b$s\b") { return $s }
    }
    if ($Text -match '(web|dashboard|panel|ui)')  { return 'web' }
    if ($Text -match '(ssh|remote|terminal)')     { return 'ssh' }
    if ($Text -match '(tor|proxy|anon)')          { return 'tor' }
    if ($Text -match '(tunnel|ngrok|cloudflare)') { return 'tunnel' }
    if ($Text -match 'telegram')                  { return 'telegram' }
    if ($Text -match 'discord')                   { return 'discord' }
    return ''
}

# ======================================================================
#  INTENT PARSER
# ======================================================================
function Parse-Intent {
    param([string]$Input)
    $t = $Input.ToLower().Trim() -replace '[^\w\s\-/]' '' -replace '\s+', ' '

    $svc = ''

    if ($t -match '^(exit|quit|bye|close|q)$') {
        return @{ Cmd = ''; Args = @(); Desc = ''; Kind = 'exit' }
    }
    if ($t -match '^\?$|^help$|^tips$|^what can|^commands') {
        return @{ Cmd = ''; Args = @(); Desc = ''; Kind = 'help' }
    }
    if ($t -match '(status|how.*(server|system|doing|going|health)|overview|dashboard|what.*(going|happening))') {
        return @{ Cmd = 'status'; Args = @(); Desc = 'Show system status (CPU, RAM, disk, uptime, services)'; Kind = 'run' }
    }
    if ($t -match '(health.?check|diagnos|doctor|check.*health|is.*everything|are.*services|all.*ok|all.*good|healthy)') {
        return @{ Cmd = 'doctor'; Args = @(); Desc = 'Run full system diagnostics'; Kind = 'run' }
    }
    if ($t -match '(monitor|watch|resource|live|real.?time|cpu.*usage|ram.*usage|performance)') {
        return @{ Cmd = 'monitor'; Args = @(); Desc = 'Live resource monitor (CPU/RAM/disk)'; Kind = 'run' }
    }
    if ($t -match '(list.*service|service.*list|all.*service|what.*running|show.*service)') {
        return @{ Cmd = 'service'; Args = @('list'); Desc = 'List all services and their status'; Kind = 'run' }
    }
    if ($t -match '(start|launch|run|spin.?up|boot|bring.?up|enable|activate|turn\ on)') {
        $svc = Find-Service $t
        if ($svc) { return @{ Cmd = 'service'; Args = @('start', $svc); Desc = "Start service: $svc"; Kind = 'run' } }
        return @{ Cmd = 'service'; Args = @('list'); Desc = 'Which service? Showing all available:'; Kind = 'run' }
    }
    if ($t -match '(stop|kill|halt|shutdown|shut.?down|disable|deactivate|turn\ off|drop)') {
        $svc = Find-Service $t
        if ($svc) { return @{ Cmd = 'service'; Args = @('stop', $svc); Desc = "Stop service: $svc"; Kind = 'run' } }
        return @{ Cmd = 'service'; Args = @('list'); Desc = 'Which service? Showing all available:'; Kind = 'run' }
    }
    if ($t -match '(restart|reboot|reload|refresh|recycle|bounce)') {
        $svc = Find-Service $t
        if ($svc) { return @{ Cmd = 'service'; Args = @('restart', $svc); Desc = "Restart service: $svc"; Kind = 'run' } }
        return @{ Cmd = 'service'; Args = @('list'); Desc = 'Which service? Showing all available:'; Kind = 'run' }
    }
    if ($t -match '(log|logs|error|errors|what.*wrong|tail|recent)') {
        $svc = Find-Service $t
        if ($svc) { return @{ Cmd = 'logs'; Args = @($svc, '50'); Desc = "Show last 50 lines of $svc logs"; Kind = 'run' } }
        return @{ Cmd = 'logs'; Args = @(); Desc = 'List all available log files'; Kind = 'run' }
    }
    if ($t -match '(backup|back.?up|save|snapshot)') {
        if ($t -match '(list|show|view|all|existing)') { return @{ Cmd = 'backup'; Args = @('list'); Desc = 'List all backups'; Kind = 'run' } }
        if ($t -match '(restore|recover|roll.?back)')  { return @{ Cmd = 'backup'; Args = @('restore'); Desc = 'Restore latest backup'; Kind = 'confirm' } }
        return @{ Cmd = 'backup'; Args = @('create'); Desc = 'Create a timestamped backup'; Kind = 'run' }
    }
    if ($t -match '(config|setting|configure)') {
        return @{ Cmd = 'config'; Args = @('show'); Desc = 'Show configuration'; Kind = 'run' }
    }
    if ($t -match '(security|secure|harden|firewall|protect|shield|lockdown)') {
        if ($t -match '(scan|check|audit)')    { return @{ Cmd = 'security'; Args = @('scan'); Desc = 'Run security scan'; Kind = 'run' } }
        if ($t -match '(harden|fix|strengthen)'){ return @{ Cmd = 'security'; Args = @('harden'); Desc = 'Apply security hardening'; Kind = 'confirm' } }
        return @{ Cmd = 'security'; Args = @('status'); Desc = 'Security status overview'; Kind = 'run' }
    }
    if ($t -match '(fail2ban|brute|ban.*ip|intruder|attack)') {
        if ($t -match '(start|enable|on)')  { return @{ Cmd = 'fail2ban'; Args = @('start');  Desc = 'Start fail2ban'; Kind = 'run' } }
        if ($t -match '(stop|disable|off)')  { return @{ Cmd = 'fail2ban'; Args = @('stop');   Desc = 'Stop fail2ban'; Kind = 'run' } }
        return @{ Cmd = 'fail2ban'; Args = @('status'); Desc = 'Fail2ban status'; Kind = 'run' }
    }
    if ($t -match '(stealth|invisible|hide|sneak|covert|incognito)') {
        if ($t -match '(enable|activate|on)')    { return @{ Cmd = 'stealth'; Args = @('enable');  Desc = 'Enable stealth mode'; Kind = 'confirm' } }
        if ($t -match '(disable|deactivate|off)'){ return @{ Cmd = 'stealth'; Args = @('disable'); Desc = 'Disable stealth mode'; Kind = 'run' } }
        return @{ Cmd = 'stealth'; Args = @('status'); Desc = 'Stealth mode status'; Kind = 'run' }
    }
    if ($t -match '(encrypt|encryption|bitlocker|veracrypt|cipher)') {
        if ($t -match '(init|setup|create|enable|mount)'){ return @{ Cmd = 'encrypt'; Args = @('init');    Desc = 'Initialize encrypted storage'; Kind = 'confirm' } }
        if ($t -match '(unmount|unlock|disable)')        { return @{ Cmd = 'encrypt'; Args = @('unmount'); Desc = 'Unmount encrypted volume'; Kind = 'confirm' } }
        return @{ Cmd = 'encrypt'; Args = @('status'); Desc = 'Encryption status'; Kind = 'run' }
    }
    if ($t -match '(tor|onion|hidden.?service|anonymous|dark)') {
        if ($t -match '(start|enable|launch|on)'){ return @{ Cmd = 'tor'; Args = @('start');  Desc = 'Start Tor gateway'; Kind = 'run' } }
        if ($t -match '(stop|disable|off)')      { return @{ Cmd = 'tor'; Args = @('stop');   Desc = 'Stop Tor gateway'; Kind = 'run' } }
        return @{ Cmd = 'tor'; Args = @('status'); Desc = 'Tor gateway status'; Kind = 'run' }
    }
    if ($t -match '(tunnel|expose|forward|ngrok|cloudflare|bore|public.*url)') {
        if ($t -match '(start|create|open|launch|enable)'){ return @{ Cmd = 'tunnel'; Args = @('start'); Desc = 'Start tunnel to internet'; Kind = 'run' } }
        if ($t -match '(stop|close|kill|disable)')         { return @{ Cmd = 'tunnel'; Args = @('stop');  Desc = 'Stop tunnel'; Kind = 'run' } }
        return @{ Cmd = 'tunnel'; Args = @('status'); Desc = 'Tunnel status'; Kind = 'run' }
    }
    if ($t -match '(tamper|integrity|dead.?man|sabotage)') {
        if ($t -match '(init|setup|create|enable)'){ return @{ Cmd = 'tamper'; Args = @('init');   Desc = 'Initialize tamper detection'; Kind = 'confirm' } }
        if ($t -match '(verify|check|test)')       { return @{ Cmd = 'tamper'; Args = @('verify'); Desc = 'Verify file integrity'; Kind = 'run' } }
        return @{ Cmd = 'tamper'; Args = @('status'); Desc = 'Tamper detection status'; Kind = 'run' }
    }
    if ($t -match '(kill.?switch|vpn.*block|vpn.*kill|block.*traffic|leak)') {
        if ($t -match '(enable|activate|on)')    { return @{ Cmd = 'killswitch'; Args = @('enable');  Desc = 'Enable VPN kill switch'; Kind = 'confirm' } }
        if ($t -match '(disable|deactivate|off)'){ return @{ Cmd = 'killswitch'; Args = @('disable'); Desc = 'Disable VPN kill switch'; Kind = 'run' } }
        return @{ Cmd = 'killswitch'; Args = @('status'); Desc = 'VPN kill switch status'; Kind = 'run' }
    }
    if ($t -match '(obfuscat|randomiz|disguis|camouflage|change.*hostname|change.*mac)') {
        return @{ Cmd = 'obfuscate'; Args = @('all'); Desc = 'Randomize hostname, MAC, SSH keys, HTTP headers'; Kind = 'confirm' }
    }
    if ($t -match '(tier|ram.*tier|memory.*class|optimize.*ram)') {
        return @{ Cmd = 'tier'; Args = @('info'); Desc = 'Show RAM tier and optimization suggestions'; Kind = 'run' }
    }
    if ($t -match '(version|ver\b|what.*version)') {
        return @{ Cmd = 'version'; Args = @(); Desc = 'Show WinVPS version'; Kind = 'run' }
    }
    if ($t -match '(storage|disk\s*space|disk\s*usage|how.*much.*space|size)') {
        return @{ Cmd = 'status'; Args = @(); Desc = 'System status including disk usage'; Kind = 'run' }
    }
    if ($t -match '(ip|address|network|my.*ip|external.*ip|local.*ip)') {
        return @{ Cmd = 'status'; Args = @(); Desc = 'Network info from system status'; Kind = 'run' }
    }
    if ($t -match '(open.*port|listening|port|what.*port|which.*port)') {
        return @{ Cmd = 'status'; Args = @(); Desc = 'Listening ports from system status'; Kind = 'run' }
    }
    if ($t -match '(uninstall|remove|delete.*winvps)') {
        return @{ Cmd = ''; Args = @(); Desc = ''; Kind = 'uninstall' }
    }
    if ($t -match '(what.*is.*winvps|about|describe)') {
        return @{ Cmd = ''; Args = @(); Desc = ''; Kind = 'about' }
    }

    return @{ Cmd = ''; Args = @(); Desc = ''; Kind = 'unknown' }
}

# ======================================================================
#  DISPLAY
# ======================================================================
function Show-Banner {
    Write-Host ''
    Write-Host "${CY}${B}      _    __        ______                __  ${R}"
    Write-Host "${CY}${B}     | |  / /__     / ____/___  _________/ /__${R}"
    Write-Host "${CY}${B}     | | / / _ \   / /   / __ \/ ___/ __  / _ \${R}"
    Write-Host "${CY}${B}     | |/ /  __/  / /___/ /_/ / /  / /_/ /  __/${R}"
    Write-Host "${CY}${B}     |___/\___/   \____/\____/_/   \__,_/\___/ ${R}"
    Write-Host "${D}       v${WinVPSVersion}  -  Natural Language Shell${R}"
    Write-Host ''
    Write-Host "${D}  Describe a command in plain English and I'll translate it.${R}"
    Write-Host "${D}  Type ${YL}?${D} for examples.  ${YL}exit${D} to quit.${R}"
    Write-Host ''
}

function Show-CommandBox {
    param([string]$FullCmd, [string]$Description)
    $indent = '  '
    $cmdLen = $FullCmd.Length
    $descLen = $Description.Length
    $boxW = [math]::Max($cmdLen + 4, 44)

    Write-Host ''
    Write-Host "${indent}${D}+-- Suggested Command ---------$(if ($boxW -gt 44) { '-' * ($boxW - 44) } else { '' })+${R}"
    Write-Host "${indent}${D}|${R}${B}${CY}  $FullCmd${R}" -NoNewline
    $pad = $boxW - $cmdLen - 2
    if ($pad -gt 0) { Write-Host (" " * $pad) -NoNewline }
    Write-Host "${D}|${R}"
    if ($Description) {
        Write-Host "${indent}${D}|${R}  ${D}$Description${R}" -NoNewline
        $dpad = $boxW - $descLen - 2
        if ($dpad -gt 0) { Write-Host (" " * $dpad) -NoNewline }
        Write-Host "${D}|${R}"
    }
    Write-Host "${indent}${D}+--$(if ($boxW -gt 2) { '-' * $boxW } else { '---' })+${R}"
}

function Show-ActionPrompt {
    Write-Host ''
    Write-Host "  ${B}Execute?${R} ${GN}[Y]${R}es  ${YL}[E]${R}dit  ${RD}[N]${R}o  ${D}[S]kip${R}"
}

function Show-Examples {
    Write-Host ''
    Write-Host "  ${B}${CY}Examples:${R}"
    Write-Host "  ${D}Natural Language${R}              ${D}Translates to${R}"
    Write-Host "  ${GN}how's my server doing${R}         ${B}winvps status${R}"
    Write-Host "  ${GN}start the web server${R}          ${B}winvps service start web${R}"
    Write-Host "  ${GN}stop ssh${R}                      ${B}winvps service stop ssh${R}"
    Write-Host "  ${GN}restart the database${R}          ${B}winvps service restart postgres${R}"
    Write-Host "  ${GN}show me recent errors${R}         ${B}winvps logs${R}"
    Write-Host "  ${GN}show ssh logs${R}                 ${B}winvps logs ssh 50${R}"
    Write-Host "  ${GN}run diagnostics${R}               ${B}winvps doctor${R}"
    Write-Host "  ${GN}create a backup${R}               ${B}winvps backup create${R}"
    Write-Host "  ${GN}open a tunnel${R}                 ${B}winvps tunnel start${R}"
    Write-Host "  ${GN}harden the server${R}             ${B}winvps security harden${R}"
    Write-Host "  ${GN}start fail2ban${R}                ${B}winvps fail2ban start${R}"
    Write-Host "  ${GN}enable stealth mode${R}           ${B}winvps stealth enable${R}"
    Write-Host "  ${GN}what version is this${R}          ${B}winvps version${R}"
    Write-Host "  ${GN}show all config${R}               ${B}winvps config show${R}"
    Write-Host ''
}

function Show-About {
    Write-Host ''
    Write-Host "  ${B}${CY}WinVPS v${WinVPSVersion}${R}"
    Write-Host "  ${D}Turn any machine into a self-managed,${R}"
    Write-Host "  ${D}auto-healing, remotely accessible VPS.${R}"
    Write-Host ''
    Write-Host "  ${B}Features:${R}"
    Write-Host "  Service supervisor | Web dashboard | Security hardening"
    Write-Host "  Cloud tunnels | Tor gateway | Telegram & Discord bots"
    Write-Host "  Encrypted storage | Tamper detection | Stealth mode"
    Write-Host "  RAM tiering | Auto-updates | Backup system"
    Write-Host ''
    Write-Host "  ${D}https://github.com/MrNova420/WinVPS${R}"
    Write-Host ''
}

# ======================================================================
#  EXECUTION
# ======================================================================
function Invoke-WinVPSCmd {
    param([string]$Cmd, [string[]]$CmdArgs)
    if (-not (Test-Path $CLI)) {
        Write-Host "  ${RD}x${R} WinVPS CLI not found"
        return
    }
    Write-Host ''
    & powershell -NoProfile -ExecutionPolicy Bypass -File $CLI $Cmd @CmdArgs 2>&1
    Write-Host ''
}

function Invoke-Approved {
    param([string]$Cmd, [string[]]$CmdArgs)
    Write-Host "  ${GN}>${R} Running..."
    Invoke-WinVPSCmd -Cmd $Cmd -CmdArgs $CmdArgs
}

function Invoke-Edited {
    Write-Host "  ${D}Edit the command:${R}"
    $edited = Read-Host "  winvps "
    if ($edited) {
        $parts = $edited.Trim() -split '\s+', 2
        $eCmd = $parts[0]
        $eArgs = if ($parts.Count -gt 1) { ($parts[1] -split '\s+') } else { @() }
        Write-Host "  ${GN}>${R} Running: winvps $edited"
        Invoke-WinVPSCmd -Cmd $eCmd -CmdArgs $eArgs
    }
}

function Handle-Prompt {
    param($Intent)
    Show-CommandBox -FullCmd "winvps $($Intent.Cmd) $($Intent.Args -join ' ')".Trim() -Description $Intent.Desc
    Show-ActionPrompt
    $response = (Read-Host '  > ').Trim().ToLower()
    switch ($response) {
        { $_ -match '^(y|yes|)$' } { Invoke-Approved -Cmd $Intent.Cmd -CmdArgs $Intent.Args }
        { $_ -match '^e' }         { Invoke-Edited }
        default                    { Write-Host "  ${D}Cancelled.${R}"; Write-Host '' }
    }
}

# ======================================================================
#  MAIN
# ======================================================================
if ($Query -and $Query.Count -gt 0) {
    $intent = Parse-Intent ($Query -join ' ')
    switch ($intent.Kind) {
        'exit'     { return }
        'help'     { Show-Examples }
        'about'    { Show-About }
        'uninstall'{ Write-Host "  ${YL}!${R} Use: ${B}winvps uninstall${R}" }
        'unknown'  { Write-Host "  ${YL}?${R} I didn't understand that. Type ${YL}?${R} for examples." }
        default    { Handle-Prompt $intent }
    }
} else {
    Show-Banner
    while ($true) {
        Write-Host "${CY}${B}  you>${R} " -NoNewline
        $input = Read-Host
        if (-not $input -or $input.Trim() -eq '') { continue }
        $intent = Parse-Intent $input
        switch ($intent.Kind) {
            'exit'     { Write-Host ''; Write-Host "  ${CY}See you!${R}"; Write-Host ''; break }
            'help'     { Show-Examples }
            'about'    { Show-About }
            'uninstall'{ Write-Host "  ${YL}!${R} Use: ${B}winvps uninstall${R}" }
            'unknown'  { Write-Host "  ${YL}?${R} I didn't understand that. Type ${YL}?${R} for examples." }
            default    { Handle-Prompt $intent }
        }
    }
}
