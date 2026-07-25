# Changelog

## [1.1.0] — 2026-07-25

### Added
- Natural language shell (`winvps shell`) — type plain English, get the right command with approve/edit/execute UX
- Web dashboard API key authentication (auto-generated, stored in `config/web-api.key`)
- Rate limiting on web API (120 requests/minute per IP)
- Input sanitization on all CLI commands and web API endpoints
- Structured logging with file rotation (`logs/web-dashboard.log`)
- Config key redaction (tokens/keys/secrets hidden from API responses)
- CORS and security headers on all API responses
- Threaded web server for concurrent request handling
- API key rotation endpoint (`POST /api/apikey`)
- Backup listing endpoint (`GET /api/backups`)
- Storage usage endpoint (`GET /api/storage`)
- Health check endpoint (`GET /api/health`)
- Service log viewer endpoint (`GET /api/logs/:service`)

### Fixed
- Python 3.14 syntax error: removed `global` keyword, use mutable state dict
- Replaced en-dash (U+2013) and em-dash (U+2014) characters with ASCII `-` across all 23 `.ps1` files (PowerShell 5.1 parser fix)
- Renamed `$Args` to `$CmdArgs` in CLI to avoid PowerShell reserved variable
- Fixed `Ensure-Dirs` array syntax for PS5.1 compatibility
- Fixed `$totalMBMB` ambiguous variable reference to `${totalMB}MB`
- Fixed Discord bot triple-backtick string escaping for PS5.1

## [1.0.0] — 2026-07-23

### Added
- Core modules: supervisor, healthcheck, security, fail2ban, stealth, obfuscate, tamper, wipe, vpn-killswitch, encrypt, tor, storage, autoupdate, lightweight, ssh, httpd
- CLI with 25+ commands: status, service, monitor, backup, config, logs, doctor, tunnel, security, stealth, obfuscate, encrypt, tor, tamper, killswitch, fail2ban, tier, uninstall, help, version
- Web dashboard (Python backend + HTML/CSS/JS frontend)
- 9 config profiles: minimal, dev, full, stealth, ghost, hardened, shadow, lite, webhost
- Telegram and Discord chat bots for remote management
- Cloudflare, ngrok, and bore tunnel support
- Tor Expert Bundle integration
- Task Scheduler auto-start
- Windows Firewall rule management
- BitLocker/VeraCrypt encryption integration
- 15 service module definitions (nginx, apache, node, python, java, redis, postgres, mysql, mongo, mail, ftp, dns, rdesktop, wireguard, tailscale)
- Auto-update system with GitHub release checking
- Log rotation and cleanup
- One-click installer (Install-WinVPS.ps1)
- Portable installer (winvps-portable.ps1)
- Full uninstaller (Uninstall-WinVPS.ps1)

### Changed
- All Bash scripts from AnVPS rewritten to PowerShell
- Linux service management replaced with Windows Process-based supervisor
- iptables replaced with Windows Firewall
- systemd replaced with Task Scheduler
- openrc/rc-status replaced with process monitoring

## [0.1.0] — 2026-07-23

### Added
- Initial project structure
- Core module framework
