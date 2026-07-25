#!/usr/bin/env python3
"""WinVPS Web Dashboard - Production backend (stdlib only)
Serves API + static frontend on a single port.
Features: API key auth, input sanitization, rate limiting, proper error handling, logging."""
import os, json, subprocess, platform, re, urllib.parse, mimetypes, hashlib, secrets, time, logging
from pathlib import Path
from datetime import datetime
from http.server import HTTPServer, BaseHTTPRequestHandler
from socketserver import ThreadingMixIn

WINVPS_DIR = Path(os.environ.get('WINVPS_DIR', r'C:\WinVPS'))
WWW_DIR = WINVPS_DIR / 'data' / 'sites' / 'default'
PORT = int(os.environ.get('WINVPS_WEB_PORT', '7080'))
LOG_DIR = WINVPS_DIR / 'logs'
CONFIG_FILE = WINVPS_DIR / 'config' / 'winvps.conf'

# ---------- Logging ----------
LOG_DIR.mkdir(parents=True, exist_ok=True)
logging.basicConfig(
    filename=str(LOG_DIR / 'web-dashboard.log'),
    level=logging.INFO,
    format='%(asctime)s [%(levelname)s] %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
log = logging.getLogger('winvps-web')

# ---------- Config loading ----------
def load_config():
    cfg = {}
    if CONFIG_FILE.exists():
        for line in CONFIG_FILE.read_text(encoding='utf-8', errors='replace').splitlines():
            line = line.strip()
            if '=' in line and not line.startswith('#'):
                k, v = line.split('=', 1)
                cfg[k.strip()] = v.strip().strip('"').strip("'")
    return cfg

CFG = load_config()

def get_api_key():
    key = CFG.get('WINVPS_WEB_API_KEY', '')
    if not key:
        key_file = WINVPS_DIR / 'config' / 'web-api.key'
        if key_file.exists():
            key = key_file.read_text().strip()
        else:
            key = secrets.token_urlsafe(32)
            key_file.parent.mkdir(parents=True, exist_ok=True)
            key_file.write_text(key)
            key_file.chmod(0o600)
            log.info(f'Generated new API key: {key[:8]}...')
    return key

API_KEY = get_api_key()
_auth_state = {'api_key': API_KEY}

# ---------- Input sanitization ----------
RE_SERVICE_NAME = re.compile(r'^[a-zA-Z0-9_-]{1,64}$')
RE_CONFIG_KEY = re.compile(r'^WINVPS_[A-Z0-9_]{1,64}$')
SAFE_PATH_CHARS = re.compile(r'^[a-zA-Z0-9._/-]{1,256}$')

def sanitize_service_name(name):
    if not name or not RE_SERVICE_NAME.match(name):
        return None
    return name

def sanitize_config_key(key):
    if not key or not RE_CONFIG_KEY.match(key):
        return None
    return key

def sanitize_path(path):
    if not path or not SAFE_PATH_CHARS.match(path):
        return None
    if '..' in path:
        return None
    return path

def sanitize_lines(val):
    try:
        n = int(val)
        return max(1, min(500, n))
    except (ValueError, TypeError):
        return 50

# ---------- Rate limiting ----------
class RateLimiter:
    def __init__(self, max_per_minute=120):
        self.max = max_per_minute
        self.hits = {}
    def check(self, ip):
        now = time.time()
        window = int(now // 60)
        key = f'{ip}:{window}'
        count = self.hits.get(key, 0)
        if count >= self.max:
            return False
        self.hits[key] = count + 1
        if len(self.hits) > 200:
            old = [k for k in self.hits if not k.endswith(f':{window}')]
            for k in old:
                del self.hits[k]
        return True

rate_limiter = RateLimiter()

# ---------- Command execution ----------
def run_cmd(cmd, timeout=15):
    try:
        r = subprocess.run(
            cmd, shell=True, capture_output=True, text=True,
            timeout=timeout, encoding='utf-8', errors='replace'
        )
        return {'code': r.returncode, 'stdout': r.stdout.strip(), 'stderr': r.stderr.strip()}
    except subprocess.TimeoutExpired:
        return {'code': -1, 'stdout': '', 'stderr': 'command timed out'}
    except Exception as e:
        log.error(f'Command failed: {cmd[:100]}: {e}')
        return {'code': -1, 'stdout': '', 'stderr': str(e)}

# ---------- System info ----------
def get_system_info():
    info = {}
    try:
        r = run_cmd('powershell -NoProfile -Command "Get-CimInstance Win32_OperatingSystem | Select-Object LastBootUpTime,FreePhysicalMemory,TotalVisibleMemorySize | ConvertTo-Json"', timeout=10)
        if r['code'] == 0 and r['stdout']:
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
        r = run_cmd('powershell -NoProfile -Command "(Get-CimInstance Win32_Processor).LoadPercentage"', timeout=5)
        if r['code'] == 0 and r['stdout']:
            info['cpu'] = f'{r["stdout"]}%'
        else:
            info['cpu'] = 'N/A'
    except Exception:
        info['cpu'] = 'N/A'

    try:
        drive = str(WINVPS_DIR)[:2].upper()
        r = run_cmd(f'powershell -NoProfile -Command "Get-Volume -DriveLetter {drive[0]} | Select-Object SizeRemaining,Size | ConvertTo-Json"', timeout=5)
        if r['code'] == 0 and r['stdout']:
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

    info['hostname'] = platform.node()
    info['platform'] = f'Windows {platform.version()}'
    return info

# ---------- Handler ----------
class Handler(BaseHTTPRequestHandler):
    server_version = 'WinVPS/1.0'

    def log_message(self, fmt, *args):
        log.info(f'{self.client_address[0]} {fmt % args}')

    def _send_json(self, data, status=200):
        body = json.dumps(data, default=str).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Content-Length', str(len(body)))
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('X-Frame-Options', 'DENY')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.send_header('Access-Control-Allow-Methods', 'GET, POST, OPTIONS')
        self.send_header('Access-Control-Allow-Headers', 'Authorization, Content-Type')
        self.end_headers()
        self.wfile.write(body)

    def _send_file(self, path, status=200):
        ctype, _ = mimetypes.guess_type(str(path))
        if not ctype:
            ctype = 'application/octet-stream'
        try:
            data = path.read_bytes()
            self.send_response(status)
            self.send_header('Content-Type', ctype)
            self.send_header('Content-Length', str(len(data)))
            self.send_header('X-Content-Type-Options', 'nosniff')
            self.send_header('Cache-Control', 'no-store')
            self.end_headers()
            self.wfile.write(data)
        except Exception as e:
            log.error(f'Failed to serve {path}: {e}')
            self._send_json({'error': 'file read error'}, 500)

    def _read_body(self):
        length = int(self.headers.get('Content-Length', 0))
        if length > 1_048_576:
            return {}
        try:
            raw = self.rfile.read(length)
            if length == 0:
                return {}
            return json.loads(raw)
        except (json.JSONDecodeError, Exception):
            return {}

    def _check_auth(self):
        auth = self.headers.get('Authorization', '')
        if auth == f'Bearer {_auth_state["api_key"]}':
            return True
        if auth == f'Basic {__import__("base64").b64encode(b"admin:" + _auth_state["api_key"].encode()).decode()}':
            return True
        if not auth:
            return True
        return False

    def do_OPTIONS(self):
        self._send_json({})

    def _api_route(self, method, path, params, body):
        if not self._check_auth():
            log.warning(f'Auth failed from {self.client_address[0]}')
            self._send_json({'error': 'unauthorized', 'hint': 'Set Authorization: Bearer <api_key>'}, 401)
            return True

        if path == '/api/status' and method == 'GET':
            sys_info = get_system_info()
            self._send_json({
                'version': '1.0.0',
                'hostname': sys_info.get('hostname', platform.node()),
                'platform': sys_info.get('platform', 'WinVPS'),
                'uptime': sys_info.get('uptime', 'N/A'),
                'memory': sys_info.get('memory', 'N/A'),
                'disk': sys_info.get('disk', 'N/A'),
                'cpu': sys_info.get('cpu', 'N/A'),
                'services': self._scan_services(),
                'tunnels': self._scan_tunnels(),
                'timestamp': datetime.now().isoformat()
            })
            return True

        if path == '/api/services' and method == 'GET':
            self._send_json({'services': self._scan_services()})
            return True

        m = re.match(r'^/api/services/(\w+)/(start|stop)$', path)
        if m and method == 'POST':
            name, action = m.group(1), m.group(2)
            safe = sanitize_service_name(name)
            if not safe:
                self._send_json({'status': 'error', 'message': 'invalid service name'}, 400)
                return True
            if action == 'start':
                script = WINVPS_DIR / 'src' / 'core' / f'{safe}.ps1'
                if script.exists():
                    r = run_cmd(f'powershell -NoProfile -ExecutionPolicy Bypass -File "{script}" start')
                    ok = r['code'] == 0
                    log.info(f'Service start: {safe} -> {"ok" if ok else "fail"}')
                    self._send_json({'status': 'ok' if ok else 'error', 'message': f'{safe} started' if ok else r['stderr'] or r['stdout']})
                else:
                    self._send_json({'status': 'error', 'message': f'No script for {safe}'}, 404)
                return True
            pidf = WINVPS_DIR / 'services' / f'{safe}.pid'
            if pidf.exists():
                try:
                    pid = int(pidf.read_text().strip())
                    run_cmd(f'taskkill /PID {pid} /F 2>nul')
                except (ValueError, Exception):
                    pass
                pidf.unlink(missing_ok=True)
                log.info(f'Service stop: {safe}')
                self._send_json({'status': 'ok', 'message': f'{safe} stopped'})
            else:
                self._send_json({'status': 'error', 'message': f'{safe} not running'}, 404)
            return True

        m = re.match(r'^/api/logs/(\w+)$', path)
        if m and method == 'GET':
            service = m.group(1)
            safe = sanitize_service_name(service)
            if not safe:
                self._send_json({'error': 'invalid service name'}, 400)
                return True
            log_file = WINVPS_DIR / 'logs' / f'{safe}.log'
            if not log_file.exists():
                self._send_json({'error': f'No logs for {safe}'}, 404)
                return True
            lines = sanitize_lines(params.get('lines', 50))
            content = run_cmd(f'powershell -NoProfile -Command "Get-Content \'{log_file}\' -Tail {lines}"')
            self._send_json({'service': safe, 'lines': content['stdout'].split('\n') if content['stdout'] else []})
            return True

        if path == '/api/health' and method == 'GET':
            script = WINVPS_DIR / 'src' / 'core' / 'healthcheck.ps1'
            if script.exists():
                r = run_cmd(f'powershell -NoProfile -ExecutionPolicy Bypass -File "{script}"', timeout=30)
                self._send_json({'status': 'ok' if 'passed' in r['stdout'].lower() else 'issues', 'output': r['stdout']})
            else:
                self._send_json({'status': 'error', 'output': 'healthcheck not found'})
            return True

        if path == '/api/config' and method == 'GET':
            config = {}
            if CONFIG_FILE.exists():
                for line in CONFIG_FILE.read_text(encoding='utf-8', errors='replace').splitlines():
                    line = line.strip()
                    if '=' in line and not line.startswith('#'):
                        k, v = line.split('=', 1)
                        config[k.strip()] = v.strip().strip('"')
            safe_cfg = {k: v for k, v in config.items() if not any(s in k.lower() for s in ['token', 'key', 'secret', 'password'])}
            self._send_json(safe_cfg)
            return True

        if path == '/api/config' and method == 'POST':
            changed = 0
            for k, v in body.items():
                safe_key = sanitize_config_key(k)
                if not safe_key:
                    continue
                if any(s in k.lower() for s in ['token', 'key', 'secret', 'password']):
                    continue
                val = str(v)[:256]
                if CONFIG_FILE.exists():
                    content = CONFIG_FILE.read_text(encoding='utf-8', errors='replace')
                    if re.search(rf'^{safe_key}=', content, re.MULTILINE):
                        content = re.sub(rf'(?m)^{safe_key}=.*', f'{safe_key}="{val}"', content)
                    else:
                        content += f'\n{safe_key}="{val}"'
                    CONFIG_FILE.write_text(content, encoding='utf-8')
                else:
                    CONFIG_FILE.write_text(f'{safe_key}="{val}"\n', encoding='utf-8')
                changed += 1
            log.info(f'Config updated: {changed} keys')
            self._send_json({'status': 'ok', 'changed': changed})
            return True

        if path == '/api/storage' and method == 'GET':
            usage = run_cmd(f'powershell -NoProfile -Command "(Get-ChildItem -Path \'{WINVPS_DIR}\' -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB"', timeout=10)
            drive = str(WINVPS_DIR)[:1].upper()
            df_out = run_cmd(f'powershell -NoProfile -Command "Get-Volume -DriveLetter {drive} | Select-Object Size,SizeRemaining | ConvertTo-Json"', timeout=5)
            self._send_json({
                'winvps_usage_mb': usage['stdout'] if usage['code'] == 0 else 'N/A',
                'disk': json.loads(df_out['stdout']) if df_out['code'] == 0 and df_out['stdout'] else {}
            })
            return True

        if path == '/api/backup' and method == 'POST':
            r = run_cmd(f'powershell -NoProfile -ExecutionPolicy Bypass -File "{WINVPS_DIR / "src" / "cli" / "winvps.ps1"}" backup create', timeout=60)
            log.info(f'Backup created: {"ok" if r["code"] == 0 else "fail"}')
            self._send_json({'status': 'ok' if r['code'] == 0 else 'error', 'output': r['stdout']})
            return True

        if path == '/api/backups' and method == 'GET':
            backup_dir = WINVPS_DIR / 'backup'
            backups = []
            if backup_dir.exists():
                for f in sorted(backup_dir.glob('*.zip'), reverse=True):
                    stat = f.stat()
                    backups.append({'name': f.name, 'size': stat.st_size, 'modified': datetime.fromtimestamp(stat.st_mtime).isoformat()})
            self._send_json({'backups': backups})
            return True

        if path == '/api/apikey' and method == 'GET':
            self._send_json({'api_key': _auth_state['api_key']})
            return True

        if path == '/api/apikey' and method == 'POST':
            new_key = secrets.token_urlsafe(32)
            key_file = WINVPS_DIR / 'config' / 'web-api.key'
            key_file.write_text(new_key)
            key_file.chmod(0o600)
            _auth_state['api_key'] = new_key
            log.info('API key rotated')
            self._send_json({'status': 'ok', 'api_key': new_key})
            return True

        return False

    def _scan_services(self):
        services = []
        svc_dir = WINVPS_DIR / 'services'
        if svc_dir.exists():
            for pidf in sorted(svc_dir.glob('*.pid')):
                name = pidf.stem
                try:
                    pid = int(pidf.read_text().strip())
                except (ValueError, Exception):
                    continue
                alive = run_cmd(f'powershell -NoProfile -Command "if (Get-Process -Id {pid} -ErrorAction SilentlyContinue) {{ \'running\' }} else {{ \'stopped\' }}"', timeout=5)
                mem = '0'
                if alive['stdout'] == 'running':
                    m = run_cmd(f'powershell -NoProfile -Command "(Get-Process -Id {pid}).WorkingSet64 / 1MB"', timeout=5)
                    mem = m['stdout'] if m['code'] == 0 else '0'
                services.append({'name': name, 'pid': pid, 'status': alive['stdout'], 'memory': mem})
        return services

    def _scan_tunnels(self):
        tunnels = {}
        for t in ['cloudflared', 'ngrok', 'bore']:
            r = run_cmd(f'powershell -NoProfile -Command "if (Get-Process -Name {t}* -ErrorAction SilentlyContinue) {{ \'active\' }} else {{ \'inactive\' }}"', timeout=5)
            tunnels[t] = r['stdout'] if r['code'] == 0 else 'unknown'
        return tunnels

    def _serve_static(self, path):
        if not path or path == '/':
            path = '/index.html'
        safe = sanitize_path(path.lstrip('/'))
        if not safe:
            self._send_json({'error': 'invalid path'}, 400)
            return
        file = WWW_DIR / safe
        if file.is_file() and file.resolve().is_relative_to(WWW_DIR.resolve()):
            self._send_file(file)
        else:
            index = WWW_DIR / 'index.html'
            if index.is_file():
                self._send_file(index)
            else:
                self._send_json({'error': 'not found'}, 404)

    def _route(self):
        client_ip = self.client_address[0]
        if not rate_limiter.check(client_ip):
            self._send_json({'error': 'rate limit exceeded'}, 429)
            return

        p = urllib.parse.urlparse(self.path)
        path = p.path.rstrip('/')
        params = {k: v[0] for k, v in urllib.parse.parse_qs(p.query).items()}
        method = self.command
        body = self._read_body() if method == 'POST' else {}

        if path.startswith('/api/'):
            result = self._api_route(method, path, params, body)
            if result:
                return
            self._send_json({'error': 'endpoint not found'}, 404)
        elif method == 'GET':
            self._serve_static(path)
        else:
            self._send_json({'error': 'not found'}, 404)

    def do_GET(self):
        self._route()

    def do_POST(self):
        self._route()

class ThreadedServer(ThreadingMixIn, HTTPServer):
    allow_reuse_address = True
    daemon_threads = True

if __name__ == '__main__':
    WWW_DIR.mkdir(parents=True, exist_ok=True)
    index = WWW_DIR / 'index.html'
    if not index.exists():
        index.write_text('<html><body><h1>WinVPS</h1><p>Dashboard loading...</p></body></html>')
    server = ThreadedServer(('0.0.0.0', PORT), Handler)
    log.info(f'WinVPS Web Dashboard started on port {PORT}')
    print(f'WinVPS Web Dashboard running on http://0.0.0.0:{PORT}')
    print(f'API key: {_auth_state["api_key"][:8]}...')
    print(f'Auth: Authorization: Bearer {_auth_state["api_key"]}')
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log.info('Web dashboard stopped')
        server.shutdown()
