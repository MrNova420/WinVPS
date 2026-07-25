#Requires -Version 5.1
<#
.SYNOPSIS
    WinVPS Service Supervisor v2.0 - manages, monitors, and auto-heals services.
.DESCRIPTION
    Reads services from config/services.conf (pipe-delimited), starts/stops services
    with dependency resolution, runs a watchdog loop with health checks and backoff,
    and maintains PID tracking for all managed services.
.PARAMETER Action
    start, stop, restart, status, watchdog, list, add, remove
.PARAMETER ServiceName
    Name of a specific service to act on.
.PARAMETER ScriptPath
    Script path for 'add' action.
.PARAMETER Port
    Port for 'add' action.
.PARAMETER Type
    Service type for 'add' action (ps, cmd, node, python, go, dotnet, docker, custom).
.PARAMETER AutoStart
    Whether to auto-start on boot for 'add' action.
.PARAMETER HealthCheck
    Health check URL or port for 'add' action.
.PARAMETER DependsOn
    Comma-separated dependencies for 'add' action.
.PARAMETER Description
    Human-readable description for 'add' action.
.PARAMETER Watchdog
    Run watchdog loop after starting.
#>
param(
    [Parameter(Position=0)]
    [ValidateSet('start','stop','restart','status','watchdog','list','add','remove')]
    [string]$Action = 'status',

    [string]$ServiceName = '',
    [string]$ScriptPath = '',
    [int]$Port = 0,
    [string]$Type = 'auto',
    [bool]$AutoStart = $false,
    [string]$HealthCheck = '',
    [string]$DependsOn = '',
    [string]$Description = '',
    [switch]$Watchdog
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$WinVPSDir = $env:WINVPS_DIR; if (-not $WinVPSDir) { $WinVPSDir = 'C:\WinVPS' }
$SrcDir    = Join-Path $WinVPSDir 'src\core'
$ServicesDir = Join-Path $WinVPSDir 'services'
$LogDir    = Join-Path $WinVPSDir 'logs'
$ConfigFile = Join-Path $WinVPSDir 'config\winvps.conf'
$ServicesConf = Join-Path $WinVPSDir 'config\services.conf'

# --- Theme ---
$Green  = "`e[38;5;114m"
$Yellow = "`e[38;5;221m"
$Red    = "`e[38;5;203m"
$Cyan   = "`e[38;5;75m"
$Purple = "`e[38;5;141m"
$Dim    = "`e[38;5;243m"
$Bold   = "`e[1m"
$NC     = "`e[0m"

function Log($msg)  { Write-Host "${Green}[supervisor]${NC} $msg" }
function Warn($msg) { Write-Host "${Yellow}[supervisor]${NC} $msg" }
function Err($msg)  { Write-Host "${Red}[supervisor]${NC} $msg" }

# --- Directory Setup ---
function Ensure-Dirs {
    foreach ($d in @($ServicesDir, $LogDir, (Join-Path $WinVPSDir 'tmp'))) {
        if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
    }
}

# --- Config Loading ---
function Load-Config {
    if (Test-Path $ConfigFile) {
        Get-Content $ConfigFile -ErrorAction SilentlyContinue | Where-Object { $_ -match '^\w+=' } | ForEach-Object {
            $key, $val = $_ -split '=', 2
            $val = $val.Trim('"').Trim("'")
            Set-Item -Path "env:WINVPS_$($key.ToUpper().Replace('WINVPS_',''))" -Value $val -ErrorAction SilentlyContinue
        }
    }
}

# --- Service Definitions (from services.conf) ---
function Get-ServiceDefinitions {
    $services = [System.Collections.ArrayList]::new()

    # Core services always exist
    $coreServices = @(
        @{ Name='ssh';     Script='ssh.ps1';      Type='ps'; Port=7022; AutoStart=$false; HealthCheck='';  DependsOn=''; Description='OpenSSH server (start manually)' },
        @{ Name='web';     Script='httpd.ps1';     Type='ps'; Port=7080; AutoStart=$false; HealthCheck='';  DependsOn=''; Description='Web dashboard (localhost only)' },
        @{ Name='fail2ban';Script='fail2ban.ps1';  Type='ps'; Port=0;    AutoStart=$false; HealthCheck='';  DependsOn=''; Description='Brute-force protection' }
    )

    foreach ($cs in $coreServices) {
        [void]$services.Add([PSCustomObject]@{
            Name        = $cs.Name
            Script      = Join-Path $SrcDir $cs.Script
            Type        = $cs.Type
            Port        = $cs.Port
            AutoStart   = $cs.AutoStart
            HealthCheck = $cs.HealthCheck
            DependsOn   = $cs.DependsOn
            Description = $cs.Description
        })
    }

    # Load from services.conf
    if (Test-Path $ServicesConf) {
        Get-Content $ServicesConf -ErrorAction SilentlyContinue | ForEach-Object {
            $line = $_.Trim()
            if ($line -eq '' -or $line.StartsWith('#')) { return }
            $parts = $line -split '\|', -1
            if ($parts.Count -ge 2) {
                $name        = $parts[0].Trim()
                $script      = $parts[1].Trim()
                $type        = if ($parts.Count -ge 3 -and $parts[2].Trim()) { $parts[2].Trim() } else { 'auto' }
                $port        = if ($parts.Count -ge 4 -and $parts[3].Trim()) { [int]$parts[3].Trim() } else { 0 }
                $autoStart   = if ($parts.Count -ge 5 -and $parts[4].Trim()) { [bool]::Parse($parts[4].Trim()) } else { $false }
                $healthCheck = if ($parts.Count -ge 6) { $parts[5].Trim() } else { '' }
                $dependsOn   = if ($parts.Count -ge 7) { $parts[6].Trim() } else { '' }
                $description = if ($parts.Count -ge 8) { $parts[7].Trim() } else { '' }

                # Auto-detect type from file extension
                if ($type -eq 'auto' -and $script) {
                    $ext = [System.IO.Path]::GetExtension($script).ToLower()
                    $type = switch ($ext) {
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
                }

                # Resolve script path
                if ($script -and -not [System.IO.Path]::IsPathRooted($script)) {
                    $script = Join-Path $WinVPSDir $script
                }

                [void]$services.Add([PSCustomObject]@{
                    Name        = $name
                    Script      = $script
                    Type        = $type
                    Port        = $port
                    AutoStart   = $autoStart
                    HealthCheck = $healthCheck
                    DependsOn   = $dependsOn
                    Description = $description
                })
            }
        }
    }

    return $services
}

# --- PID Management ---
function Get-PidFile($name) { Join-Path $ServicesDir "$name.pid" }

function Test-ServiceRunning($name) {
    $pidFile = Get-PidFile $name
    if (-not (Test-Path $pidFile)) { return $false }
    $pid = [int](Get-Content $pidFile -ErrorAction SilentlyContinue)
    if ($pid -le 0) { return $false }
    $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
    return ($null -ne $proc)
}

function Get-ServicePid($name) {
    $pidFile = Get-PidFile $name
    if (-not (Test-Path $pidFile)) { return 0 }
    return [int](Get-Content $pidFile -ErrorAction SilentlyContinue)
}

# --- Dependency Resolution ---
function Get-StartOrder {
    param([string[]]$ServiceNames, [hashtable]$ServiceMap)

    $resolved = [System.Collections.ArrayList]::new()
    $visited  = @{}

    function Visit($name) {
        if ($visited[$name]) { return }
        $visited[$name] = $true
        $svc = $ServiceMap[$name]
        if ($svc -and $svc.DependsOn) {
            foreach ($dep in ($svc.DependsOn -split ',')) {
                $dep = $dep.Trim()
                if ($dep -and $ServiceMap[$dep]) { Visit $dep }
            }
        }
        [void]$resolved.Add($name)
    }

    foreach ($n in $ServiceNames) { Visit $n }
    return $resolved
}

# --- Service Start (unified) ---
function Start-ServiceByName {
    param(
        [string]$Name,
        [switch]$Force
    )

    $services = Get-ServiceDefinitions
    $svc = $services | Where-Object { $_.Name -eq $Name }
    if (-not $svc) {
        Err "Service '$Name' not found"
        return $false
    }

    $pidFile = Get-PidFile $Name
    $logFile = Join-Path $LogDir "$Name.log"

    if ((Test-ServiceRunning $Name) -and -not $Force) {
        $pid = Get-ServicePid $Name
        Log "$Name already running (PID $pid)"
        return $true
    }

    if (Test-Path $pidFile) { Remove-Item $pidFile -Force -ErrorAction SilentlyContinue }

    # Resolve dependencies first
    if ($svc.DependsOn) {
        foreach ($dep in ($svc.DependsOn -split ',')) {
            $dep = $dep.Trim()
            if ($dep -and -not (Test-ServiceRunning $dep)) {
                Log "Starting dependency: $dep"
                Start-ServiceByName -Name $dep | Out-Null
            }
        }
    }

    # Build launch command based on type
    $launchInfo = Get-LaunchCommand -Service $svc
    if (-not $launchInfo) {
        Err "Cannot determine how to launch '$Name'"
        return $false
    }

    try {
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = $launchInfo.File
        $pinfo.Arguments = $launchInfo.Args
        $pinfo.UseShellExecute = $false
        $pinfo.CreateNoWindow = $true
        $pinfo.RedirectStandardOutput = $true
        $pinfo.RedirectStandardError = $true
        $proc = [System.Diagnostics.Process]::Start($pinfo)
        $proc.Id | Out-File -FilePath $pidFile -Encoding ascii -Force
        Start-Sleep -Seconds 2
        if (-not $proc.HasExited) {
            Log "$Name started (PID $($proc.Id), type=$($svc.Type))"
            return $true
        } else {
            Warn "$Name exited immediately (code $($proc.ExitCode))"
            Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
            return $false
        }
    } catch {
        Warn "$Name failed to start: $_"
        return $false
    }
}

# --- Stop Service (unified) ---
function Stop-ServiceByName {
    param([string]$Name, [switch]$Graceful)

    $pidFile = Get-PidFile $Name
    if (-not (Test-Path $pidFile)) {
        Warn "$Name not running"
        return
    }

    $pid = [int](Get-Content $pidFile -ErrorAction SilentlyContinue)
    if ($pid -gt 0) {
        $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
        if ($proc) {
            try {
                if ($Graceful) {
                    # Try graceful shutdown first
                    $proc.CloseMainWindow() | Out-Null
                    $waited = 0
                    while (-not $proc.HasExited -and $waited -lt 5) {
                        Start-Sleep -Seconds 1
                        $waited++
                    }
                }
                if (-not $proc.HasExited) {
                    $proc.Kill()
                }
                Start-Sleep -Milliseconds 500
                Log "$Name stopped (PID $pid)"
            } catch {
                Warn "Could not stop $Name : $_"
            }
        }
    }
    Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
}

# --- Start All ---
function Start-AllServices {
    Log "Starting all services..."
    $services = Get-ServiceDefinitions
    $serviceMap = @{}
    foreach ($s in $services) { $serviceMap[$s.Name] = $s }

    $toStart = $services | Where-Object { $_.AutoStart } | ForEach-Object { $_.Name }
    $order = Get-StartOrder -ServiceNames $toStart -ServiceMap $serviceMap

    $running = 0
    foreach ($name in $order) {
        if (Start-ServiceByName -Name $name) { $running++ }
    }
    Log "Supervisor active - $running/$($services.Count) services running"
}

# --- Stop All ---
function Stop-AllServices {
    Log "Stopping all services..."
    Get-ChildItem -Path $ServicesDir -Filter '*.pid' -ErrorAction SilentlyContinue | ForEach-Object {
        Stop-ServiceByName -Name $_.BaseName -Graceful
    }
    Log "All services stopped"
}

# --- List Services ---
function Show-ServiceList {
    $services = Get-ServiceDefinitions
    Write-Host ''
    Write-Host "  ${Bold}Services${NC} ($($services.Count) registered)"
    Write-Host "  $($Dim)---${NC}"

    foreach ($svc in $services) {
        $running = Test-ServiceRunning $svc.Name
        $statusIcon = if ($running) { "${Green}*${NC}" } else { "${Red}o${NC}" }
        $statusText = if ($running) { "${Green}running${NC}" } else { "${Red}stopped${NC}" }
        $mem = ''
        if ($running) {
            $pid = Get-ServicePid $svc.Name
            $proc = Get-Process -Id $pid -ErrorAction SilentlyContinue
            if ($proc) { $mem = "$([math]::Round($proc.WorkingSet64 / 1MB, 1))MB" }
        }
        $port = if ($svc.Port -gt 0) { ":$($svc.Port)" } else { '' }
        $deps = if ($svc.DependsOn) { " ${Dim}<- $($svc.DependsOn)${NC}" } else { '' }
        Write-Host "  $statusIcon ${Bold}$($svc.Name)${NC} ${Dim}$($svc.Type)$NC $port $statusText $mem$deps"
    }
    Write-Host ''
}

# --- Show Status ---
function Show-Status {
    $services = Get-ServiceDefinitions
    $running = 0
    foreach ($svc in $services) {
        if (Test-ServiceRunning $svc.Name) {
            $pid = Get-ServicePid $svc.Name
            $mem = (Get-Process -Id $pid -ErrorAction SilentlyContinue).WorkingSet64 / 1MB
            Log "$($svc.Name) is running (PID $pid, $([math]::Round($mem,1))MB)"
            $running++
        } else {
            Warn "$($svc.Name) is stopped"
        }
    }
    Write-Host "  Services: $running/$($services.Count) running"
}

# --- Add Service ---
function Add-Service {
    param(
        [string]$Name,
        [string]$Script,
        [string]$Type = 'auto',
        [int]$Port = 0,
        [bool]$AutoStart = $false,
        [string]$HealthCheck = '',
        [string]$DependsOn = '',
        [string]$Description = ''
    )

    # Validate
    if (-not $Name -or -not $Script) {
        Err "Name and Script are required"
        return
    }

    # Check if service already exists
    $existing = Get-ServiceDefinitions | Where-Object { $_.Name -eq $Name }
    if ($existing) {
        Err "Service '$Name' already exists"
        return
    }

    # Auto-detect type
    if ($Type -eq 'auto') {
        $ext = [System.IO.Path]::GetExtension($Script).ToLower()
        $Type = switch ($ext) {
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
    }

    # Build line
    $line = "$Name|$Script|$Type|$Port|$AutoStart|$HealthCheck|$DependsOn|$Description"

    # Ensure services.conf exists
    if (-not (Test-Path $ServicesConf)) {
        "# WinVPS Service Definitions`n" | Out-File -FilePath $ServicesConf -Encoding ascii
    }

    Add-Content -Path $ServicesConf -Value $line -Encoding ascii
    Log "Added service: $Name (type=$Type, port=$Port)"
}

# --- Remove Service ---
function Remove-Service {
    param([string]$Name)

    if (-not $Name) {
        Err "Service name required"
        return
    }

    # Stop if running
    if (Test-ServiceRunning $Name) {
        Stop-ServiceByName -Name $Name
    }

    # Remove from services.conf
    if (Test-Path $ServicesConf) {
        $lines = Get-Content $ServicesConf -Encoding ascii
        $filtered = $lines | Where-Object { $_ -notmatch "^\Q$Name\E\|" }
        $filtered | Out-File -FilePath $ServicesConf -Encoding ascii -Force
        Log "Removed '$Name' from services.conf"
    }

    # Clean up PID and log files
    $pidFile = Get-PidFile $Name
    if (Test-Path $pidFile) { Remove-Item $pidFile -Force -ErrorAction SilentlyContinue }
    $logFile = Join-Path $LogDir "$Name.log"
    if (Test-Path $logFile) { Remove-Item $logFile -Force -ErrorAction SilentlyContinue }
    Log "Service '$Name' removed"
}

# --- Launch Command Builder ---
function Get-LaunchCommand {
    param([PSCustomObject]$Service)

    $script = $Service.Script
    $type   = $Service.Type

    switch ($type) {
        'ps' {
            return @{
                File = 'powershell.exe'
                Args = "-NoProfile -NonInteractive -ExecutionPolicy Bypass -File `"$script`" start"
            }
        }
        'cmd' {
            return @{
                File = 'cmd.exe'
                Args = "/c `"$script`""
            }
        }
        'node' {
            $nodePath = Get-Command node -ErrorAction SilentlyContinue
            if (-not $nodePath) {
                Warn "Node.js not found in PATH"
                return $null
            }
            return @{
                File = 'node.exe'
                Args = "`"$script`""
            }
        }
        'python' {
            $pythonPath = Get-Command python -ErrorAction SilentlyContinue
            if (-not $pythonPath) {
                $pythonPath = Get-Command python3 -ErrorAction SilentlyContinue
            }
            if (-not $pythonPath) {
                Warn "Python not found in PATH"
                return $null
            }
            $cmd = if ($pythonPath) { $pythonPath.Source } else { 'python.exe' }
            return @{
                File = $cmd
                Args = "`"$script`""
            }
        }
        'go' {
            $goPath = Get-Command go -ErrorAction SilentlyContinue
            if (-not $goPath) {
                Warn "Go not found in PATH"
                return $null
            }
            return @{
                File = 'go.exe'
                Args = "run `"$script`""
            }
        }
        'dotnet' {
            $dotnetPath = Get-Command dotnet -ErrorAction SilentlyContinue
            if (-not $dotnetPath) {
                Warn ".NET SDK not found in PATH"
                return $null
            }
            return @{
                File = 'dotnet.exe'
                Args = "run --project `"$script`""
            }
        }
        'docker' {
            $dockerPath = Get-Command docker -ErrorAction SilentlyContinue
            if (-not $dockerPath) {
                Warn "Docker not found in PATH"
                return $null
            }
            $dir = Split-Path $script -Parent
            return @{
                File = 'docker.exe'
                Args = "compose -f `"$script`" up -d"
            }
        }
        default {
            # Fallback: try running directly
            return @{
                File = $script
                Args = ''
            }
        }
    }
}

# --- Health Check ---
function Test-ServiceHealth {
    param([string]$HealthCheck)

    if (-not $HealthCheck) { return $true }

    if ($HealthCheck -match '^\d+$') {
        # TCP port check
        $port = [int]$HealthCheck
        $conn = Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue
        return ($null -ne $conn)
    } elseif ($HealthCheck -match '^https?://') {
        # HTTP health check
        try {
            $response = Invoke-WebRequest -Uri $HealthCheck -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
            return ($response.StatusCode -eq 200)
        } catch {
            return $false
        }
    }

    return $true
}

# --- Watchdog with backoff ---
function Invoke-Watchdog {
    $backoff = 1
    $maxBackoff = 60
    $restartCount = @{}

    $wdInterval = if ($env:WINVPS_WATCHDOG_INTERVAL) { $env:WINVPS_WATCHDOG_INTERVAL } else { 30 }
    Log "Watchdog started - monitoring every ${wdInterval}s"
    while ($true) {
        $interval = if ($env:WINVPS_WATCHDOG_INTERVAL) { [int]$env:WINVPS_WATCHDOG_INTERVAL } else { 30 }
        $services = Get-ServiceDefinitions
        foreach ($svc in $services) {
            $running = Test-ServiceRunning $svc.Name
            if (-not $running) {
                # Check restart count
                if (-not $restartCount.ContainsKey($svc.Name)) { $restartCount[$svc.Name] = 0 }
                if ($restartCount[$svc.Name] -ge 5) {
                    Err "$($svc.Name) failed to restart 5 times - skipping"
                    continue
                }

                Warn "$($svc.Name) crashed - restarting (attempt $($restartCount[$svc.Name] + 1))"
                $pidFile = Get-PidFile $svc.Name
                if (Test-Path $pidFile) { Remove-Item $pidFile -Force }
                Start-Sleep -Seconds $backoff
                if (Start-ServiceByName -Name $svc.Name) {
                    $restartCount[$svc.Name] = 0
                    $backoff = 1
                } else {
                    $restartCount[$svc.Name]++
                    $backoff = [math]::Min($backoff * 2, $maxBackoff)
                }
            } else {
                # Check health
                if ($svc.HealthCheck -and -not (Test-ServiceHealth $svc.HealthCheck)) {
                    Warn "$($svc.Name) health check failed"
                    Stop-ServiceByName -Name $svc.Name
                }
            }
        }
        Start-Sleep -Seconds $interval
    }
}

# --- Main ---
Ensure-Dirs
Load-Config

switch ($Action) {
    'start' {
        if ($ServiceName) {
            Start-ServiceByName -Name $ServiceName
            if ($Watchdog) { Invoke-Watchdog }
        } else {
            Start-AllServices
            if ($Watchdog) { Invoke-Watchdog }
        }
    }
    'stop' {
        if ($ServiceName) {
            Stop-ServiceByName -Name $ServiceName
        } else {
            Stop-AllServices
        }
    }
    'restart' {
        if ($ServiceName) {
            Stop-ServiceByName -Name $ServiceName
            Start-Sleep -Seconds 2
            Start-ServiceByName -Name $ServiceName
        } else {
            Stop-AllServices
            Start-Sleep -Seconds 2
            Start-AllServices
        }
    }
    'status'   { Show-Status }
    'list'     { Show-ServiceList }
    'watchdog' { Start-AllServices; Invoke-Watchdog }
    'add'      {
        Add-Service -Name $ServiceName -Script $ScriptPath -Type $Type -Port $Port -AutoStart $AutoStart -HealthCheck $HealthCheck -DependsOn $DependsOn -Description $Description
    }
    'remove'   { Remove-Service -Name $ServiceName }
    default    { Write-Host "Usage: supervisor.ps1 {start|stop|restart|status|list|watchdog|add|remove}" }
}
