#Requires -Version 5.1
<#
.SYNOPSIS
    WinVPS Project Setup — one-shot bootstrapper for any project.
.DESCRIPTION
    Installs prerequisites, clones repos, detects project type, installs dependencies,
    registers as a WinVPS service, starts it, and optionally exposes via tunnel.
.PARAMETER RepoUrl
    Git URL to clone (optional if providing local path).
.PARAMETER Name
    Service name.
.PARAMETER Path
    Local project path (optional if providing RepoUrl).
.PARAMETER Port
    Listening port.
.PARAMETER Type
    Service type: auto, node, python, go, dotnet, ps, cmd, docker, custom.
.PARAMETER AutoStart
    Auto-start on boot.
.PARAMETER HealthCheck
    Health check URL.
.PARAMETER DependsOn
    Comma-separated service dependencies.
.PARAMETER Description
    Human-readable description.
.PARAMETER Tailscale
    Expose via Tailscale Funnel.
.PARAMETER Cloudflare
    Expose via Cloudflare Tunnel.
.PARAMETER DryRun
    Show what would be done without doing it.
.EXAMPLE
    .\Setup-Project.ps1 -RepoUrl "https://github.com/user/app" -Name "myapp" -Port 3000
.EXAMPLE
    .\Setup-Project.ps1 -Path "D:\projects\api" -Name "api" -Type python -Port 8000 -AutoStart
#>
param(
    [string]$RepoUrl = '',
    [string]$Name = '',
    [string]$Path = '',
    [int]$Port = 0,
    [string]$Type = 'auto',
    [switch]$AutoStart,
    [string]$HealthCheck = '',
    [string]$DependsOn = '',
    [string]$Description = '',
    [switch]$Tailscale,
    [switch]$Cloudflare,
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$WinVPSDir = $env:WINVPS_DIR; if (-not $WinVPSDir) { $WinVPSDir = 'C:\WinVPS' }
$SvcMgr    = Join-Path $WinVPSDir 'src\core\service-manager.ps1'

$Green  = "`e[38;5;114m"
$Yellow = "`e[38;5;221m"
$Red    = "`e[38;5;203m"
$Cyan   = "`e[38;5;75m"
$Dim    = "`e[38;5;243m"
$Bold   = "`e[1m"
$NC     = "`e[0m"

function Step($msg)  { Write-Host "${Cyan}[setup]${NC} $msg" }
function Ok($msg)    { Write-Host "${Green}[  ok]${NC} $msg" }
function Warn($msg)  { Write-Host "${Yellow}[warn]${NC} $msg" }
function Fail($msg)  { Write-Host "${Red}[fail]${NC} $msg" }

# --- Interactive prompts if no Name ---
if (-not $Name) {
    Write-Host ''
    Write-Host "  ${Bold}WinVPS Project Setup${NC}"
    Write-Host "  ${Dim}──────────────────────────────────────────${NC}"
    Write-Host ''
    $Name = Read-Host "  Service name"
    if (-not $Name) { Fail "Name required"; exit 1 }

    $Path = Read-Host "  Project path (or leave empty to clone from URL)"
    if (-not $Path) {
        $RepoUrl = Read-Host "  Git URL to clone"
        if (-not $RepoUrl) { Fail "Path or URL required"; exit 1 }
    }

    $PortInput = Read-Host "  Port [0]"
    $Port = if ($PortInput) { [int]$PortInput } else { 0 }

    $AutoStartInput = Read-Host "  Auto-start on boot? [y/N]"
    $AutoStart = ($AutoStartInput -eq 'y' -or $AutoStartInput -eq 'Y')
}

Write-Host ''
Write-Host "  ${Bold}WinVPS Project Setup${NC}"
Write-Host "  ${Dim}──────────────────────────────────────────${NC}"
Write-Host ''
Write-Host "  Name:      ${Bold}$Name${NC}"
Write-Host "  Path:      $Path"
Write-Host "  Repo:      $RepoUrl"
Write-Host "  Port:      $Port"
Write-Host "  Type:      $Type"
Write-Host "  Auto:      $AutoStart"
Write-Host "  Health:    $HealthCheck"
Write-Host "  Depends:   $DependsOn"
Write-Host "  Tailscale: $Tailscale"
Write-Host ''

if ($DryRun) {
    Write-Host "  ${Dim}(dry run — no changes will be made)${NC}"
    Write-Host ''
}

# --- Step 1: Clone if needed ---
if ($RepoUrl -and -not $Path) {
    Step "Cloning $RepoUrl..."
    if (-not $DryRun) {
        $cloneDir = Join-Path $WinVPSDir "projects\$Name"
        if (Test-Path $cloneDir) {
            Warn "Directory already exists: $cloneDir"
        } else {
            git clone $RepoUrl $cloneDir 2>&1
            if ($LASTEXITCODE -ne 0) { Fail "Git clone failed"; exit 1 }
        }
        $Path = $cloneDir
    }
    Ok "Repository cloned to $Path"
}

# --- Step 2: Detect project type ---
if ($Type -eq 'auto' -and $Path) {
    Step "Detecting project type..."
    if (Test-Path (Join-Path $Path 'package.json')) { $Type = 'node' }
    elseif (Test-Path (Join-Path $Path 'requirements.txt')) { $Type = 'python' }
    elseif (Test-Path (Join-Path $Path 'pyproject.toml')) { $Type = 'python' }
    elseif (Test-Path (Join-Path $Path 'go.mod')) { $Type = 'go' }
    elseif (Test-Path (Join-Path $Path '*.csproj')) { $Type = 'dotnet' }
    elseif (Test-Path (Join-Path $Path 'Dockerfile')) { $Type = 'docker' }
    else {
        # Detect by extension
        $ext = [System.IO.Path]::GetExtension((Get-ChildItem -Path $Path -File -Recurse -Include *.js,*.py,*.go,*.ps1 | Select-Object -First 1).Name)
        $Type = switch ($ext) { '.js' { 'node' } '.py' { 'python' } '.go' { 'go' } '.ps1' { 'ps' } default { 'ps' } }
    }
    Ok "Detected type: $Type"
}

# --- Step 3: Detect entry point ---
if ($Path -and -not $ScriptPath) {
    Step "Detecting entry point..."
    $candidates = switch ($Type) {
        'node'   { @('index.js', 'server.js', 'app.js', 'main.js', 'src/index.js', 'src/server.js') }
        'python' { @('main.py', 'app.py', 'server.py', 'manage.py', 'src/main.py') }
        'go'     { @('main.go', 'cmd/main.go', 'cmd/server/main.go') }
        'dotnet' { Get-ChildItem -Path $Path -Filter '*.csproj' | Select-Object -ExpandProperty Name }
        default  { @('main.ps1', 'start.ps1', 'run.ps1', 'server.ps1') }
    }
    foreach ($c in $candidates) {
        $fullPath = Join-Path $Path $c
        if (Test-Path $fullPath) { $ScriptPath = $fullPath; break }
    }
    if ($ScriptPath) {
        Ok "Entry point: $ScriptPath"
    } else {
        Warn "Could not auto-detect entry point — you may need to set it manually"
    }
}

# --- Step 4: Install prerequisites ---
Step "Checking prerequisites..."
$prereqs = @()

switch ($Type) {
    'node' {
        $node = Get-Command node -ErrorAction SilentlyContinue
        if (-not $node) { $prereqs += 'OpenJS.NodeJS' }
    }
    'python' {
        $python = Get-Command python -ErrorAction SilentlyContinue
        if (-not $python) { $prereqs += 'Python.Python.3.12' }
    }
    'go' {
        $go = Get-Command go -ErrorAction SilentlyContinue
        if (-not $go) { $prereqs += 'GoLang.Go' }
    }
    'dotnet' {
        $dotnet = Get-Command dotnet -ErrorAction SilentlyContinue
        if (-not $dotnet) { $prereqs += 'Microsoft.DotNet.SDK.8' }
    }
}

foreach ($p in $prereqs) {
    Step "Installing $p via winget..."
    if (-not $DryRun) {
        winget install $p --accept-package-agreements --accept-source-agreements 2>&1
    }
    Ok "$p installed"
}

# --- Step 5: Install project dependencies ---
if ($Path -and -not $DryRun) {
    Step "Installing project dependencies..."
    Push-Location $Path
    switch ($Type) {
        'node'   { if (Test-Path 'package.json') { npm install 2>&1 } }
        'python' { if (Test-Path 'requirements.txt') { pip install -r requirements.txt 2>&1 } elseif (Test-Path 'pyproject.toml') { pip install -e . 2>&1 } }
        'go'     { go mod download 2>&1 }
        'dotnet' { dotnet restore 2>&1 }
    }
    Pop-Location
    Ok "Dependencies installed"
}

# --- Step 6: Register service ---
if (-not $DryRun -and $ScriptPath) {
    Step "Registering service..."
    & powershell -NoProfile -ExecutionPolicy Bypass -File $SvcMgr add `
        -ServiceName $Name -ScriptPath $ScriptPath -Type $Type -Port $Port `
        -AutoStart $AutoStart -HealthCheck $HealthCheck -DependsOn $DependsOn -Description $Description
    Ok "Service '$Name' registered"
}

# --- Step 7: Start service ---
if (-not $DryRun) {
    Step "Starting service..."
    & powershell -NoProfile -ExecutionPolicy Bypass -File $SvcMgr start -ServiceName $Name
    Ok "Service '$Name' started"
}

# --- Step 8: Start tunnel if requested ---
if ($Tailscale -and -not $DryRun) {
    Step "Starting Tailscale Funnel..."
    $tunnelMgr = Join-Path $WinVPSDir 'src\tunnels\tunnel-manager.ps1'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $tunnelMgr start tailscale
    Ok "Tailscale Funnel active"
}

if ($Cloudflare -and -not $DryRun) {
    Step "Starting Cloudflare tunnel..."
    $tunnelMgr = Join-Path $WinVPSDir 'src\tunnels\tunnel-manager.ps1'
    & powershell -NoProfile -ExecutionPolicy Bypass -File $tunnelMgr start cloudflare
    Ok "Cloudflare tunnel active"
}

# --- Summary ---
Write-Host ''
Write-Host "  ${Bold}${Green}Setup Complete!${NC}"
Write-Host "  ${Dim}──────────────────────────────────────────${NC}"
Write-Host ''
Write-Host "  Service:  ${Bold}$Name${NC}"
if ($Port) { Write-Host "  Local:    http://localhost:$Port" }
Write-Host "  Logs:     winvps logs $Name"
Write-Host "  Status:   winvps service detail $Name"
Write-Host "  Health:   winvps service health $Name"
Write-Host "  Stop:     winvps service stop $Name"
Write-Host "  Remove:   winvps service remove $Name"
Write-Host ''
