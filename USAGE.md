# WinVPS Usage Guide

> Complete reference for every command, feature, and workflow in WinVPS v2.0.

---

## Table of Contents

- [Getting Started](#getting-started)
- [Service Management](#service-management)
- [Project Setup](#project-setup)
- [Natural Language Shell](#natural-language-shell)
- [System Monitoring](#system-monitoring)
- [Tunnels & Remote Access](#tunnels--remote-access)
- [Security](#security)
- [Backup & Recovery](#backup--recovery)
- [Configuration](#configuration)
- [Web Dashboard](#web-dashboard)
- [API Reference](#api-reference)
- [Telegram & Discord Bots](#telegram--discord-bots)
- [Troubleshooting](#troubleshooting)

---

## Getting Started

### Installation

```powershell
# Option 1: One-liner (Run as Administrator)
irm https://raw.githubusercontent.com/MrNova420/WinVPS/master/dist/winvps-portable.ps1 | iex

# Option 2: Clone + install
git clone https://github.com/MrNova420/WinVPS.git C:\WinVPS
cd C:\WinVPS
.\setup\Install-WinVPS.ps1
```

### First Steps

```powershell
# Check system status
winvps status

# Run diagnostics
winvps doctor

# Open the natural language shell
winvps shell

# Open the web dashboard
start http://localhost:7080
```

### What Gets Installed

| Component | Port | Description |
|-----------|------|-------------|
| OpenSSH Server | 7022 | Remote SSH access |
| Web Dashboard | 7080 | Browser-based management |
| Python Backend | - | API server for dashboard |
| Service Supervisor | - | Auto-healing process manager |
| Windows Firewall | - | Security rules |
| Task Scheduler | - | Auto-start on boot |

---

## Service Management

### Listing Services

```powershell
# List all registered services
winvps service list

# Detailed table with status, type, port, memory, health
# Output:
#   STATUS  NAME           TYPE     PORT   MEMORY   HEALTH
#   ●       ssh            ps       :7022  12.3MB   ✓
#   ●       web            ps       :7080  45.6MB   ✓
#   ○       fail2ban       ps       -      -        —
#   ●       my-app         node     :3000  89.2MB   ✓
```

### Adding Services

#### Interactive Mode

```powershell
winvps service add
# Prompts for:
#   Service name: my-app
#   Script path: D:\projects\app\server.js
#   Type: node (auto-detected)
#   Port: 3000
#   Auto-start: y
#   Health check: http://localhost:3000/health
#   Dependencies: redis,postgres
#   Description: My web application
```

#### Flag Mode

```powershell
winvps service add my-app "D:\projects\app\server.js" --port 3000 --type node --auto --health http://localhost:3000/health --depends redis,postgres --desc "My web app"
```

#### Supported Types

| Type | Extension | Runtime |
|------|-----------|---------|
| `node` | `.js`, `.mjs`, `.ts` | `node <script>` |
| `python` | `.py` | `python <script>` |
| `go` | `.go` | `go run <script>` |
| `dotnet` | `.csproj`, `.sln` | `dotnet run --project <path>` |
| `ps` | `.ps1` | `powershell -File <script>` |
| `cmd` | `.cmd`, `.bat` | `cmd /c <script>` |
| `docker` | `Dockerfile` | `docker compose up -d` |
| `auto` | any | Auto-detected from extension |

### Starting & Stopping

```powershell
winvps service start my-app
winvps service stop my-app
winvps service restart my-app
```

### Removing Services

```powershell
winvps service remove my-app
# Stops the service, removes from services.conf, cleans up files
```

### Service Details

```powershell
winvps service detail my-app
# Shows: status, config, resources, health, environment
```

### Health Checks

```powershell
# Run health check for a service
winvps service health my-app

# Supported check types:
#   HTTP: http://localhost:3000/health
#   TCP:  3306 (just a port number)
#   Auto: Falls back to process check
```

### Service Metrics

```powershell
# View resource usage
winvps service metrics my-app
# Returns: memory, CPU, disk, uptime, health status as JSON
```

### Dependency Graph

```powershell
# View service dependencies
winvps service deps

# Output:
#   Service Dependency Graph
#   ● ssh
#   ● web <-- fail2ban
#   ○ fail2ban
#   ● my-app <-- redis, postgres
#   ○ redis
#   ○ postgres
```

### Install Dependencies

```powershell
# Auto-install project dependencies based on type
winvps service install-deps my-app
# node: npm install
# python: pip install -r requirements.txt
# go: go mod download
# dotnet: dotnet restore
```

### Execute in Service Context

```powershell
# Run a command with the service's environment loaded
winvps service exec my-app "npm test"
winvps service exec my-app "python manage.py migrate"
```

### Service Logs

```powershell
# View logs for a service
winvps service logs my-app
winvps service logs my-app 200

# List all available log files
winvps service logs
```

### Service Backup & Restore

```powershell
# Backup service data, config, and environment
winvps service backup my-app

# Restore from latest backup
winvps service restore my-app
```

---

## Project Setup

### One-Shot Bootstrapper

The `Setup-Project.ps1` script handles everything from cloning to running:

```powershell
# Clone from Git and set up
.\setup\Setup-Project.ps1 -RepoUrl "https://github.com/user/app" -Name "myapp" -Port 3000

# Set up from local path
.\setup\Setup-Project.ps1 -Path "D:\projects\api" -Name "api" -Type python -Port 8000 -AutoStart

# Full setup with tunnel
.\setup\Setup-Project.ps1 -Path "D:\projects\web" -Name "web" -Port 3000 -Tailscale

# Dry run (show what would happen)
.\setup\Setup-Project.ps1 -Path "D:\projects\app" -Name "app" -DryRun
```

### What It Does

1. **Clones** the repository (if URL provided)
2. **Detects** project type (node, python, go, dotnet, etc.)
3. **Finds** the entry point (index.js, main.py, etc.)
4. **Installs** prerequisites via winget (Node.js, Python, Go, etc.)
5. **Installs** project dependencies (npm, pip, go mod, dotnet restore)
6. **Registers** as a WinVPS service
7. **Starts** the service
8. **Optionally** starts a tunnel for remote access

---

## Natural Language Shell

### Interactive Mode

```powershell
winvps shell
# You> how's my server doing
# You> start the web server
# You> show me recent ssh logs
# You> create a backup
# You> open a tunnel
# You> harden the server
# You> exit
```

### One-Shot Mode

```powershell
winvps shell "how's my server doing"
winvps shell "start the web server"
winvps shell "show ssh logs"
winvps shell "create a backup"
```

### What You Can Say

| You Say | WinVPS Runs |
|---------|-------------|
| `how's my server doing` | `winvps status` |
| `start the web server` | `winvps service start web` |
| `stop ssh` | `winvps service stop ssh` |
| `restart my-app` | `winvps service restart my-app` |
| `show me recent errors` | `winvps logs` |
| `show ssh logs` | `winvps logs ssh 50` |
| `run diagnostics` | `winvps doctor` |
| `create a backup` | `winvps backup create` |
| `open a tunnel` | `winvps tunnel start` |
| `harden the server` | `winvps security harden` |
| `start fail2ban` | `winvps fail2ban start` |
| `enable stealth mode` | `winvps stealth enable` |
| `show all config` | `winvps config show` |
| `what version is this` | `winvps version` |

---

## System Monitoring

### Live Monitor

```powershell
# Real-time CPU, memory, services (refreshes every 3s)
winvps monitor

# Custom refresh interval
winvps monitor 5
```

### System Status

```powershell
winvps status
# Shows: uptime, CPU, memory, services, network, security
```

### Diagnostics

```powershell
winvps doctor
# Checks: directories, config, PowerShell, OpenSSH, running services
```

---

## Tunnels & Remote Access

### Available Tunnels

| Tunnel | Type | Cost | Permanent URL |
|--------|------|------|---------------|
| **Tailscale Funnel** | Mesh VPN | Free | Yes |
| **Cloudflare** | CDN tunnel | Free | Yes |
| **ngrok** | Reverse proxy | Free/Paid | No (changes) |
| **bore** | TCP tunnel | Free | No (changes) |

### Tailscale Funnel (Recommended)

```powershell
# 1. Install Tailscale
winget install Tailscale.Tailscale

# 2. Connect
tailscale up

# 3. Start funnel
winvps tunnel start tailscale

# Your app is now at: https://your-hostname.tail-net.ts.net
```

### Cloudflare Tunnel

```powershell
# 1. Install cloudflared
winget install Cloudflare.cloudflared

# 2. Authenticate
cloudflared tunnel login

# 3. Create tunnel
cloudflared tunnel create winvps

# 4. Configure
winvps config set WINVPS_TUNNEL_TOKEN "your-token"

# 5. Start
winvps tunnel start cloudflare
```

### ngrok

```powershell
# 1. Install ngrok
winget install Ngrok.Ngrok

# 2. Configure
ngrok config add-authtoken YOUR_TOKEN

# 3. Start
winvps tunnel start ngrok
```

### Tunnel Management

```powershell
# Check tunnel status
winvps tunnel status

# Stop all tunnels
winvps tunnel stop

# Restart a specific tunnel
winvps tunnel restart cloudflare
```

---

## Security

### Security Hardening

```powershell
# Scan for issues
winvps security scan

# Apply hardening
winvps security harden

# Check status
winvps security status
```

### Fail2ban (Brute-Force Protection)

```powershell
winvps fail2ban start
winvps fail2ban stop
winvps fail2ban status
```

### Stealth Mode

```powershell
# Schedule when your machine is available
winvps stealth enable
winvps stealth disable
winvps stealth status
```

### Device Obfuscation

```powershell
# Randomize everything
winvps obfuscate all

# Specific items
winvps obfuscate hostname
winvps obfuscate ssh
winvps obfuscate mac
```

### Encrypted Storage

```powershell
winvps encrypt init
winvps encrypt unmount
winvps encrypt status
```

### Tamper Detection

```powershell
winvps tamper init
winvps tamper verify
winvps tamper status
```

### VPN Kill Switch

```powershell
winvps killswitch enable
winvps killswitch disable
winvps killswitch status
```

---

## Backup & Recovery

### Create Backups

```powershell
winvps backup create
# Creates timestamped zip of config + data
```

### List Backups

```powershell
winvps backup list
# Shows all backups with size and date
```

### Restore

```powershell
winvps backup restore
# Restores from latest backup
```

### Service-Specific Backup

```powershell
winvps service backup my-app
winvps service restore my-app
```

---

## Configuration

### View Config

```powershell
winvps config show
```

### Get/Set Values

```powershell
winvps config get WINVPS_SSH_PORT
winvps config set WINVPS_SSH_PORT 7022
winvps config set WINVPS_TAILSCALE_HOSTNAME "my-server"
```

### Load Profiles

```powershell
winvps config load minimal    # Minimal setup
winvps config load dev        # Development
winvps config load full       # Everything on
winvps config load hardened   # Security focused
winvps config load stealth    # Maximum stealth
```

### Key Configuration Options

| Key | Default | Description |
|-----|---------|-------------|
| `WINVPS_SSH_PORT` | 7022 | SSH port |
| `WINVPS_WEB_PORT` | 7080 | Dashboard port |
| `WINVPS_TIER` | auto | RAM tier (shadow/lite/standard/full) |
| `WINVPS_AUTO_UPDATE` | true | Auto-update WinVPS |
| `WINVPS_WATCHDOG` | true | Auto-restart crashed services |
| `WINVPS_TUNNEL_TYPE` | cloudflare | Default tunnel |
| `WINVPS_TAILSCALE_HOSTNAME` | - | Tailscale hostname for funnel |

---

## Web Dashboard

### Access

Open `http://localhost:7080` in your browser.

### Features

- **Overview** — CPU, memory, disk, services count, tunnel status
- **Services** — Start/stop/restart/remove services, add new services
- **Tunnels** — Start/stop tunnel providers
- **Logs** — View service logs with live tail
- **Configuration** — Edit settings in-browser
- **Storage** — Disk usage, backup management

### API Key Authentication

The dashboard auto-generates an API key on first run.

```powershell
# Get your API key
type C:\WinVPS\config\web-api.key

# Use with API calls
$key = Get-Content C:\WinVPS\config\web-api.key
Invoke-RestMethod -Uri http://localhost:7080/api/status -Headers @{Authorization="Bearer $key"}

# Rotate key
Invoke-RestMethod -Uri http://localhost:7080/api/apikey -Method POST -Headers @{Authorization="Bearer $key"}
```

---

## API Reference

### Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/status` | GET | System status |
| `/api/services` | GET | List all services |
| `/api/services/add` | POST | Add a service |
| `/api/services/:name/start` | POST | Start service |
| `/api/services/:name/stop` | POST | Stop service |
| `/api/services/:name/remove` | POST | Remove service |
| `/api/logs/:service` | GET | Get service logs |
| `/api/config` | GET/POST | Read/write config |
| `/api/health` | GET | Run health check |
| `/api/storage` | GET | Storage usage |
| `/api/backups` | GET | List backups |
| `/api/backup` | POST | Create backup |
| `/api/apikey` | GET/POST | Get/rotate API key |

### Example: Add Service via API

```powershell
$key = Get-Content C:\WinVPS\config\web-api.key
$body = @{
    name = "my-app"
    path = "D:\projects\app\server.js"
    type = "node"
    port = 3000
    auto_start = $true
} | ConvertTo-Json

Invoke-RestMethod -Uri http://localhost:7080/api/services/add `
    -Method POST `
    -Headers @{Authorization="Bearer $key"; "Content-Type"="application/json"} `
    -Body $body
```

---

## Telegram & Discord Bots

### Telegram Bot Setup

```powershell
# 1. Create bot with @BotFather
# 2. Set token
winvps config set WINVPS_TELEGRAM_BOT_TOKEN "YOUR_TOKEN"

# 3. Get chat ID from getUpdates
winvps config set WINVPS_TELEGRAM_CHAT_ID "YOUR_CHAT_ID"

# 4. Start bot
.\src\bots\shell-telegram.ps1 start
```

**Bot Commands:** `/status`, `/services`, `/health`, `/backup`, `/help`

### Discord Bot Setup

```powershell
# 1. Create bot at discord.com/developers
# 2. Set token and channel
winvps config set WINVPS_DISCORD_BOT_TOKEN "YOUR_TOKEN"
winvps config set WINVPS_DISCORD_CHANNEL_ID "YOUR_CHANNEL_ID"

# 3. Start bot
.\src\bots\shell-discord.ps1 start
```

**Bot Commands:** `!status`, `!health`, `!backup`, `!help`

---

## Troubleshooting

### Service Won't Start

```powershell
# Check logs
winvps service logs my-app

# Check status
winvps service detail my-app

# Check health
winvps service health my-app

# Try starting manually
winvps service exec my-app "node server.js"
```

### Dashboard Not Loading

```powershell
# Check if web service is running
winvps service list

# Check port
netstat -an | findstr 7080

# Restart web service
winvps service restart web
```

### SSH Not Working

```powershell
# Check SSH service
winvps service status ssh

# Check firewall
netsh advfirewall firewall show rule name="WinVPS SSH"

# Restart SSH
winvps service restart ssh
```

### Run Diagnostics

```powershell
winvps doctor
```

---

## RAM Tiers

| Tier | RAM | Description |
|------|-----|-------------|
| Shadow | ≤512MB | Ultra-light, SSH + minimal web only |
| Lite | ≤2GB | Core services only |
| Standard | ≤8GB | Balanced feature set |
| Full | >8GB | Everything enabled |

```powershell
winvps tier info
```
