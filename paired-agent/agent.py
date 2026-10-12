#!/usr/bin/env python3
"""Pulse direct-IP agent: authenticated enrollment, pinned TLS, read-only stats.

Python 3.6+ on Linux (openssl); Python 3.10+ on Windows (psutil/cryptography).
The legacy LAN agents are deliberately separate from this public-IP service.
"""
import argparse
import datetime
import hashlib
import hmac
import http.client
import json
import os
import platform
import re
import secrets
import shutil
import socket
import ssl
import subprocess
import threading
import time
from collections import deque
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path
from socketserver import ThreadingMixIn
from urllib.parse import parse_qs, urlsplit

HEX64 = re.compile(r'^[0-9a-f]{64}$')
PROTOCOL = 'pulse-pair-v1'


def digest(value):
    return hashlib.sha256(value.encode('utf-8')).hexdigest()


def atomic_json(path, value):
    temporary = path.with_suffix('.tmp')
    with open(str(temporary), 'w') as stream:
        json.dump(value, stream, separators=(',', ':'))
        stream.flush()
        os.fsync(stream.fileno())
    if os.name != 'nt':
        os.chmod(str(temporary), 0o600)
    os.replace(str(temporary), str(path))


def certificate_fingerprint(directory):
    pem = (directory / 'server.crt').read_text()
    return hashlib.sha256(ssl.PEM_cert_to_DER_cert(pem)).hexdigest()


def verification_code(fingerprint):
    value = fingerprint[:16].upper()
    return '-'.join(value[i:i + 4] for i in range(0, 16, 4))


def ensure_certificate(directory):
    cert, key = directory / 'server.crt', directory / 'server.key'
    if cert.exists() and key.exists():
        return
    if platform.system() == 'Windows':
        from cryptography import x509
        from cryptography.x509.oid import NameOID
        from cryptography.hazmat.primitives import hashes, serialization
        from cryptography.hazmat.primitives.asymmetric import rsa
        private = rsa.generate_private_key(public_exponent=65537, key_size=3072)
        subject = x509.Name([x509.NameAttribute(NameOID.COMMON_NAME, 'Pulse Agent')])
        now = datetime.datetime.now(datetime.timezone.utc)
        certificate = (x509.CertificateBuilder().subject_name(subject).issuer_name(subject)
                       .public_key(private.public_key()).serial_number(x509.random_serial_number())
                       .not_valid_before(now - datetime.timedelta(minutes=5))
                       .not_valid_after(now + datetime.timedelta(days=3650))
                       .add_extension(x509.BasicConstraints(ca=False, path_length=None), critical=True)
                       .sign(private, hashes.SHA256()))
        key.write_bytes(private.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                                             serialization.NoEncryption()))
        cert.write_bytes(certificate.public_bytes(serialization.Encoding.PEM))
    else:
        subprocess.run(['openssl', 'req', '-x509', '-newkey', 'rsa:3072', '-sha256', '-nodes',
                        '-days', '3650', '-subj', '/CN=Pulse Agent', '-keyout', str(key), '-out', str(cert)],
                       check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        os.chmod(str(key), 0o600)


def configure(directory, token, expires, bind, port):
    if not HEX64.fullmatch(token):
        raise ValueError('Pairing token must be 64 lowercase hexadecimal characters')
    now = int(time.time())
    if not now < expires <= now + 660:
        raise ValueError('Pairing command expired. Generate a fresh command in Pulse (check both clocks).')
    if not 1024 <= port <= 65535:
        raise ValueError('Port must be 1024–65535')
    directory.mkdir(parents=True, exist_ok=True)
    ensure_certificate(directory)
    path = directory / 'state.json'
    previous = json.loads(path.read_text()) if path.exists() else {}
    # A consumed command must never reopen enrollment, even if rerun locally.
    if previous.get('last_token_hash') == digest(token) and not previous.get('pairing_token'):
        raise ValueError('This pairing command was already used. Generate a new command in Pulse.')
    value = {'device_id': previous.get('device_id', secrets.token_hex(16)), 'bind': bind, 'port': port,
             'pairing_token': token, 'expires': expires, 'last_token_hash': digest(token)}
    # An explicitly new enrollment replaces/revokes the prior controller.
    atomic_json(path, value)
    print('Pairing ready. Verify this code in Pulse: ' + verification_code(certificate_fingerprint(directory)))
    print('HTTPS port: {}. Waiting for approval; no telemetry is accessible yet.'.format(port))


class Enrollment:
    def __init__(self, directory):
        self.path = directory / 'state.json'
        self.state = json.loads(self.path.read_text())
        self.fingerprint = certificate_fingerprint(directory)
        self.lock = threading.Lock()

    def active_token(self):
        token = self.state.get('pairing_token')
        if token and time.time() >= self.state['expires']:
            replacement = dict(self.state)
            replacement.pop('pairing_token', None)
            atomic_json(self.path, replacement)
            self.state = replacement
            return None
        return token

    def info(self, nonce):
        if not HEX64.fullmatch(nonce):
            return None
        with self.lock:
            token = self.active_token()
            if not token:
                return None
            payload = {'protocol': PROTOCOL, 'nonce': nonce, 'device_id': self.state['device_id'],
                       'hostname': socket.gethostname()[:128], 'os': platform.system(),
                       'expires': self.state['expires'], 'fingerprint': self.fingerprint}
            # Sign exact bytes, avoiding cross-language JSON canonicalization.
            encoded = json.dumps(payload, separators=(',', ':'), ensure_ascii=True)
            signature = hmac.new(bytes.fromhex(token), encoded.encode('utf-8'), hashlib.sha256).hexdigest()
            return {'payload': encoded, 'proof': signature}

    def approve(self, token, credential):
        if not HEX64.fullmatch(token) or not HEX64.fullmatch(credential):
            return False
        with self.lock:
            active = self.active_token()
            if not active or not hmac.compare_digest(active, token):
                return False
            replacement = dict(self.state)
            replacement.pop('pairing_token', None)
            replacement.pop('expires', None)
            replacement['credential_hash'] = digest(credential)
            atomic_json(self.path, replacement)
            self.state = replacement
            return True

    def authorized(self, credential):
        with self.lock:
            expected = self.state.get('credential_hash', '')
            return bool(expected and HEX64.fullmatch(credential) and hmac.compare_digest(expected, digest(credential)))

    def revoke(self, credential):
        with self.lock:
            expected = self.state.get('credential_hash') or self.state.get('revoked_credential_hash', '')
            if not expected or not HEX64.fullmatch(credential) or not hmac.compare_digest(expected, digest(credential)):
                return False
            replacement = dict(self.state)
            replacement.pop('credential_hash', None)
            replacement['revoked_credential_hash'] = expected
            atomic_json(self.path, replacement)
            self.state = replacement
            return True


class Sampler:
    def __init__(self):
        self.snapshot = None
        self.lock = threading.Lock()
        self.previous_cpu = None

    def collect(self):
        if platform.system() == 'Windows':
            import psutil
            memory = psutil.virtual_memory()
            cpu = {'percent': psutil.cpu_percent(interval=0.25), 'logical_cores': psutil.cpu_count() or 1,
                   'physical_cores': psutil.cpu_count(logical=False) or psutil.cpu_count() or 1}
            used, total = memory.total - memory.available, memory.total
            uptime = int(time.time() - psutil.boot_time())
            disk_path = os.environ.get('SystemDrive', 'C:') + '\\'
        else:
            with open('/proc/stat') as stream:
                fields = [int(x) for x in stream.readline().split()[1:9]]
            current = (sum(fields), fields[3] + fields[4])
            previous = self.previous_cpu or current
            self.previous_cpu = current
            delta = current[0] - previous[0]
            percent = max(0, min(100, 100 * (1 - (current[1] - previous[1]) / delta))) if delta else 0
            cpu = {'percent': round(percent, 1), 'logical_cores': os.cpu_count() or 1, 'physical_cores': os.cpu_count() or 1}
            with open('/proc/meminfo') as stream:
                values = {line.split(':')[0]: int(line.split()[1]) * 1024 for line in stream}
            total = values['MemTotal']
            available = values.get('MemAvailable', values.get('MemFree', 0) + values.get('Cached', 0) + values.get('Buffers', 0))
            used = max(0, min(total, total - available))
            with open('/proc/uptime') as stream:
                uptime = int(float(stream.read().split()[0]))
            disk_path = '/'
        disk = shutil.disk_usage(disk_path)
        gpu = {'available': False}
        if platform.system() == 'Windows':
            try:
                output = subprocess.check_output(['nvidia-smi', '--query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu,name',
                                                  '--format=csv,noheader,nounits'], timeout=2,
                                                 creationflags=getattr(subprocess, 'CREATE_NO_WINDOW', 0)).decode()
                util, used_mb, total_mb, temp, name = [x.strip() for x in output.splitlines()[0].split(',', 4)]
                gpu = {'available': True, 'name': name, 'utilization_percent': float(util), 'vram_used_mb': float(used_mb),
                       'vram_total_mb': float(total_mb), 'temperature_c': float(temp)}
            except (OSError, subprocess.SubprocessError, ValueError, IndexError):
                pass
        return {'hostname': socket.gethostname(), 'os': platform.system() + ' ' + platform.release(),
                'timestamp': datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ'),
                'uptime_seconds': uptime, 'cpu': cpu,
                'memory': {'used_gb': round(used / 1024**3, 2), 'total_gb': round(total / 1024**3, 2),
                           'percent': round(used / total * 100, 1) if total else 0},
                'gpu': gpu, 'disk': {'path': disk_path, 'used_gb': round(disk.used / 1024**3, 2),
                                     'total_gb': round(disk.total / 1024**3, 2),
                                     'percent': round(disk.used / disk.total * 100, 1)}}

    def run(self):
        while True:
            try:
                sample = self.collect()
            except Exception:
                sample = None
            with self.lock:
                self.snapshot = sample
            time.sleep(2)


class AgentServer(ThreadingMixIn, HTTPServer):
    daemon_threads = True
    allow_reuse_address = True
    request_queue_size = 16

    def __init__(self, address, enrollment, sampler, context):
        self.enrollment, self.sampler, self.context = enrollment, sampler, context
        self.slots = threading.BoundedSemaphore(16)
        self.rate_lock = threading.Lock()
        self.requests = deque()
        if ':' in address[0]:
            self.address_family = socket.AF_INET6
        super().__init__(address, Handler)

    def allow_request(self):
        with self.rate_lock:
            now = time.monotonic()
            while self.requests and self.requests[0] < now - 60:
                self.requests.popleft()
            if len(self.requests) >= 180:
                return False
            self.requests.append(now)
            return True

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
            request.settimeout(5)
            # Handshake occurs in a bounded worker, never in the accept loop.
            request = self.context.wrap_socket(request, server_side=True)
            super().process_request_thread(request, address)
        except (OSError, ssl.SSLError):
            self.shutdown_request(request)
        finally:
            self.slots.release()

    def handle_error(self, request, client_address):
        pass  # Don't leak headers, tokens, or request bodies into logs.


class Handler(BaseHTTPRequestHandler):
    server_version = 'Pulse'
    sys_version = ''

    def log_message(self, *_args):
        pass

    def reply(self, status, body):
        data = json.dumps(body, allow_nan=False).encode('utf-8')
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('Content-Length', str(len(data)))
        self.send_header('Connection', 'close')
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if not self.server.allow_request():
            return self.reply(429, {'error': 'Rate limited'})
        url = urlsplit(self.path)
        if url.path == '/pairing':
            nonce = parse_qs(url.query).get('nonce', [''])[0]
            info = self.server.enrollment.info(nonce)
            return self.reply(200, info) if info else self.reply(410, {'error': 'Pairing unavailable or expired'})
        if url.path == '/health':
            return self.reply(200, {'ok': True})
        if url.path != '/stats':
            return self.reply(404, {'error': 'Not found'})
        if not self.server.enrollment.authorized(self.headers.get('X-API-Key', '')):
            return self.reply(401, {'error': 'Not authorized'})
        with self.server.sampler.lock:
            sample = self.server.sampler.snapshot
        return self.reply(200, sample) if sample else self.reply(503, {'error': 'Waiting for sample'})

    def do_POST(self):
        if not self.server.allow_request():
            return self.reply(429, {'error': 'Rate limited'})
        if self.path == '/revoke':
            if self.server.enrollment.revoke(self.headers.get('X-API-Key', '')):
                return self.reply(200, {'revoked': True})
            return self.reply(401, {'error': 'Not authorized'})
        if self.path != '/pairing/approve':
            return self.reply(404, {'error': 'Not found'})
        try:
            length = int(self.headers.get('Content-Length', '0'))
            if not 0 < length <= 4096 or self.headers.get('Transfer-Encoding'):
                return self.reply(413, {'error': 'Invalid body size'})
            value = json.loads(self.rfile.read(length).decode('utf-8'))
            token, credential = value.get('token', ''), value.get('credential', '')
            if not isinstance(token, str) or not isinstance(credential, str):
                raise ValueError('Invalid fields')
            accepted = self.server.enrollment.approve(token, credential)
        except (ValueError, AttributeError, UnicodeError):
            return self.reply(400, {'error': 'Invalid request'})
        return self.reply(200, {'approved': True}) if accepted else self.reply(403, {'error': 'Pairing unavailable'})


def check_service(directory):
    enrollment = Enrollment(directory)
    # Local installer check: explicitly compare the known certificate before
    # sending any HTTP request. This is not an unverified remote connection.
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    context.check_hostname = False
    context.verify_mode = ssl.CERT_NONE
    for _ in range(12):
        connection = http.client.HTTPSConnection('127.0.0.1', enrollment.state['port'], context=context, timeout=2)
        try:
            connection.connect()
            actual = hashlib.sha256(connection.sock.getpeercert(binary_form=True)).hexdigest()
            if not hmac.compare_digest(actual, enrollment.fingerprint):
                raise ValueError('Another certificate is serving the requested port')
            connection.request('GET', '/health')
            response = connection.getresponse()
            if response.status == 200 and json.loads(response.read(1024)).get('ok') is True:
                print('Verified: local HTTPS agent is healthy and presents the expected certificate.')
                return
        except (OSError, ValueError):
            pass
        finally:
            connection.close()
        time.sleep(0.5)
    raise RuntimeError('HTTPS health check failed. Check service logs and whether the port is already in use.')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--state-dir', required=True)
    parser.add_argument('--configure', action='store_true')
    parser.add_argument('--check', action='store_true')
    parser.add_argument('--token', default='')
    parser.add_argument('--expires', type=int, default=0)
    parser.add_argument('--bind', default='0.0.0.0')
    parser.add_argument('--port', type=int, default=8843)
    args = parser.parse_args()
    directory = Path(args.state_dir)
    if args.check:
        check_service(directory)
        return
    if args.configure:
        configure(directory, args.token, args.expires, args.bind, args.port)
        return
    enrollment = Enrollment(directory)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    if hasattr(ssl, 'TLSVersion'):
        context.minimum_version = ssl.TLSVersion.TLSv1_2
    else:
        context.options |= ssl.OP_NO_TLSv1 | ssl.OP_NO_TLSv1_1
    context.load_cert_chain(str(directory / 'server.crt'), str(directory / 'server.key'))
    sampler = Sampler()
    threading.Thread(target=sampler.run, daemon=True).start()
    server = AgentServer((enrollment.state['bind'], enrollment.state['port']), enrollment, sampler, context)
    server.serve_forever()


if __name__ == '__main__':
    main()
