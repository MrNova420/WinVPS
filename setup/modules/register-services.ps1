# WinVPS - Windows VPS Auto-Managed Server Platform
# PowerShell 7+ compatible

$services = @(
    @{ name = 'nginx';    desc = 'Nginx HTTP reverse proxy'; port = 8080; config = 'nginx.conf' }
    @{ name = 'apache';   desc = 'Apache HTTP server';       port = 8080; config = 'apache.conf' }
    @{ name = 'node';     desc = 'Node.js runtime';          port = 3000; config = 'package.json' }
    @{ name = 'python';   desc = 'Python application server';port = 5000; config = 'app.py' }
    @{ name = 'java';     desc = 'Java/JVM application';     port = 8443; config = 'app.jar' }
    @{ name = 'redis';    desc = 'Redis in-memory database'; port = 6379; config = 'redis.conf' }
    @{ name = 'postgres'; desc = 'PostgreSQL database';      port = 5432; config = 'postgresql.conf' }
    @{ name = 'mysql';    desc = 'MySQL/MariaDB database';   port = 3306; config = 'my.cnf' }
    @{ name = 'mongo';    desc = 'MongoDB document database';port = 27017; config = 'mongod.conf' }
    @{ name = 'mail';     desc = 'Mail server (hMailServer)';port = 587;  config = 'hMailServer.ini' }
    @{ name = 'ftp';      desc = 'FTP server (FileZilla)';   port = 21;   config = 'FileZilla Server.xml' }
    @{ name = 'dns';      desc = 'DNS server (BIND9)';       port = 53;   config = 'named.conf' }
    @{ name = 'rdesktop'; desc = 'Remote Desktop (RDP)';     port = 3389; config = '' }
    @{ name = 'wireguard';desc = 'WireGuard VPN';            port = 51820;config = 'wg0.conf' }
    @{ name = 'tailscale';desc = 'Tailscale mesh VPN';       port = 0;    config = '' }
)

foreach ($svc in $services) {
    $dir = "C:\WinVPS\services\$($svc.name)"
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    @"
# WinVPS Service: $($svc.name)
service=$($svc.name)
description=$($svc.desc)
port=$($svc.port)
type=custom
auto_start=true
" | Out-File -FilePath "$dir\config.ini" -Encoding ascii -Force

    "disabled" | Out-File -FilePath "$dir\.disabled" -Encoding ascii -Force
    "# $($svc.desc) status`nstopped" | Out-File -FilePath "$dir\status" -Encoding ascii -Force
}
