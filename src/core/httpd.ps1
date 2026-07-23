#Requires -Version 5.1
<#
.SYNOPSIS
    WinVPS HTTP Server - serves the web dashboard and API.
.DESCRIPTION
    Runs the Python-based web API backend and serves static frontend files.
    Falls back to PowerShell HTTP listener if Python is unavailable.
#>
param(
    [Parameter(Position=0)]
    [ValidateSet('start','stop','restart','status')]
    [string]$Action = 'start'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$WinVPSDir = $env:WINVPS_DIR; if (-not $WinVPSDir) { $WinVPSDir = 'C:\WinVPS' }
$ServicesDir = Join-Path $WinVPSDir 'services'
$LogDir = Join-Path $WinVPSDir 'logs'
$ConfigFile = Join-Path $WinVPSDir 'config\winvps.conf'
$PidFile = Join-Path $ServicesDir 'web.pid'
$ApiPidFile = Join-Path $ServicesDir 'webapi.pid'
$LogFile = Join-Path $LogDir 'web.log'
$BackendScript = Join-Path $WinVPSDir 'src\web\backend\main.py'
$FrontendDir = Join-Path $WinVPSDir 'src\web\frontend'
$WwwDir = Join-Path $WinVPSDir 'data\sites\default'

if (-not (Test-Path $ServicesDir)) { New-Item -ItemType Directory -Path $ServicesDir -Force | Out-Null }
if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
if (-not (Test-Path $WwwDir)) { New-Item -ItemType Directory -Path $WwwDir -Force | Out-Null }

function Load-Port {
    $port = 7080
    if (Test-Path $ConfigFile) {
        $line = Get-Content $ConfigFile | Where-Object { $_ -match '^WINVPS_WEB_PORT=' }
        if ($line) { $port = [int]($line -split '=',2)[1].Trim('"') }
    }
    return $port
}

function Copy-Frontend {
    if (Test-Path $FrontendDir) {
        Copy-Item -Path "$FrontendDir\*" -Destination $WwwDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Test-Python {
    try {
        $ver = & python --version 2>&1
        if ($ver -match 'Python 3') { return 'python' }
    } catch {}
    try {
        $ver = & python3 --version 2>&1
        if ($ver -match 'Python 3') { return 'python3' }
    } catch {}
    return $null
}

function Start-Web {
    $port = Load-Port

    if (Test-Path $PidFile) {
        $oldPid = Get-Content $PidFile -ErrorAction SilentlyContinue
        if ($oldPid) {
            $proc = Get-Process -Id ([int]$oldPid) -ErrorAction SilentlyContinue
            if ($proc) {
                Write-Host "[web] Already running (PID $oldPid)"
                return
            }
        }
        Remove-Item $PidFile -Force
    }

    Copy-Frontend

    $python = Test-Python
    if ($python -and (Test-Path $BackendScript)) {
        Write-Host "[web] Starting Python API on port $port..."
        $env:ANVPS_WEB_PORT = $port
        $pinfo = New-Object System.Diagnostics.ProcessStartInfo
        $pinfo.FileName = $python
        $pinfo.Arguments = "`"$BackendScript`""
        $pinfo.UseShellExecute = $false
        $pinfo.CreateNoWindow = $true
        $pinfo.RedirectStandardOutput = $true
        $pinfo.RedirectStandardError = $true
        $proc = [System.Diagnostics.Process]::Start($pinfo)
        $proc.Id | Out-File -FilePath $ApiPidFile -Encoding ascii -Force
        Start-Sleep -Seconds 2
        if (-not $proc.HasExited) {
            $proc.Id | Out-File -FilePath $PidFile -Encoding ascii -Force
            Write-Host "[web] Dashboard running on http://0.0.0.0:$port (PID $($proc.Id))"
        } else {
            $err = $proc.StandardError.ReadToEnd()
            Write-Host "[web] Python API failed: $err"
        }
    } else {
        Write-Host "[web] Python not found - using PowerShell HTTP listener on port $port"
        Start-PowerShellHttpd -Port $port
    }
}

function Start-PowerShellHttpd {
    param([int]$Port = 7080)
    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add("http://+:$Port/")
    try {
        $listener.Start()
    } catch {
        Write-Host "[web] Cannot bind to port $Port - trying with netsh..."
        & netsh http add urlacl url="http://+:$Port/" user=Everyone 2>&1 | Out-Null
        $listener.Start()
    }

    $pid = $PID
    $pid | Out-File -FilePath $PidFile -Encoding ascii -Force
    Write-Host "[web] PowerShell HTTPD started on port $Port (PID $pid)"

    $job = {
        param($Listener, $WwwDir, $LogDir)
        while ($Listener.IsListening) {
            try {
                $ctx = $Listener.GetContext()
                $path = $ctx.Request.Url.AbsolutePath.TrimStart('/')
                if (-not $path) { $path = 'index.html' }
                $file = Join-Path $WwwDir $path
                if (Test-Path $file) {
                    $bytes = [IO.File]::ReadAllBytes($file)
                    $ext = [IO.Path]::GetExtension($file).ToLower()
                    $ct = switch ($ext) {
                        '.html' { 'text/html' }
                        '.css'  { 'text/css' }
                        '.js'   { 'application/javascript' }
                        '.json' { 'application/json' }
                        '.png'  { 'image/png' }
                        '.ico'  { 'image/x-icon' }
                        default { 'application/octet-stream' }
                    }
                    $ctx.Response.ContentType = $ct
                    $ctx.Response.ContentLength64 = $bytes.Length
                    $ctx.Response.StatusCode = 200
                    $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
                } else {
                    $fallback = Join-Path $WwwDir 'index.html'
                    if (Test-Path $fallback) {
                        $bytes = [IO.File]::ReadAllBytes($fallback)
                        $ctx.Response.ContentType = 'text/html'
                        $ctx.Response.ContentLength64 = $bytes.Length
                        $ctx.Response.OutputStream.Write($bytes, 0, $bytes.Length)
                    } else {
                        $ctx.Response.StatusCode = 404
                    }
                }
                $ctx.Response.Close()
            } catch {}
        }
    }
    Start-Job -ScriptBlock $job -ArgumentList $listener, $WwwDir, $LogDir | Out-Null
}

function Stop-Web {
    foreach ($pf in @($PidFile, $ApiPidFile)) {
        if (Test-Path $pf) {
            $pid = Get-Content $pf -ErrorAction SilentlyContinue
            if ($pid -and $pid -ne 'system') {
                Stop-Process -Id ([int]$pid) -Force -ErrorAction SilentlyContinue
            }
            Remove-Item $pf -Force
        }
    }
    Get-Process -Name 'python*' -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandLine -match 'main\.py' } |
        Stop-Process -Force -ErrorAction SilentlyContinue
    Get-Job | Where-Object { $_.State -eq 'Running' } | Stop-Job -ErrorAction SilentlyContinue
    Write-Host "[web] HTTPD stopped"
}

function Show-WebStatus {
    $running = $false
    if (Test-Path $PidFile) {
        $pid = Get-Content $PidFile -ErrorAction SilentlyContinue
        if ($pid) {
            $proc = Get-Process -Id ([int]$pid) -ErrorAction SilentlyContinue
            if ($proc) { $running = $true; Write-Host "[web] HTTPD running (PID $pid)" }
        }
    }
    if (-not $running) { Write-Host "[web] HTTPD stopped" }
}

switch ($Action) {
    'start'   { Start-Web }
    'stop'    { Stop-Web }
    'restart' { Stop-Web; Start-Sleep -Seconds 2; Start-Web }
    'status'  { Show-WebStatus }
}
