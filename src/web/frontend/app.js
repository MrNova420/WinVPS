/* ============================================================
   WinVPS Dashboard — App Logic v2.0
   ============================================================ */

const BASE = '';
let refreshInterval;
let currentTab = 'overview';

// --- Utilities ---
function escapeHtml(str) {
  return String(str).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');
}

function toast(msg, isError = false) {
  const t = document.getElementById('toast');
  t.textContent = msg;
  t.className = 'toast' + (isError ? ' error' : '');
  t.classList.add('show');
  setTimeout(() => t.classList.remove('show'), 3000);
}

function formatBytes(bytes) {
  if (bytes === 0) return '0 B';
  const k = 1024;
  const sizes = ['B', 'KB', 'MB', 'GB'];
  const i = Math.floor(Math.log(bytes) / Math.log(k));
  return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + ' ' + sizes[i];
}

// --- API ---
async function api(url, opts = {}) {
  const r = await fetch(BASE + url, {
    headers: { 'Accept': 'application/json', ...opts.headers },
    ...opts
  });
  if (!r.ok) {
    const text = await r.text();
    throw new Error(text || `HTTP ${r.status}`);
  }
  return r.json();
}

// --- Tab Navigation ---
function switchTab(name) {
  currentTab = name;
  document.querySelectorAll('.tab-content').forEach(t => t.classList.remove('active'));
  document.querySelectorAll('.nav a').forEach(a => a.classList.remove('active'));
  const tab = document.getElementById('tab-' + name);
  if (tab) tab.classList.add('active');
  const nav = document.querySelector('.nav a[onclick*="' + name + '"]');
  if (nav) nav.classList.add('active');
}

// --- Overview ---
async function loadOverview() {
  try {
    const d = await api('/api/status');
    document.getElementById('hostname').innerHTML = (d.hostname || 'Unknown') + ' <span class="platform-badge">' + (d.platform || 'WinVPS') + '</span>';
    document.getElementById('uptime').textContent = d.uptime || '';
    document.getElementById('statusBadge').innerHTML = '<span class="dot"></span> Online';
    document.getElementById('statusBadge').className = 'status-badge online';

    // CPU
    const cpuEl = document.getElementById('cpu');
    const cpuPct = parseInt(d.cpu) || 0;
    cpuEl.textContent = d.cpu || '-';
    cpuEl.className = 'value ' + (cpuPct > 80 ? 'red' : cpuPct > 60 ? 'yellow' : 'green');
    document.getElementById('cpuBar').style.width = cpuPct + '%';
    document.getElementById('cpuBar').className = 'fill ' + (cpuPct > 80 ? 'red' : cpuPct > 60 ? 'yellow' : 'green');

    // Memory
    const memEl = document.getElementById('memory');
    memEl.textContent = d.memory || '-';
    const memPct = d.memory ? parseInt(d.memory) : 0;
    memEl.className = 'value ' + (memPct > 80 ? 'red' : memPct > 60 ? 'yellow' : 'green');
    document.getElementById('memBar').style.width = memPct + '%';
    document.getElementById('memBar').className = 'fill ' + (memPct > 80 ? 'red' : memPct > 60 ? 'yellow' : 'green');

    // Disk
    document.getElementById('disk').textContent = d.disk || '-';

    // Services count
    const running = (d.services || []).filter(s => s.status === 'running').length;
    const total = (d.services || []).length;
    document.getElementById('svcCount').textContent = running + '/' + total;

    // Tunnels
    const tl = document.getElementById('tunnelList');
    tl.innerHTML = '';
    for (const [k, v] of Object.entries(d.tunnels || {})) {
      const card = document.createElement('div');
      card.className = 'tunnel-card';
      card.innerHTML = '<div class="tunnel-name"><span class="tunnel-status"><span class="dot ' + (v === 'active' ? 'active' : 'inactive') + '"></span></span>' + escapeHtml(k) + '</div>' +
        '<span class="badge ' + (v === 'active' ? 'running' : 'stopped') + '">' + v + '</span>';
      tl.appendChild(card);
    }
  } catch (e) {
    document.getElementById('statusBadge').innerHTML = '<span class="dot"></span> Offline';
    document.getElementById('statusBadge').className = 'status-badge offline';
  }
}

// --- Services ---
async function loadServices() {
  try {
    const d = await api('/api/services');
    const el = document.getElementById('serviceList');
    if (!d.services || d.services.length === 0) {
      el.innerHTML = '<div class="panel-header"><h2>Services</h2></div><div class="service-row"><span style="color:var(--text-secondary)">No services running</span></div>';
      return;
    }
    let html = '<div class="panel-header"><h2>Services</h2><button class="primary sm" onclick="showAddServiceModal()">+ Add Service</button></div>';
    for (const s of d.services) {
      const typeClass = s.type || 'ps';
      html += '<div class="service-row">' +
        '<div class="service-info">' +
          '<span class="name">' + escapeHtml(s.name) + '</span>' +
          '<div class="meta">' +
            '<span class="badge type">' + escapeHtml(typeClass) + '</span>' +
            (s.port ? '<span>:' + escapeHtml(s.port) + '</span>' : '') +
            (s.pid ? '<span>PID ' + s.pid + '</span>' : '') +
            (s.memory ? '<span>' + parseFloat(s.memory).toFixed(1) + ' MB</span>' : '') +
          '</div>' +
        '</div>' +
        '<div class="service-actions">' +
          '<span class="badge ' + s.status + '">' + s.status + '</span>' +
          '<button class="sm" onclick="serviceAction(\'' + escapeHtml(s.name) + '\',\'start\')" title="Start">▶</button>' +
          '<button class="sm" onclick="serviceAction(\'' + escapeHtml(s.name) + '\',\'stop\')" title="Stop">■</button>' +
          '<button class="sm danger" onclick="serviceAction(\'' + escapeHtml(s.name) + '\',\'remove\')" title="Remove">✕</button>' +
        '</div>' +
      '</div>';
    }
    el.innerHTML = html;
  } catch (e) { console.error('loadServices:', e); }
}

async function serviceAction(name, action) {
  try {
    let url, method;
    if (action === 'remove') {
      url = '/api/services/' + name + '/remove';
      method = 'POST';
    } else {
      url = '/api/services/' + name + '/' + action;
      method = 'POST';
    }
    const r = await api(url, { method });
    toast(r.message || action + ' ' + name);
    setTimeout(loadServices, 1000);
  } catch (e) { toast(e.message, true); }
}

function showAddServiceModal() {
  document.getElementById('addServiceModal').classList.add('active');
}

function hideAddServiceModal() {
  document.getElementById('addServiceModal').classList.remove('active');
}

async function submitAddService() {
  const name = document.getElementById('addName').value.trim();
  const path = document.getElementById('addPath').value.trim();
  const type = document.getElementById('addType').value;
  const port = document.getElementById('addPort').value.trim();
  const autoStart = document.getElementById('addAuto').checked;
  const health = document.getElementById('addHealth').value.trim();
  const desc = document.getElementById('addDesc').value.trim();

  if (!name || !path) {
    toast('Name and path are required', true);
    return;
  }

  try {
    const r = await api('/api/services/add', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ name, path, type, port: parseInt(port) || 0, auto_start: autoStart, health_check: health, description: desc })
    });
    toast(r.message || 'Service added');
    hideAddServiceModal();
    loadServices();
    loadLogSelector();
  } catch (e) { toast(e.message, true); }
}

// --- Logs ---
async function loadLogSelector() {
  try {
    const d = await api('/api/services');
    const sel = document.getElementById('logSelector');
    sel.innerHTML = '<option value="">Select service...</option>';
    const services = (d.services || []).map(s => s.name);
    // Also add common log names
    const common = ['ssh', 'web', 'fail2ban', 'healthcheck', 'tamper', 'obfuscate', 'update', 'web-dashboard'];
    const all = [...new Set([...services, ...common])];
    for (const s of all) {
      sel.innerHTML += '<option value="' + escapeHtml(s) + '">' + escapeHtml(s) + '</option>';
    }
  } catch (e) {}
}

async function refreshLogs() {
  const sel = document.getElementById('logSelector');
  const out = document.getElementById('logOutput');
  if (!sel.value) { out.innerHTML = '<div class="line">Select a service to view logs</div>'; return; }
  try {
    const d = await api('/api/logs/' + sel.value + '?lines=100');
    out.innerHTML = (d.lines || []).map(l => '<div class="line">' + escapeHtml(l) + '</div>').join('');
    out.scrollTop = out.scrollHeight;
  } catch (e) {
    out.innerHTML = '<div class="line error">Error: ' + escapeHtml(e.message) + '</div>';
  }
}

// --- Config ---
async function loadConfig() {
  try {
    const d = await api('/api/config');
    const form = document.getElementById('configForm');
    form.innerHTML = '';
    const important = ['WINVPS_SSH_PORT', 'WINVPS_WEB_PORT', 'WINVPS_TIER', 'WINVPS_AUTO_UPDATE',
      'WINVPS_TUNNEL_TYPE', 'WINVPS_WATCHDOG', 'WINVPS_TAILSCALE_HOSTNAME'];
    const entries = Object.entries(d).sort((a, b) => {
      const ai = important.indexOf(a[0]); const bi = important.indexOf(b[0]);
      return (ai === -1 ? 999 : ai) - (bi === -1 ? 999 : bi);
    });
    for (const [k, v] of entries) {
      const group = document.createElement('div');
      group.className = 'form-group';
      group.innerHTML = '<label>' + escapeHtml(k) + '</label><input type="text" name="' + escapeHtml(k) + '" value="' + escapeHtml(v) + '">';
      form.appendChild(group);
    }
  } catch (e) { console.error('loadConfig:', e); }
}

async function saveConfig() {
  const form = document.getElementById('configForm');
  const data = {};
  form.querySelectorAll('input').forEach(i => { if (i.name) data[i.name] = i.value; });
  try {
    await api('/api/config', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(data)
    });
    toast('Configuration saved');
  } catch (e) { toast(e.message, true); }
}

// --- Storage ---
async function loadStorage() {
  try {
    const d = await api('/api/storage');
    document.getElementById('storageUsage').textContent = d.winvps_usage_mb ? parseFloat(d.winvps_usage_mb).toFixed(1) + ' MB' : '-';
  } catch (e) {}
  try {
    const d = await api('/api/backups');
    document.getElementById('backupCount').textContent = d.backups.length;
    const el = document.getElementById('backupList');
    if (d.backups.length === 0) {
      el.innerHTML = '<div class="panel-header"><h2>Backups</h2></div><div class="backup-row"><span style="color:var(--text-secondary)">No backups yet</span></div>';
      return;
    }
    let html = '<div class="panel-header"><h2>Backups</h2></div>';
    for (const b of d.backups) {
      const size = formatBytes(b.size);
      html += '<div class="backup-row"><span class="name">' + escapeHtml(b.name) + '</span><span style="color:var(--text-secondary)">' + size + '</span><span style="color:var(--text-secondary);font-size:12px">' + new Date(b.modified).toLocaleString() + '</span></div>';
    }
    el.innerHTML = html;
  } catch (e) {}
}

async function createBackup() {
  try {
    const r = await api('/api/backup', { method: 'POST' });
    toast('Backup created');
    setTimeout(loadStorage, 2000);
  } catch (e) { toast(e.message, true); }
}

// --- Init ---
document.addEventListener('DOMContentLoaded', () => {
  loadOverview();
  loadServices();
  loadLogSelector();
  loadConfig();
  loadStorage();
  refreshInterval = setInterval(() => {
    loadOverview();
    loadServices();
  }, 5000);
});
