#!/usr/bin/env python3
"""WinVPS Web Dashboard — Zero-dependency Python backend (stdlib only)
Serves both the API and static frontend files on a single port.
Adapted from AnVPS for Windows."""
import os, json, subprocess, platform, re, urllib.parse, mimetypes
from pathlib import Path
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
from socketserver import ThreadingMixIn

WINVPS_DIR = Path(os.environ.get('WINVPS_DIR', r'C:\WinVPS'))
WWW_DIR = WINVPS_DIR / 'data' / 'sites' / 'default'
PORT = int(os.environ.get('ANVPS_WEB_PORT', '7080'))

def run_cmd(cmd):
    try:
        r = subprocess.run(cmd, shell=True, capture_output=True, text=True, timeout=10, encoding='utf-8', errors='replace')
        return {'code': r.returncode, 'stdout': r.stdout.strip(), 'stderr': r.stderr.strip()}
    except subprocess.TimeoutExpired:
        return {'code': -1, 'stdout': '', 'stderr': 'timeout'}
    except Exception as e:
        return {'code': -1, 'stdout': '', 'stderr': str(e)}

def get_system_info():
    info = {}
    try:
        r = run_cmd('powershell -NoProfile -Command "Get-CimInstance Win32_OperatingSystem | Select-Object LastBootUpTime,FreePhysicalMemory,TotalVisibleMemorySize | ConvertTo-Json"')
        if r['code'] == 0:
            os_info = json.loads(r['stdout'])
            boot = datetime.fromisoformat(os_info['LastBootUpTime'].replace('Z', '+00:00'))
            uptime_s = (datetime.now().astimezone() - boot).total_seconds()
            hours = int(uptime_s // 3600)
            mins = int((uptime_s % 3600) // 60)
            info['uptime'] = f'{hours}h {mins}m'
            total = int(os_info.get('TotalVisibleMemorySize', 0)) // 1024
            free = int(os_info.get('FreePhysicalMemory', 0)) // 1024
            used = total - free
            info['memory'] = f'{used}MB/{total}MB ({round(used/total*100) if total else 0}%)'
    except Exception:
        info['uptime'] = 'N/A'
        info['memory'] = 'N/A'

    try:
        r = run_cmd('powershell -NoProfile -Command "(Get-CimInstance Win32_Processor).LoadPercentage"')
        if r['code'] == 0:
            info['cpu'] = f'{r["stdout"]}%'
        else:
            info['cpu'] = 'N/A'
    except Exception:
        info['cpu'] = 'N/A'

    try:
        r = run_cmd(f'powershell -NoProfile -Command "Get-Volume | Where-Object {{$_.DriveLetter -eq \'{str(WINVPS_DIR)[:2][0]}\'}} | Select-Object SizeRemaining,Size | ConvertTo-Json"')
        if r['code'] == 0:
            vol = json.loads(r['stdout'])
            total = int(vol.get('Size', 0))
            free = int(vol.get('SizeRemaining', 0))
            used_gb = round((total - free) / (1024**3), 1)
            total_gb = round(total / (1024**3), 1)
            info['disk'] = f'{used_gb}GB/{total_gb}GB'
        else:
            info['disk'] = 'N/A'
    except Exception:
        info['disk'] = 'N/A'

    return info

class Handler(BaseHTTPRequestHandler):
    def _send_json(self, data, status=200):
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', '*')
        self.end_headers()
        self.wfile.write(json.dumps(data, default=str).encode())

    def _send_file(self, path, status=200):
        ctype, _ = mimetypes.guess_type(str(path))
        if not ctype:
            ctype = 'application/octet-stream'
        self.send_response(status)
        self.send_header('Content-Type', ctype)
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        with open(path, 'rb') as f:
            self.wfile.write(f.read())

    def _read_body(self):
        length = int(self.headers.get('Content-Length', 0))
        return json.loads(self.rfile.read(length)) if length else {}

    def _serve_static(self, path):
        safe = Path(path).relative_to('/')
        file = WWW_DIR / safe
        if file.is_file():
            self._send_file(file)
        else:
            index = WWW_DIR / 'index.html'
            if index.is_file():
                self._send_file(index)
            else:
                self._send_json({'error': 'not found'}, 404)

    def do_OPTIONS(self):
        self._send_json({})

    def _api_route(self, method, path, params, body):
        if path == '/api/status' and method == 'GET':
            sys_info = get_system_info()
            return self._send_json({
                'version': '1.0.0',
                'hostname': platform.node(),
                'platform': 'WinVPS',
                'uptime': sys_info.get('uptime', 'N/A'),
                'memory': sys_info.get('memory', 'N/A'),
                'disk': sys_info.get('disk', 'N/A'),
                'cpu': sys_info.get('cpu', 'N/A'),
                'services': self._scan_services(),
                'tunnels': self._scan_tunnels(),
                'timestamp': datetime.now().isoformat()
            })

        if path == '/api/services' and method == 'GET':
            return self._send_json({'services': self._scan_services()})

        m = re.match(r'^/api/services/(\w+)/(start|stop)$', path)
        if m:
            name, action = m.group(1), m.group(2)
            if action == 'start':
                script = WINVPS_DIR / 'src' / 'core' / f'{name}.ps1'
                if script.exists():
                    r = run_cmd(f'powershell -NoProfile -ExecutionPolicy Bypass -File "{script}" start')
                    ok = r['code'] == 0
                    return self._send_json({'status': 'ok' if ok else 'error', 'message': f'{name} started' if ok else r['stderr'] or r['stdout']})
                return self._send_json({'status': 'error', 'message': f'No script for {name}'}, 404)
            pidf = WINVPS_DIR / 'services' / f'{name}.pid'
            if pidf.exists():
                pid = pidf.read_text().strip()
                run_cmd(f'taskkill /PID {pid} /F 2>nul')
                pidf.unlink(missing_ok=True)
                return self._send_json({'status': 'ok', 'message': f'{name} stopped'})
            return self._send_json({'status': 'error', 'message': f'{name} not running'}, 404)

        m = re.match(r'^/api/logs/(\w+)$', path)
        if m and method == 'GET':
            service = m.group(1)
            log_file = WINVPS_DIR / 'logs' / f'{service}.log'
            if not log_file.exists():
                return self._send_json({'error': f'No logs for {service}'}, 404)
            lines = int(params.get('lines', 50))
            content = run_cmd(f'powershell -NoProfile -Command "Get-Content \'{log_file}\' -Tail {lines}"')
            return self._send_json({'service': service, 'lines': content['stdout'].split('\n')})

        if path == '/api/health' and method == 'GET':
            script = WINVPS_DIR / 'src' / 'core' / 'healthcheck.ps1'
            if script.exists():
                r = run_cmd(f'powershell -NoProfile -ExecutionPolicy Bypass -File "{script}"')
                return self._send_json({'status': 'ok' if 'passed' in r['stdout'].lower() else 'issues', 'output': r['stdout']})
            return self._send_json({'status': 'error', 'output': 'healthcheck not found'})

        config_file = WINVPS_DIR / 'config' / 'winvps.conf'
        if path == '/api/config':
            if method == 'GET':
                config = {}
                if config_file.exists():
                    for line in config_file.read_text().splitlines():
                        if '=' in line and not line.startswith('#'):
                            k, v = line.split('=', 1)
                            config[k.strip()] = v.strip().strip('"')
                return self._send_json(config)
            if method == 'POST':
                with open(config_file, 'w') as f:
                    for k, v in body.items():
                        f.write(f'{k}="{v}"\n')
                return self._send_json({'status': 'ok'})

        if path == '/api/storage' and method == 'GET':
            usage = run_cmd(f'powershell -NoProfile -Command "(Get-ChildItem -Path \'{WINVPS_DIR}\' -Recurse -File | Measure-Object -Property Length -Sum).Sum / 1MB"')
            df_out = run_cmd(f'powershell -NoProfile -Command "Get-Volume | Where-Object {{$_.DriveLetter -eq \'{str(WINVPS_DIR)[:2][0]}\'}} | Select-Object Size,SizeRemaining | ConvertTo-Json"')
            return self._send_json({'anvps_usage_mb': usage['stdout'], 'disk': df_out['stdout']})

        if path == '/api/backup' and method == 'POST':
            r = run_cmd(f'powershell -NoProfile -ExecutionPolicy Bypass -File "{WINVPS_DIR / "src" / "cli" / "winvps.ps1"}" backup create')
            return self._send_json({'status': 'ok' if r['code'] == 0 else 'error', 'output': r['stdout']})

        if path == '/api/backups' and method == 'GET':
            backup_dir = WINVPS_DIR / 'backup'
            backups = []
            if backup_dir.exists():
                for f in sorted(backup_dir.glob('*.zip'), reverse=True):
                    stat = f.stat()
                    backups.append({'name': f.name, 'size': stat.st_size, 'modified': datetime.fromtimestamp(stat.st_mtime).isoformat()})
            return self._send_json({'backups': backups})

        return None

    def _scan_services(self):
        services = []
        svc_dir = WINVPS_DIR / 'services'
        if svc_dir.exists():
            for pidf in sorted(svc_dir.glob('*.pid')):
                name = pidf.stem
                pid = int(pidf.read_text().strip())
                alive = run_cmd(f'powershell -NoProfile -Command "if (Get-Process -Id {pid} -ErrorAction SilentlyContinue) {{ \'running\' }} else {{ \'stopped\' }}"')
                mem = '0'
                if alive['stdout'] == 'running':
                    m = run_cmd(f'powershell -NoProfile -Command "(Get-Process -Id {pid}).WorkingSet64 / 1MB"')
                    mem = m['stdout']
                services.append({'name': name, 'pid': pid, 'status': alive['stdout'], 'memory': mem})
        return services

    def _scan_tunnels(self):
        tunnels = {}
        for t in ['cloudflared', 'ngrok', 'bore']:
            r = run_cmd(f'powershell -NoProfile -Command "if (Get-Process -Name {t}* -ErrorAction SilentlyContinue) {{ \'active\' }} else {{ \'inactive\' }}"')
            tunnels[t] = r['stdout']
        return tunnels

    def _route(self):
        p = urllib.parse.urlparse(self.path)
        path = p.path.rstrip('/')
        params = {k: v[0] for k, v in urllib.parse.parse_qs(p.query).items()}
        method = self.command
        body = self._read_body() if method == 'POST' else {}
        result = self._api_route(method, path, params, body)
        if result is not None:
            return
        if method == 'GET':
            self._serve_static(path)
        else:
            self._send_json({'error': 'not found'}, 404)

    def do_GET(self):
        self._route()

    def do_POST(self):
        self._route()

class ThreadedServer(ThreadingMixIn, HTTPServer):
    allow_reuse_address = True

if __name__ == '__main__':
    WWW_DIR.mkdir(parents=True, exist_ok=True)
    index = WWW_DIR / 'index.html'
    if not index.exists():
        index.write_text('<html><body><h1>WinVPS</h1><p>Dashboard loading...</p></body></html>')
    server = ThreadedServer(('0.0.0.0', PORT), Handler)
    print(f'WinVPS Web Dashboard running on http://0.0.0.0:{PORT}')
    server.serve_forever()
