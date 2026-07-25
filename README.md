<p align="center">
  <img src="https://img.shields.io/badge/version-2.0.0-blue?style=for-the-badge" alt="Version">
  <img src="https://img.shields.io/badge/license-MIT-green?style=for-the-badge" alt="License">
  <img src="https://img.shields.io/badge/powershell-5.1%2B-blue?style=for-the-badge" alt="PowerShell">
  <img src="https://img.shields.io/badge/platform-Windows-0078d4?style=for-the-badge" alt="Windows">
</p>

<h1 align="center">WinVPS</h1>

<p align="center">
  <strong>Turn any Windows machine into a self-managed, auto-healing, remotely accessible VPS.</strong>
</p>

<p align="center">
  Host any project — Node.js, Python, Go, .NET, Rust, Java, Docker — as a managed service<br>
  with one command. Monitor everything from a beautiful web dashboard.
</p>

---

## What is WinVPS?

WinVPS transforms a Windows PC into a production-grade VPS. Install it once, and your machine becomes a self-healing server that:

- **Manages any project** as a service with auto-restart, health checks, and dependency resolution
- **Exposes everything remotely** via Tailscale, Cloudflare, ngrok, or SSH
- **Heals itself** — crashed services restart automatically with exponential backoff
- **Monitors everything** — CPU, memory, disk, per-service metrics in a real-time dashboard
- **Secures itself** — fail2ban, firewall hardening, stealth mode, tamper detection

---

## Quick Start

### Install (Run PowerShell as Administrator)

```powershell
# One-liner
irm https://raw.githubusercontent.com/MrNova420/WinVPS/master/dist/winvps-portable.ps1 | iex

# Or clone + install
git clone https://github.com/MrNova420/WinVPS.git C:\WinVPS
cd C:\WinVPS
.\setup\Install-WinVPS.ps1
```

### Add Your First Project

```powershell
# From a local project
winvps service add my-app "D:\projects\my-app\server.js" --port 3000 --type node

# From a Git repo
.\setup\Setup-Project.ps1 -RepoUrl "https://github.com/user/app" -Name "myapp" -Port 3000

# Or use the interactive wizard
winvps service add
```

### Manage Everything

```powershell
winvps status                    # System overview
winvps service list              # All services
winvps service start my-app      # Start a service
winvps service stop my-app       # Stop a service
winvps service detail my-app     # Full service info
winvps service health my-app     # Health check
winvps service deps              # Dependency graph
winvps shell                     # Natural language interface
```

### Open the Dashboard

```
http://localhost:7080
```

---

## Features

### Service Management

Any project becomes a managed service with one command:

| Feature | Description |
|---------|-------------|
| **Multi-language** | Node.js, Python, Go, .NET, PowerShell, Docker, any executable |
| **Auto-detection** | Detects project type from file extension |
| **Dependency resolution** | Start services in correct order with `depends_on` |
| **Health checks** | HTTP endpoint, TCP port, or process-based checks |
| **Auto-restart** | Exponential backoff, max 5 attempts, then mark as failed |
| **Per-service env** | Isolated `.env` files for each service |
| **Metrics** | Memory, CPU, disk, uptime per service |
| **Backup/restore** | Per-service data backup and recovery |
| **Log management** | Isolated stdout/stderr logs with rotation |

```powershell
# Add any project
winvps service add api "D:\api\main.py" --port 8000 --type python --auto --health http://localhost:8000/docs

# View dependency graph
winvps service deps
#   ● ssh
#   ● web <-- fail2ban
#   ● api <-- redis, postgres
#   ○ redis
#   ○ postgres

# Run health check
winvps service health api
# healthy: HTTP 200 OK (latency: 45ms)
```

### Remote Access

Four tunnel providers for accessing your machine from anywhere:

| Provider | Cost | Permanent URL | Setup |
|----------|------|---------------|-------|
| **Tailscale Funnel** | Free | `https://your-host.tail.ts.net` | `tailscale up` + `winvps tunnel start tailscale` |
| **Cloudflare** | Free | `https://your-tunnel.trycloudflare.com` | `cloudflared tunnel create` |
| **ngrok** | Free/Paid | Changes each restart | `ngrok config add-authtoken TOKEN` |
| **bore** | Free | Changes each restart | Auto-downloaded |

### Natural Language Shell

Talk to your server in plain English:

```
You> how's my server doing
You> start the web server
You> show me recent ssh logs
You> create a backup
You> open a tunnel
You> harden the server
```

### Security Suite

| Tool | Description |
|------|-------------|
| **Fail2ban** | Brute-force protection with auto-banning |
| **Firewall** | Windows Firewall rules — **always asks before creating** |
| **Stealth Mode** | Schedule when your machine is available |
| **Obfuscation** | Randomize hostname, MAC, SSH keys, HTTP headers |
| **Tamper Detection** | File integrity monitoring with auto-wipe |
| **Encrypted Storage** | BitLocker-encrypted volumes |
| **VPN Kill Switch** | Block all traffic outside VPN |

### Web Dashboard

Beautiful, real-time dashboard at `http://localhost:7080` (binds localhost only — never exposed to network by default):

- **Overview** — CPU, memory, disk with progress bars
- **Services** — Start/stop/restart, add new services, health status
- **Tunnels** — Manage Tailscale, Cloudflare, ngrok, bore
- **Logs** — Live log viewer with search
- **Configuration** — Edit settings in-browser
- **Storage** — Disk usage, backup management

### One-Shot Project Bootstrapper

```powershell
# Clone + install + register + start — all in one command
.\setup\Setup-Project.ps1 -RepoUrl "https://github.com/user/app" -Name "myapp" -Port 3000 -Tailscale
```

Handles: Git clone, prerequisite installation (winget), dependency install, service registration, startup, and optional tunnel setup.

---

## Commands

### Core

| Command | Description |
|---------|-------------|
| `winvps status` | System overview |
| `winvps shell` | Natural language shell |
| `winvps service list` | List all services |
| `winvps service add` | Add a project as a service |
| `winvps service remove` | Remove a service |
| `winvps service start <name>` | Start a service |
| `winvps service stop <name>` | Stop a service |
| `winvps service restart <name>` | Restart a service |
| `winvps service detail <name>` | Full service info |
| `winvps service health <name>` | Health check |
| `winvps service metrics <name>` | Resource usage |
| `winvps service deps` | Dependency graph |
| `winvps service logs <name>` | View logs |
| `winvps service backup <name>` | Backup service data |
| `winvps service exec <name> "cmd"` | Execute in service context |
| `winvps monitor` | Live resource monitor |
| `winvps doctor` | Diagnostics |

### Networking

| Command | Description |
|---------|-------------|
| `winvps tunnel start tailscale` | Start Tailscale Funnel |
| `winvps tunnel start cloudflare` | Start Cloudflare tunnel |
| `winvps tunnel start ngrok` | Start ngrok tunnel |
| `winvps tunnel start bore` | Start bore tunnel |
| `winvps tunnel stop` | Stop all tunnels |
| `winvps tunnel status` | Tunnel status |

### Security

| Command | Description |
|---------|-------------|
| `winvps security harden` | Lock down SSH + firewall |
| `winvps fail2ban start` | Start brute-force protection |
| `winvps stealth enable` | Enable stealth mode |
| `winvps obfuscate all` | Randomize device identity |
| `winvps encrypt init` | Initialize encrypted storage |
| `winvps tamper init` | Initialize tamper detection |

### Data

| Command | Description |
|---------|-------------|
| `winvps backup create` | Create backup |
| `winvps backup list` | List backups |
| `winvps backup restore` | Restore latest |
| `winvps logs` | List log files |
| `winvps config show` | Show configuration |
| `winvps config set KEY VALUE` | Set config value |

See [USAGE.md](USAGE.md) for the complete reference.

---

## Architecture

```
C:\WinVPS\
├── src/
│   ├── cli/winvps.ps1              # Main CLI (25+ commands)
│   ├── core/
│   │   ├── service-manager.ps1     # Service lifecycle management
│   │   ├── supervisor.ps1          # Auto-healing process manager
│   │   └── ...                     # 17 core modules
│   ├── web/
│   │   ├── backend/main.py         # Python API server
│   │   └── frontend/               # Dashboard (HTML/CSS/JS)
│   ├── shell/                      # Natural language shell
│   ├── tunnels/tunnel-manager.ps1  # Tailscale/Cloudflare/ngrok/bore
│   └── bots/                       # Telegram/Discord bots
├── config/
│   ├── winvps.conf                 # Main configuration
│   ├── services.conf               # Service definitions
│   └── profiles/                   # Pre-configured profiles
├── services/                       # Per-service directories
│   └── <name>/
│       ├── service.conf            # Service config
│       ├── pid                     # Process ID
│       ├── .env                    # Environment variables
│       ├── data/                   # Persistent data
│       ├── logs/                   # stdout/stderr logs
│       └── secrets/                # Encrypted secrets
├── setup/
│   ├── Install-WinVPS.ps1          # Installer
│   ├── Setup-Project.ps1           # Project bootstrapper
│   └── Uninstall-WinVPS.ps1        # Uninstaller
└── dist/
    └── winvps-portable.ps1         # One-command installer
```

---

## Configuration

### Main Config (`config/winvps.conf`)

```ini
WINVPS_SSH_PORT=7022
WINVPS_WEB_PORT=7080
WINVPS_WEB_HOST="127.0.0.1"        # Dashboard bind address (never 0.0.0.0)
WINVPS_TIER="auto"
WINVPS_AUTO_UPDATE=true
WINVPS_WATCHDOG=true
WINVPS_TUNNEL_TYPE="cloudflare"
WINVPS_TAILSCALE_HOSTNAME=""
```

### Service Definitions (`config/services.conf`)

```
# name|script|type|port|auto_start|health_check|depends_on|description
# WARNING: auto_start is false by default — nothing starts or exposes ports without your consent
ssh|src/core/ssh.ps1|ps|7022|false|||OpenSSH server
web|src/core/httpd.ps1|ps|7080|false|||Web dashboard
```

### Per-Service Config (`services/<name>/service.conf`)

```ini
WINVPS_SVC_NAME=my-app
WINVPS_SVC_TYPE=node
WINVPS_SVC_PORT=3000
WINVPS_SVC_PID=12345
WINVPS_SVC_STARTED=2026-07-25 10:30:00
```

### Per-Service Environment (`services/<name>/.env`)

```
NODE_ENV=production
DATABASE_URL=postgresql://localhost:5432/mydb
SECRET_KEY=***
```

---

## RAM Tiers

WinVPS automatically detects your system's RAM and optimizes:

| Tier | RAM | Description |
|------|-----|-------------|
| **Shadow** | ≤512MB | Ultra-light, SSH + minimal web only |
| **Lite** | ≤2GB | Core services only |
| **Standard** | ≤8GB | Balanced feature set |
| **Full** | >8GB | Everything enabled |

```powershell
winvps tier info
```

---

## Web Dashboard

### API Key Authentication

Auto-generated on first run at `config/web-api.key`:

```powershell
# Get API key
type C:\WinVPS\config\web-api.key

# Use with API
$key = Get-Content C:\WinVPS\config\web-api.key
Invoke-RestMethod -Uri http://localhost:7080/api/status -Headers @{Authorization="Bearer $key"}
```

### API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/status` | GET | System status |
| `/api/services` | GET | List services |
| `/api/services/add` | POST | Add service |
| `/api/services/:name/start` | POST | Start service |
| `/api/services/:name/stop` | POST | Stop service |
| `/api/services/:name/remove` | POST | Remove service |
| `/api/logs/:service` | GET | Service logs |
| `/api/config` | GET/POST | Configuration |
| `/api/health` | GET | Health check |
| `/api/storage` | GET | Disk usage |
| `/api/backups` | GET | List backups |
| `/api/backup` | POST | Create backup |

---

## Telegram & Discord Bots

Manage your server from chat:

```powershell
# Telegram
winvps config set WINVPS_TELEGRAM_BOT_TOKEN "YOUR_TOKEN"
.\src\bots\shell-telegram.ps1 start

# Discord
winvps config set WINVPS_DISCORD_BOT_TOKEN "YOUR_TOKEN"
.\src\bots\shell-discord.ps1 start
```

---

## Profiles

Pre-configured profiles for different use cases:

```powershell
winvps config load minimal     # Minimal setup
winvps config load dev         # Development
winvps config load full        # Everything on
winvps config load hardened    # Security focused
winvps config load stealth     # Maximum stealth
winvps config load ghost       # Ultra-stealth, auto-wipe
```

---

## Security Model

WinVPS follows a **never-auto-expose, never-auto-elevate** philosophy:

| Behavior | Default | Why |
|----------|---------|-----|
| **Dashboard binding** | `127.0.0.1` (localhost only) | Never exposed to network without explicit opt-in |
| **Core services** | `auto_start=false` | Nothing runs or opens ports until you say so |
| **Firewall rules** | Interactive `y/N` prompt | You choose what gets opened |
| **Scheduled task** | Interactive `y/N` prompt | No boot persistence without consent |
| **Security harden** | Interactive `y/N` for firewall | You decide the lockdown level |

To expose the dashboard beyond localhost, set `WINVPS_WEB_HOST` in `config/winvps.conf`:

```powershell
winvps config set WINVPS_WEB_HOST "0.0.0.0"   # ⚠️ Exposes to all interfaces
winvps config set WINVPS_WEB_HOST "192.168.1.x"  # Expose to LAN only
```

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

---

## License

MIT — see [LICENSE](LICENSE)

---

<p align="center">
  <strong>Built with care for the home server community.</strong>
</p>
