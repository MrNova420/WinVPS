#Requires -Version 5.1
<#
.SYNOPSIS
    WinVPS Discord Bot - remote management via Discord webhooks.
.DESCRIPTION
    Zero-dependency Discord bot using Invoke-RestMethod and the Discord REST API.
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
$PidFile = Join-Path $ServicesDir 'discord-bot.pid'
$LogFile = Join-Path $LogDir 'discord-bot.log'

$script:BotToken = ''
$script:ChannelId = ''
$script:LastMessageId = 0

function Log($msg) {
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
    "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [discord] $msg" | Out-File -FilePath $LogFile -Encoding ascii -Append
}

function Load-Config {
    if (Test-Path $ConfigFile) {
        $lines = Get-Content $ConfigFile
        $t = $lines | Where-Object { $_ -match '^WINVPS_DISCORD_BOT_TOKEN=' }
        $c = $lines | Where-Object { $_ -match '^WINVPS_DISCORD_CHANNEL_ID=' }
        if ($t) { $script:BotToken = ($t -split '=',2)[1].Trim('"') }
        if ($c) { $script:ChannelId = ($c -split '=',2)[1].Trim('"') }
    }
}

function Send-DiscordMessage {
    param([string]$Content)
    if (-not $script:BotToken) { return }
    try {
        $uri = "https://discord.com/api/v10/channels/$($script:ChannelId)/messages"
        $headers = @{ Authorization = "Bot $($script:BotToken)"; 'Content-Type' = 'application/json' }
        $body = @{ content = $Content } | ConvertTo-Json
        Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $body -TimeoutSec 10 -ErrorAction Stop
    } catch {}
}

function Process-Message {
    param([string]$Content, [string]$AuthorId)
    if ($Content -eq '!status') {
        $os = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue
        $cpu = Get-CimInstance Win32_Processor -ErrorAction SilentlyContinue
        $freeMB = [math]::Round($os.FreePhysicalMemory / 1024)
        $uptime = (Get-Date) - $os.LastBootUpTime
        Send-DiscordMessage "**WinVPS Status**`nUptime: $([math]::Floor($uptime.TotalHours))h $($uptime.Minutes)m`nCPU: $($cpu.LoadPercentage)%`nFree RAM: ${freeMB}MB"
    } elseif ($Content -eq '!health') {
        $hs = Join-Path $WinVPSDir 'src\core\healthcheck.ps1'
        if (Test-Path $hs) {
            $r = & powershell -NoProfile -ExecutionPolicy Bypass -File $hs 2>&1
            $codeBlock = "``````" + ($r -join "`n") + "``````"
            Send-DiscordMessage $codeBlock
        }
    } elseif ($Content -eq '!backup') {
        Send-DiscordMessage 'Creating backup...'
        $cli = Join-Path $WinVPSDir 'src\cli\winvps.ps1'
        & powershell -NoProfile -ExecutionPolicy Bypass -File $cli backup create 2>&1 | Out-Null
        Send-DiscordMessage 'Backup complete'
    } elseif ($Content -eq '!help') {
        Send-DiscordMessage "**WinVPS Bot**`n!status - System status`n!health - Health check`n!backup - Create backup`n!help - This message"
    }
}

function Start-Poll {
    Load-Config
    if (-not $script:BotToken) { Write-Host '[discord] Bot token not set'; return }

    while ($true) {
        try {
            $uri = "https://discord.com/api/v10/channels/$($script:ChannelId)/messages?limit=1"
            $headers = @{ Authorization = "Bot $($script:BotToken)"; 'Content-Type' = 'application/json' }
            $resp = Invoke-RestMethod -Uri $uri -Headers $headers -TimeoutSec 15
            foreach ($msg in $resp) {
                if ([long]$msg.id -gt [long]$script:LastMessageId) {
                    $script:LastMessageId = $msg.id
                    if ($msg.author.bot -ne $true -and $msg.content) {
                        Process-Message -Content $msg.content -AuthorId $msg.author.id
                    }
                }
            }
        } catch {}
        Start-Sleep -Seconds 5
    }
}

function Start-Bot {
    if (Test-Path $PidFile) {
        $pid = Get-Content $PidFile -ErrorAction SilentlyContinue
        if ($pid -and (Get-Process -Id ([int]$pid) -ErrorAction SilentlyContinue)) {
            Write-Host "[discord] Already running (PID $pid)"; return
        }
    }
    Load-Config
    if (-not $script:BotToken) { Write-Host '[discord] Bot token not set - bot disabled'; return }

    $pinfo = New-Object System.Diagnostics.ProcessStartInfo
    $pinfo.FileName = 'powershell.exe'
    $pinfo.Arguments = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$PSCommandPath`" poll"
    $pinfo.UseShellExecute = $false
    $pinfo.CreateNoWindow = $true
    $proc = [System.Diagnostics.Process]::Start($pinfo)
    $proc.Id | Out-File -FilePath $PidFile -Encoding ascii -Force
    Start-Sleep -Seconds 2
    if (-not $proc.HasExited) {
        Write-Host "[discord] Bot started (PID $($proc.Id))"
        Send-DiscordMessage 'WinVPS Discord bot started'
    } else {
        Write-Host '[discord] Bot failed to start'
    }
}

function Stop-Bot {
    if (Test-Path $PidFile) {
        $pid = Get-Content $PidFile -ErrorAction SilentlyContinue
        if ($pid) { Stop-Process -Id ([int]$pid) -Force -ErrorAction SilentlyContinue }
        Remove-Item $PidFile -Force
        Write-Host '[discord] Bot stopped'
    }
}

switch ($Action) {
    'start'   { Start-Bot }
    'stop'    { Stop-Bot }
    'restart' { Stop-Bot; Start-Sleep -Seconds 2; Start-Bot }
    'poll'    { Start-Poll }
    default   { Write-Host 'Usage: shell-discord.ps1 {start|stop|restart}' }
}
