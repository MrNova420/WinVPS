# Changelog

## [2.0.0] — 2026-07-25

### Added — Service System v2.0
- `config/services.conf` — pipe-delimited service definitions (name|script|type|port|auto_start|health_check|depends_on|description)
- `src/core/service-manager.ps1` — comprehensive service lifecycle manager (1091 lines)
  - 20 actions: list, add, remove, start, stop, restart, status, detail, config, env, secrets, health, metrics, deps, graph, backup, restore, exec, logs, install-deps
  - Per-service directory structure: `services/<name>/{pid, .env, data/, logs/, secrets/, service.conf}`
  - Dependency resolution via topological sort (graph-based start ordering)
  - Health check engine: HTTP (with latency), TCP port, process fallback, retries, history
  - Metrics collection: memory, CPU, disk, uptime, log size, history saved as JSON
  - Dependency graph: forward + reverse dependency map with ASCII visualization
  - Launch command builder per type (node, python, go, dotnet, docker, ps, cmd)
  - Service backup/restore, log rotation, dependency auto-install, exec in service context
- Auto-detect service type from file extension (`.js`→node, `.py`→python, `.ps1`→ps, `.go`→go, `.csproj`→dotnet, Dockerfile→docker)
- Named args parser (`Parse-Args`) for `--key value` and `--flag` CLI patterns

### Added — Tailscale Support
- Tailscale Funnel tunnel type in `src/tunnels/tunnel-manager.ps1`
- `WINVPS_TAILSCALE_HOSTNAME` config key
- Auto-detection of tailscale.exe, connection verification, funnel start/stop

### Added — Web Dashboard v2.0
- Split frontend into 3 files: `styles.css` (design system), `app.js` (dashboard logic), `index.html` (layout)
- GitHub-dark palette with CSS variables, cards, tables, badges, modals, toasts, animations
- Service management from dashboard: list, start/stop, add/remove
- Add Service modal with auto-detection
- Dynamic service list from `services.conf` (not hardcoded)
- API endpoints: `POST /api/services/add`, `POST /api/services/:name/remove`

### Added — Generic Project Bootstrapper
- `setup/Setup-Project.ps1` — register any project as a managed service with one command
- Params: RepoUrl, Name, Path, Port, Type, AutoStart, HealthCheck, DependsOn, Description, Tailscale, Cloudflare, DryRun
- Interactive prompts, auto-detect type, find entry point, install prereqs via winget, install deps

### Added — Documentation
- `USAGE.md` — comprehensive usage guide covering all commands, API reference, troubleshooting
- Professional `README.md` with badges, architecture diagram, feature tables

### Changed — CLI Rewrite
- `src/cli/winvps.ps1` rewritten with premium UX
- Theme system: `$Theme` hashtable (Primary, Success, Warning, Error, Dim, Accent, Reset, Bold)
- `service list/add/remove/start/stop/restart/detail/health/metrics/deps/logs/backup/exec/install-deps` commands
- Interactive prompts for `service add` when no args given
- `Show-Status`, `Show-Help`, `Show-Doctor`, `Show-Monitor` with color-coded output

### Changed — Supervisor Rewrite
- `src/core/supervisor.ps1` rewritten to read from `services.conf` (pipe-delimited format)
- Dependency resolution: topological sort ensures correct start order
- Watchdog with exponential backoff (1s → 2s → 4s → ... → 60s max, resets on success)
- Max 5 restart attempts before giving up per service
- Graceful shutdown: CloseMainWindow → wait 5s → Kill

### Fixed
- Replaced Unicode box-drawing (`─`), bullet (`●`), circle (`○`), and em-dash (`—`) with ASCII across all PS files (PS 5.1 parser compatibility)
- Fixed `${Theme.Reset}` patterns → `$Theme.Reset` (property access, not variable name lookup)
- Removed `return switch` (invalid in PS 5.1) in service-manager.ps1
- Replaced `??` null coalescing operator (PS 7+ only) with `if/else` in supervisor.ps1
- All 4 core modules pass PowerShell parse tests

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
