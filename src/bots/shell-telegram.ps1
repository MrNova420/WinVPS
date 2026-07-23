#Requires -Version 5.1
<#
.SYNOPSIS
    WinVPS Telegram Bot - remote management via Telegram.
.DESCRIPTION
    Zero-dependency Telegram bot using Invoke-RestMethod and the Telegram REST API.
#>
param(
    [Parameter(Position=0)]
    [ValidateSet('start','stop','restart','poll')]
    [string]$Action = 'start'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'SilentlyContinue'

$WinVPSDir = $env:WINVPS_DIR; if (-not $WinVPSDir) { $WinVPSDir = 'C:\WinVPS' }
$ServicesDir = Join-Path $WinVPSDir 'services'
$LogDir = Join-Path $WinVPSDir 'logs'
$ConfigFile = Join-Path $WinVPSDir 'config\winvps.conf'
$PidFile = Join-Path $ServicesDir 'telegram-bot.pid'
$LogFile = Join-Path $LogDir 'telegram-bot.log'

$script:Token = ''
$script:ChatId = ''
$script:LastUpdate = 0

function Log($msg) {
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [telegram] $msg" | Out-File -FilePath $LogFile -Encoding ascii -Append
}

function Load-Config {
    if (Test-Path $ConfigFile) {
        $lines = Get-Content $ConfigFile
        $t = $lines | Where-Object { $_ -match '^WINVPS_TELEGRAM_BOT_TOKEN=' }
        $c = $lines | Where-Object { $_ -match '^WINVPS_TELEGRAM_CHAT_ID=' }
        if ($t) { $script:Token = ($t -split '=',2)[1].Trim('"') }
        if ($c) { $script:ChatId = ($c -split '=',2)[1].Trim('"') }
    }
}

function Send-TelegramMessage {
    param([string]$Text)
    if (-not $script:Token -or -not $script:ChatId) { return }
    try {
        $uri = "https://api.telegram.org/bot$($script:Token)/sendMessage"
        Invoke-RestMethod -Uri $uri -Method Post -Body @{ chat_id = $script:ChatId; text = $Text; parse_mode = 'Markdown' } -TimeoutSec 10 -ErrorAction Stop
    } catch {}
}

function Process-Update {
    param([string]$Msg, [string]$Chat)
    Log "Command: $Msg from $Chat"
    switch -Wildcard ($Msg) {
        '/start'  { Send-TelegramMessage "WinVPS Bot`n/status - System status`n/services - List services`n/health - Health check`n/backup - Create backup`n/help - Help" }
        '/help'   { Send-TelegramMessage "WinVPS Bot Commands:`n/status - System status`n/services - List services`n/health - Health check`n/backup - Create backup" }
        '/status' {
            $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
            $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue
            $totalMB = [math]::Round($os.TotalPhysicalMemory / 1MB)
            $freeMB = [math]::Round($os.FreePhysicalMemory / 1024)
            $uptime = (Get-Date) - $os.LastBootUpTime
            Send-TelegramMessage "WinVPS Status`nUptime: $([math]::Floor($uptime.TotalHours))h $($uptime.Minutes)m`nCPU: $($cpu.LoadPercentage)%`nMemory: $($totalMB - $freeMB)MB/${totalMB}MB"
        }
        '/services' {
            $out = 'Services:'
            Get-ChildItem -Path $ServicesDir -Filter '*.pid' -ErrorAction SilentlyContinue | ForEach-Object {
                $pid = [int](Get-Content $_.FullName -ErrorAction SilentlyContinue)
                $running = if ($pid -and (Get-Process -Id $pid -ErrorAction SilentlyContinue)) { 'running' } else { 'stopped' }
                $out += "`n$($_.BaseName): $running"
            }
            Send-TelegramMessage $out
        }
        '/health' {
            $hs = Join-Path $WinVPSDir 'src\core\healthcheck.ps1'
            if (Test-Path $hs) {
                $r = & powershell -NoProfile -ExecutionPolicy Bypass -File $hs 2>&1
                Send-TelegramMessage "Health: $($r | Select-Object -Last 3 | Out-String)"
            }
        }
        '/backup' {
            Send-TelegramMessage 'Creating backup...'
            $cli = Join-Path $WinVPSDir 'src\cli\winvps.ps1'
            & powershell -NoProfile -ExecutionPolicy Bypass -File $cli backup create 2>&1 | Out-Null
            Send-TelegramMessage 'Backup complete'
        }
    }
}

function Start-Poll {
    Load-Config
    if (-not $script:Token) { Write-Host '[telegram] WINVPS_TELEGRAM_BOT_TOKEN not set'; return }

    while ($true) {
        try {
            $uri = "https://api.telegram.org/bot$($script:Token)/getUpdates?offset=$($script:LastUpdate)&timeout=10"
            $resp = Invoke-RestMethod -Uri $uri -TimeoutSec 15
            foreach ($update in $resp.result) {
                if ($update.update_id -ge $script:LastUpdate) {
                    $script:LastUpdate = $update.update_id + 1
                }
                if ($update.message.text) {
                    Process-Update -Msg $update.message.text -Chat $update.message.chat.id
                }
            }
        } catch {}
        Start-Sleep -Seconds 3
    }
}

function Start-Bot {
    if (Test-Path $PidFile) {
        $pid = Get-Content $PidFile -ErrorAction SilentlyContinue
        if ($pid -and (Get-Process -Id ([int]$pid) -ErrorAction SilentlyContinue)) {
            Write-Host "[telegram] Already running (PID $pid)"; return
        }
    }
    Load-Config
    if (-not $script:Token) { Write-Host '[telegram] Token not set - bot disabled'; return }

    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = 'powershell.exe'
    $pinfo.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$PSCommandPath`" poll"
    $pinfo.UseShellExecute = $false
    $pinfo.CreateNoWindow = $true
    $proc = [System.Diagnostics.Process]::Start($pinfo)
    $proc.Id | Out-File -FilePath $PidFile -Encoding ascii -Force
    Start-Sleep -Seconds 2
    if (-not $proc.HasExited) {
        Write-Host "[telegram] Bot started (PID $($proc.Id))"
        Send-TelegramMessage 'WinVPS Telegram bot started'
    } else {
        Write-Host '[telegram] Bot failed to start'
    }
}

function Stop-Bot {
    if (Test-Path $PidFile) {
        $pid = Get-Content $PidFile -ErrorAction SilentlyContinue
        if ($pid) { Stop-Process -Id ([int]$pid) -Force -ErrorAction SilentlyContinue }
        Remove-Item $PidFile -Force
        Write-Host '[telegram] Bot stopped'
    }
}

switch ($Action) {
    'start'   { Start-Bot }
    'stop'    { Stop-Bot }
    'restart' { Stop-Bot; Start-Sleep -Seconds 2; Start-Bot }
    'poll'    { Start-Poll }
    default   { Write-Host 'Usage: telegram.ps1 {start|stop|restart}' }
}
