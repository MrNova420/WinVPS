# WinVPS

A Windows fork of [AnVPS](https://github.com/MrNova420/AnVPS) — turn any Windows machine into a self-managed, auto-healing, remotely accessible VPS.

## Features

- **Service Supervisor** — auto-restarts crashed services
- **System Health Monitoring** — CPU, RAM, disk, network, temperature
- **Web Dashboard** — dark-themed control panel at `http://localhost:7080`
- **Security Hardening** — SSH lockdown, firewall, fail2ban
- **Auto-Updates** — self-updating, package management
- **Backup System** — timestamped compressed backups
- **Cloud Tunnels** — Cloudflare, ngrok, bore, WireGuard for remote access
- **Tor Gateway** — optional Tor hidden service support
- **Stealth Mode** — scheduled availability, decoy services
- **Obfuscation** — hostname, MAC, SSH key, HTTP header randomization
- **Tamper Detection** — integrity checks with auto-wipe on failure
- **VPN Kill Switch** — blocks all traffic outside VPN
- **Telegram/Discord Bots** — remote management via chat
- **RAM Tiering** — automatic optimization for 512MB to 16GB+

## Quick Start

### One-line install (PowerShell as Admin)

```powershell
iex (Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/WinVPS/WinVPS/main/setup/install.ps1').Content
```

### Manual install

```powershell
# Clone
git clone https://github.com/WinVPS/WinVPS.git C:\WinVPS
cd C:\WinVPS

# Install
.\setup\Install-WinVPS.ps1
```

### Usage

```powershell
winvps status              # System overview
winvps service list        # List all services
winvps security harden     # Lock down SSH + firewall
winvps tunnel start cloudflare  # Expose via Cloudflare tunnel
winvps backup create       # Create a backup
winvps doctor              # Auto-fix common issues
```

## RAM Tiers

| Tier | RAM | Description |
|------|-----|-------------|
| Shadow | ≤512MB | Ultra-light, SSH + minimal web only |
| Lite | ≤2GB | Core services only |
| Standard | ≤8GB | Balanced feature set |
| Full | >8GB | Everything enabled |

## Configuration

Main config: `C:\WinVPS\config\winvps.conf`

Profiles in `config\profiles\`: `minimal`, `dev`, `full`, `stealth`, `ghost`, `hardened`

## Web Dashboard

Visit `http://localhost:7080` after installation. Dark-themed with:
- System overview (CPU, RAM, disk, uptime)
- Service management (start/stop/restart)
- Live logs viewer
- Configuration editor
- Storage analyzer

## License

MIT — see [LICENSE](LICENSE)
