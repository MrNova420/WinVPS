# WinVPS

A Windows fork of [AnVPS](https://github.com/MrNova420/AnVPS) -- turn any Windows machine into a self-managed, auto-healing, remotely accessible VPS.

## Features

- **Service Supervisor** -- auto-restarts crashed services
- **System Health Monitoring** -- CPU, RAM, disk, network, temperature
- **Web Dashboard** -- dark-themed control panel at `http://localhost:7080`
- **Natural Language Shell** -- type what you want in plain English
- **Security Hardening** -- SSH lockdown, firewall, fail2ban
- **Auto-Updates** -- self-updating, package management
- **Backup System** -- timestamped compressed backups
- **Cloud Tunnels** -- Cloudflare, ngrok, bore, WireGuard for remote access
- **Tor Gateway** -- optional Tor hidden service support
- **Stealth Mode** -- scheduled availability, decoy services
- **Obfuscation** -- hostname, MAC, SSH key, HTTP header randomization
- **Tamper Detection** -- integrity checks with auto-wipe on failure
- **VPN Kill Switch** -- blocks all traffic outside VPN
- **Telegram/Discord Bots** -- remote management via chat
- **RAM Tiering** -- automatic optimization for 512MB to 16GB+

---

## Quick Start

### 1. Install (Run PowerShell as Administrator)

**One-liner:**
```powershell
irm https://raw.githubusercontent.com/MrNova420/WinVPS/master/dist/winvps-portable.ps1 | iex
```

**Or clone + install:**
```powershell
git clone https://github.com/MrNova420/WinVPS.git C:\WinVPS
cd C:\WinVPS
.\setup\Install-WinVPS.ps1
```

### 2. What it installs

- OpenSSH Server (port 7022)
- Python 3 (for web backend)
- WinVPS services and dashboard
- Windows Firewall rules
- Auto-start Task Scheduler entry

### 3. First login

```powershell
# Check everything is running
winvps status

# Run diagnostics
winvps doctor

# Open the natural language shell
winvps shell
```

### 4. Web dashboard

Open **http://localhost:7080** in your browser.

API key is auto-generated at `C:\WinVPS\config\web-api.key`.

---

## Natural Language Shell

The fastest way to use WinVPS. Type what you want in plain English.

```powershell
# Interactive mode - talk to WinVPS
winvps shell

# One-shot mode - ask and execute
winvps shell "how's my server doing"
winvps shell "start the web server"
winvps shell "show me recent ssh logs"
winvps shell "create a backup"
winvps shell "open a tunnel"
winvps shell "harden the server"
```

### How it works

```
  you> how's my server doing

  +-- Suggested Command --------------------------+
  |  winvps status                                |
  |  Show system status (CPU, RAM, disk, uptime)  |
  +-----------------------------------------------+

  Execute? [Y]es  [E]dit  [N]o  [S]kip
  > y
```

Type `?` for examples, `exit` to quit.

### What you can say

| Say this | WinVPS runs |
|----------|-------------|
| `how's my server doing` | `winvps status` |
| `start the web server` | `winvps service start web` |
| `stop ssh` | `winvps service stop ssh` |
| `restart the database` | `winvps service restart postgres` |
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

Works on Windows (PowerShell 5.1+/7+) and Linux (Bash).

---

## Commands

### Core

| Command | Description |
|---------|-------------|
| `winvps shell` | Natural language shell (ask in plain English) |
| `winvps status` | System overview (uptime, CPU, RAM, services, network) |
| `winvps service list` | List all available and running services |
| `winvps service start ssh` | Start a service |
| `winvps service stop web` | Stop a service |
| `winvps service restart ssh` | Restart a service |
| `winvps service setup` | Run initial service setup |
| `winvps monitor` | Live resource monitor (refreshes every 3s) |
| `winvps monitor 5` | Monitor with 5 second refresh |
| `winvps doctor` | Run diagnostics, check all services |

### Backup

| Command | Description |
|---------|-------------|
| `winvps backup create` | Create timestamped backup |
| `winvps backup list` | List all backups |
| `winvps backup restore` | Restore latest backup |

### Configuration

| Command | Description |
|---------|-------------|
| `winvps config show` | Show all config |
| `winvps config get WINVPS_SSH_PORT` | Get a config value |
| `winvps config set WINVPS_SSH_PORT 7022` | Set a config value |
| `winvps config load full` | Load a profile (minimal/dev/full/stealth/ghost/hardened) |

### Logs

| Command | Description |
|---------|-------------|
| `winvps logs` | List available log files |
| `winvps logs ssh 100` | Last 100 lines of SSH logs |
| `winvps logs web` | Web server logs |

### Security

| Command | Description |
|---------|-------------|
| `winvps security status` | Show security status |
| `winvps security scan` | Scan for issues |
| `winvps security harden` | Lock down SSH + firewall |
| `winvps fail2ban start` | Start brute-force protection |
| `winvps fail2ban stop` | Stop brute-force protection |
| `winvps tamper init` | Initialize tamper detection |
| `winvps tamper verify` | Verify file integrity |
| `winvps tamper status` | Show tamper status |

### Stealth & Obfuscation

| Command | Description |
|---------|-------------|
| `winvps stealth enable` | Enable stealth mode |
| `winvps stealth disable` | Disable stealth mode |
| `winvps stealth status` | Show stealth status |
| `winvps obfuscate all` | Randomize hostname, MAC, SSH keys |
| `winvps obfuscate hostname` | Randomize hostname only |
| `winvps obfuscate ssh` | Randomize SSH host keys |
| `winvps obfuscate mac` | Randomize MAC address |

### Networking

| Command | Description |
|---------|-------------|
| `winvps tunnel start cloudflare` | Start Cloudflare tunnel |
| `winvps tunnel start ngrok` | Start ngrok tunnel |
| `winvps tunnel start bore` | Start bore tunnel |
| `winvps tunnel stop` | Stop active tunnel |
| `winvps tunnel status` | Show tunnel status |
| `winvps tor start` | Start Tor gateway |
| `winvps tor stop` | Stop Tor gateway |
| `winvps killswitch enable` | Enable VPN kill switch |
| `winvps killswitch disable` | Disable VPN kill switch |

### Encryption

| Command | Description |
|---------|-------------|
| `winvps encrypt init` | Initialize encrypted storage |
| `winvps encrypt unmount` | Unmount encrypted volume |
| `winvps encrypt status` | Show encryption status |

### Other

| Command | Description |
|---------|-------------|
| `winvps tier info` | Show RAM tier and recommendations |
| `winvps uninstall` | Remove WinVPS completely |
| `winvps help` | Show all commands |
| `winvps version` | Show version |

---

## Remote Access Setup

### Option 1: Cloudflare Tunnel (Recommended - Free)

1. Sign up at https://dash.cloudflare.com
2. Install cloudflared:
   ```powershell
   winget install Cloudflare.cloudflared
   ```
3. Authenticate:
   ```powershell
   cloudflared tunnel login
   ```
4. Create a tunnel:
   ```powershell
   cloudflared tunnel create winvps
   ```
5. Start the tunnel:
   ```powershell
   winvps tunnel start cloudflare
   ```

This gives you a permanent `https://your-tunnel.trycloudflare.com` URL accessible from anywhere.

### Option 2: ngrok (Quick, temporary)

1. Sign up at https://ngrok.com and get your authtoken
2. Install ngrok:
   ```powershell
   winget install Ngrok.Ngrok
   ```
3. Configure:
   ```powershell
   ngrok config add-authtoken YOUR_TOKEN
   ```
4. Start:
   ```powershell
   winvps tunnel start ngrok
   ```

### Option 3: SSH Reverse Tunnel

If you have a public VPS:
```powershell
# On your WinVPS machine, connect to your public VPS
ssh -R 7022:localhost:22 root@your-public-vps-ip
```

### Option 4: Direct SSH (Port Forwarding)

On your router, forward port 7022 to your machine's local IP, then:
```powershell
ssh -p 7022 yourusername@your-public-ip
```

---

## Telegram Bot Setup

1. Message [@BotFather](https://t.me/BotFather) on Telegram and create a bot
2. Copy the bot token
3. Add to your config:
   ```powershell
   winvps config set WINVPS_TELEGRAM_BOT_TOKEN "YOUR_BOT_TOKEN"
   ```
4. Get your chat ID by messaging your bot, then visit:
   ```
   https://api.telegram.org/botYOUR_BOT_TOKEN/getUpdates
   ```
5. Set your chat ID:
   ```powershell
   winvps config set WINVPS_TELEGRAM_CHAT_ID "YOUR_CHAT_ID"
   ```
6. Start the bot:
   ```powershell
   .\src\bots\shell-telegram.ps1 start
   ```

### Bot Commands
- `/status` - System status
- `/services` - List running services
- `/health` - Run health check
- `/backup` - Create backup
- `/help` - Show commands

---

## Discord Bot Setup

1. Create a Discord bot at https://discord.com/developers/applications
2. Copy the bot token and set it:
   ```powershell
   winvps config set WINVPS_DISCORD_BOT_TOKEN "YOUR_BOT_TOKEN"
   ```
3. Get your channel ID (enable Developer Mode in Discord, right-click channel > Copy ID):
   ```powershell
   winvps config set WINVPS_DISCORD_CHANNEL_ID "YOUR_CHANNEL_ID"
   ```
4. Start the bot:
   ```powershell
   .\src\bots\shell-discord.ps1 start
   ```

### Bot Commands
- `!status` - System status
- `!health` - Health check
- `!backup` - Create backup
- `!help` - Show commands

---

## RAM Tiers

WinVPS automatically detects your system's RAM and optimizes accordingly:

| Tier | RAM | Description |
|------|-----|-------------|
| Shadow | <=512MB | Ultra-light, SSH + minimal web only |
| Lite | <=2GB | Core services only |
| Standard | <=8GB | Balanced feature set |
| Full | >8GB | Everything enabled |

Check your tier:
```powershell
winvps tier info
```

---

## Profiles

Switch between pre-configured profiles:

```powershell
winvps config load minimal    # Minimal setup
winvps config load dev         # Development
winvps config load full        # Everything on
winvps config load hardened    # Security focused
winvps config load stealth     # Maximum stealth
winvps config load ghost       # Ultra-stealth, auto-wipe
```

---

## Configuration

Main config file: `C:\WinVPS\config\winvps.conf`

Key settings:
```
WINVPS_SSH_PORT=7022
WINVPS_WEB_PORT=7080
WINVPS_AUTO_UPDATE=true
WINVPS_AUTO_BACKUP=true
WINVPS_BACKUP_INTERVAL="weekly"
WINVPS_WATCHDOG=true
WINVPS_LOG_LEVEL="info"
```

---

## Web Dashboard

Visit **http://localhost:7080** after installation.

### Features
- System overview (CPU, RAM, disk, uptime)
- Service management (start/stop/restart)
- Live logs viewer
- Configuration editor
- Storage analyzer
- Backup management
- API key authentication (auto-generated on first run)

### API Key Auth

The dashboard requires a Bearer token for API access. The key is auto-generated on first run and stored at `config/web-api.key`.

```powershell
# Get your API key
type C:\WinVPS\config\web-api.key

# Use with curl/Invoke-WebRequest
$key = Get-Content C:\WinVPS\config\web-api.key
Invoke-RestMethod -Uri http://localhost:7080/api/status -Headers @{Authorization="Bearer $key"}

# Rotate the key
Invoke-RestMethod -Uri http://localhost:7080/api/apikey -Method POST -Headers @{Authorization="Bearer $key"}
```

### API Endpoints

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/status` | GET | System status overview |
| `/api/services` | GET | List all services |
| `/api/services/:name/start` | POST | Start a service |
| `/api/services/:name/stop` | POST | Stop a service |
| `/api/logs/:service` | GET | Get service logs |
| `/api/config` | GET/POST | Read/write configuration |
| `/api/health` | GET | Run health check |
| `/api/storage` | GET | Storage usage |
| `/api/backups` | GET | List backups |
| `/api/backup` | POST | Create backup |
| `/api/apikey` | GET/POST | Get/rotate API key |

---

## Project Structure

```
C:\WinVPS\
  src/
    cli/winvps.ps1           # Main CLI (25+ commands)
    shell/shell.ps1          # Natural language shell (PS)
    shell/shell.sh           # Natural language shell (Bash)
    core/                    # 17 core modules
    web/backend/main.py      # Python API server
    web/frontend/index.html  # Dashboard UI
    bots/                    # Telegram/Discord bots
    tunnels/                 # Tunnel manager
  config/
    winvps.conf              # Main config
    web-api.key              # Auto-generated API key
    profiles/                # Pre-configured profiles
  setup/
    Install-WinVPS.ps1       # Installer
    Uninstall-WinVPS.ps1     # Uninstaller
  dist/
    winvps-portable.ps1      # One-command portable installer
  tests/                     # Test suite
```

---

## Uninstall

```powershell
.\setup\Uninstall-WinVPS.ps1
```

Or from the CLI:
```powershell
winvps uninstall
```

---

## License

MIT -- see [LICENSE](LICENSE)
