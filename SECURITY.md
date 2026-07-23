# Security Policy

## Reporting

If you discover a security vulnerability in WinVPS, please report it responsibly.
Open a GitHub issue at: https://github.com/WinVPS/WinVPS/issues

## Security Features

- SSH hardening (disable root, password auth, MaxAuthTries)
- Windows Firewall rule management
- Fail2ban-style brute-force IP banning
- Tamper detection with integrity checks
- Secure data wipe on tamper (configurable)
- VPN kill switch (blocks traffic outside VPN)
- Stealth mode with scheduled availability
- Obfuscation (hostname, MAC, SSH keys, HTTP headers)
- Tor gateway support
- BitLocker/VeraCrypt encryption integration
- Auto-updates with integrity verification

## Hardening Checklist

Run `winvps security harden` to apply:
- [ ] SSH port changed from 22
- [ ] Password authentication disabled
- [ ] Max auth tries limited to 3
- [ ] Firewall enabled with only required ports
- [ ] Fail2ban enabled for SSH
- [ ] Tamper detection enabled
- [ ] Dead man switch configured

## Default Ports

| Port | Service |
|------|---------|
| 7022 | SSH |
| 7080 | Web Dashboard |
| 7443 | HTTPS |
| 7444 | File Transfer |
