#!/usr/bin/env bash
# Self-contained Pulse Linux agent installer. Ubuntu/Debian/Oracle Linux.
# Usage: sudo bash install.sh [--bind 127.0.0.1] [--port 8801]
set -euo pipefail
umask 077

BIND_OVERRIDE=''
PORT_OVERRIDE=''
while (($#)); do
    case "$1" in
        --bind) BIND_OVERRIDE="${2:?--bind requires an IP address}"; shift 2 ;;
        --port) PORT_OVERRIDE="${2:?--port requires a port}"; shift 2 ;;
        --help|-h) echo 'Usage: sudo bash install.sh [--bind IP] [--port PORT]'; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done
[[ "$(uname -s)" == Linux ]] || { echo 'This installer requires Linux.' >&2; exit 1; }
[[ "$EUID" == 0 ]] || { echo 'Run with sudo bash install.sh (or pipe to sudo bash).' >&2; exit 1; }
command -v systemctl >/dev/null || { echo 'A systemd-based Linux distribution is required.' >&2; exit 1; }
if ! command -v python3 >/dev/null; then
    if command -v apt-get >/dev/null; then
        apt-get update
        apt-get install -y python3
    elif command -v dnf >/dev/null; then
        dnf install -y python3
    elif command -v yum >/dev/null; then
        yum install -y python3
    else
        echo 'Install Python 3.6+ and rerun this script.' >&2; exit 1
    fi
fi
python3 -c 'import sys; assert sys.version_info >= (3, 6), "Python 3.6+ required"'
install -d -m 755 /opt/pulse-agent
install -d -m 700 /etc/pulse-agent

# Keep the existing API key and connection settings on every reinstall.
python3 - "$BIND_OVERRIDE" "$PORT_OVERRIDE" <<'PY'
import ipaddress, json, os, secrets, sys
path = '/etc/pulse-agent/config.json'
config = {'host': '127.0.0.1', 'port': 8801, 'api_key': secrets.token_hex(32)}
if os.path.exists(path):
    with open(path) as f:
        config.update(json.load(f))
if sys.argv[1]: config['host'] = sys.argv[1]
if sys.argv[2]: config['port'] = int(sys.argv[2])
ipaddress.ip_address(config['host'])
assert isinstance(config['port'], int) and 1024 <= config['port'] <= 65535, 'Port must be 1024–65535'
assert isinstance(config['api_key'], str) and len(config['api_key']) >= 32, 'Existing API key must be at least 32 characters'
# A hex key is safe to use in a systemd EnvironmentFile without escaping.
assert all(c in '0123456789abcdefABCDEF' for c in config['api_key']), 'API key must be hexadecimal'
with open(path + '.tmp', 'w') as f:
    json.dump(config, f, indent=2)
os.chmod(path + '.tmp', 0o600)
os.replace(path + '.tmp', path)
with open('/etc/pulse-agent/agent.env.tmp', 'w') as f:
    f.write('PULSE_BIND={}\nPULSE_PORT={}\nPULSE_API_KEY={}\n'.format(config['host'], config['port'], config['api_key']))
os.chmod('/etc/pulse-agent/agent.env.tmp', 0o600)
os.replace('/etc/pulse-agent/agent.env.tmp', '/etc/pulse-agent/agent.env')
PY

cat > /opt/pulse-agent/agent.py.new <<'PY_AGENT'
#!/usr/bin/env python3
"""Read-only Linux telemetry using only Python's standard library and /proc."""
import datetime
import hmac
import json
import os
import platform
import shutil
import socket
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
from socketserver import ThreadingMixIn

GIB = 1024 ** 3


def read_cpu(path='/proc/stat'):
    with open(path) as source:
        values = [int(value) for value in source.readline().split()[1:9]]
    # guest/guest_nice are already counted in user/nice, so omit them.
    return sum(values), values[3] + (values[4] if len(values) > 4 else 0)


def cpu_percent(previous, current):
    total = current[0] - previous[0]
    idle = current[1] - previous[1]
    return round(max(0.0, min(100.0, 100.0 * (total - idle) / total)), 1) if total > 0 else 0.0


def memory_stats(path='/proc/meminfo'):
    with open(path) as source:
        values = {line.split(':', 1)[0]: int(line.split()[1]) * 1024 for line in source if ':' in line}
    total = values['MemTotal']
    available = values.get('MemAvailable')
    if available is None:
        available = sum(values.get(key, 0) for key in ('MemFree', 'Buffers', 'Cached', 'SReclaimable')) - values.get('Shmem', 0)
    used = max(0, min(total, total - available))
    return {'used_gb': round(used / GIB, 2), 'total_gb': round(total / GIB, 2),
            'percent': round(100 * used / total, 1) if total else 0.0}


def physical_cores(path='/proc/cpuinfo'):
    with open(path) as source:
        blocks = source.read().strip().split('\n\n')
    cores = set()
    for block in blocks:
        fields = dict(line.split(':', 1) for line in block.splitlines() if ':' in line)
        fields = {key.strip(): value.strip() for key, value in fields.items()}
        if 'physical id' in fields and 'core id' in fields:
            cores.add((fields['physical id'], fields['core id']))
    # ARM/VPS kernels may not expose physical topology.
    return len(cores) or os.cpu_count() or 1


class Sampler:
    def __init__(self):
        self.lock = threading.Lock()
        self.snapshot = None
        self.cores = physical_cores()
        self.previous = read_cpu()

    def collect(self):
        current = read_cpu()
        percent = cpu_percent(self.previous, current)
        self.previous = current
        disk = shutil.disk_usage('/')
        with open('/proc/uptime') as source:
            uptime = int(float(source.read().split()[0]))
        return {
            'hostname': socket.gethostname(),
            'os': '{} {}'.format(platform.system(), platform.release()),
            'timestamp': datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
            'uptime_seconds': uptime,
            'cpu': {'percent': percent, 'logical_cores': os.cpu_count() or 1, 'physical_cores': self.cores},
            'memory': memory_stats(),
            'gpu': {'available': False},
            'disk': {'path': '/', 'used_gb': round(disk.used / GIB, 2), 'total_gb': round(disk.total / GIB, 2),
                     'percent': round(100 * disk.used / disk.total, 1) if disk.total else 0.0}
        }

    def run(self):
        while True:
            time.sleep(1)
            try:
                snapshot = self.collect()
                with self.lock:
                    self.snapshot = snapshot
            except (OSError, ValueError, KeyError):
                # Don't serve stale metrics as if they were freshly collected.
                with self.lock:
                    self.snapshot = None


class StatsServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True
    allow_reuse_address = True
    request_queue_size = 16

    def __init__(self, address, sampler, api_key):
        self.sampler = sampler
        self.api_key = api_key.encode('utf-8')
        self.slots = threading.BoundedSemaphore(16)
        if ':' in address[0]:
            self.address_family = socket.AF_INET6
        super().__init__(address, Handler)

    def process_request(self, request, address):
        if not self.slots.acquire(blocking=False):
            self.shutdown_request(request)
            return
        try:
            super().process_request(request, address)
        except Exception:
            self.slots.release()
            raise

    def process_request_thread(self, request, address):
        try:
            super().process_request_thread(request, address)
        finally:
            self.slots.release()


class Handler(BaseHTTPRequestHandler):
    server_version = 'Pulse'
    sys_version = ''

    def setup(self):
        self.request.settimeout(5)
        super().setup()

    def log_message(self, *_args):
        pass  # Never log request headers or API keys.

    def reply(self, status, body):
        data = json.dumps(body, allow_nan=False).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path == '/health':
            self.reply(200, {'ok': True})
            return
        if self.path != '/stats':
            self.reply(404, {'error': 'Not found'})
            return
        key = self.headers.get('X-API-Key', '').encode('utf-8')
        if not hmac.compare_digest(key, self.server.api_key):
            self.reply(401, {'error': 'Missing or invalid API key'})
            return
        with self.server.sampler.lock:
            snapshot = self.server.sampler.snapshot
        if snapshot is None:
            self.reply(503, {'error': 'Waiting for a system sample'})
        else:
            self.reply(200, snapshot)


def main():
    key = os.environ.get('PULSE_API_KEY', '')
    if len(key) < 32:
        raise SystemExit('PULSE_API_KEY must contain at least 32 characters')
    sampler = Sampler()
    threading.Thread(target=sampler.run, daemon=True).start()
    server = StatsServer((os.environ.get('PULSE_BIND', '127.0.0.1'), int(os.environ.get('PULSE_PORT', '8801'))), sampler, key)
    server.serve_forever(poll_interval=0.5)


if __name__ == '__main__':
    main()
PY_AGENT
python3 -c 'import ast; ast.parse(open("/opt/pulse-agent/agent.py.new").read())'
chmod 644 /opt/pulse-agent/agent.py.new
mv /opt/pulse-agent/agent.py.new /opt/pulse-agent/agent.py

cat > /etc/systemd/system/pulse-agent.service <<'SERVICE'
[Unit]
Description=Pulse read-only system stats
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
DynamicUser=yes
EnvironmentFile=/etc/pulse-agent/agent.env
ExecStart=/usr/bin/python3 -B /opt/pulse-agent/agent.py
Restart=on-failure
RestartSec=5
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes
PrivateTmp=yes
PrivateDevices=yes
ProtectKernelTunables=yes
ProtectKernelModules=yes
ProtectControlGroups=yes
RestrictSUIDSGID=yes
RestrictAddressFamilies=AF_INET AF_INET6 AF_UNIX
CapabilityBoundingSet=
UMask=0077

[Install]
WantedBy=multi-user.target
SERVICE
chmod 644 /etc/systemd/system/pulse-agent.service
systemctl daemon-reload
systemctl enable pulse-agent.service
systemctl restart pulse-agent.service

# Authenticate a real stats request; don't report success on a mere open port.
python3 - <<'PY'
import json, time, urllib.request, urllib.error
with open('/etc/pulse-agent/config.json') as f:
    config = json.load(f)
host = config['host']
if host == '0.0.0.0': host = '127.0.0.1'
if host == '::': host = '::1'
if ':' in host: host = '[' + host + ']'
url = 'http://{}:{}/stats'.format(host, config['port'])
opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
for attempt in range(15):
    try:
        request = urllib.request.Request(url, headers={'X-API-Key': config['api_key']})
        with opener.open(request, timeout=2) as response:
            stats = json.load(response)
        break
    except (OSError, ValueError):
        time.sleep(1)
else:
    raise SystemExit('Service failed its stats check. Run: sudo journalctl -u pulse-agent -n 40 --no-pager')
print('\nPulse agent installed and running (starts automatically on boot).')
print('Detected: {} vCPU, {} GiB RAM'.format(stats['cpu']['logical_cores'], stats['memory']['total_gb']))
print('Bind address: {}   Port: {}'.format(config['host'], config['port']))
print('API key: {}'.format(config['api_key']))
if config['host'] in ('127.0.0.1', '::1'):
    print('\nOn your Mac, keep this SSH tunnel running (replace USER and VPS_IP):')
    target = '[::1]' if config['host'] == '::1' else '127.0.0.1'
    print('ssh -N -o ExitOnForwardFailure=yes -o ServerAliveInterval=30 -o ServerAliveCountMax=3 -L 127.0.0.1:8802:{}:{} USER@VPS_IP'.format(target, config['port']))
    print('Pulse > Advanced > Settings > Oracle VPS: host 127.0.0.1, port 8802, HTTPS off, API key above.')
else:
    print('\nIn Pulse, use the reachable private/VPN address, this port, and the API key above.')
    print('Direct public access needs an HTTPS reverse proxy. No firewall or Oracle Cloud rules were changed.')
PY
