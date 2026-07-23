# Changelog

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
