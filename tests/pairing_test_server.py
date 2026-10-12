"""Ephemeral, local HTTPS fixture for the real Swift networking implementation."""
import importlib.util
import json
from pathlib import Path
import ssl
import sys
import threading
import time

root = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('paired_agent', root / 'paired-agent/agent.py')
agent = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agent)
directory = Path(sys.argv[1])
state = directory / 'tls-state'
token = 'a' * 64
expires = int(time.time()) + 600
agent.platform.system = lambda: 'Linux'
agent.configure(state, token, expires, '127.0.0.1', 8843)
enrollment = agent.Enrollment(state)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.minimum_version = ssl.TLSVersion.TLSv1_2
context.load_cert_chain(str(state / 'server.crt'), str(state / 'server.key'))
class Sampler:
    lock = threading.Lock()
    snapshot = json.loads((directory / 'linux-stats.json').read_text())
class TestHandler(agent.Handler):
    def do_GET(self):
        if self.path == '/redirect':
            self.send_response(302)
            self.send_header('Location', '/stats')
            self.end_headers()
        elif self.path == '/oversize':
            self.send_response(200)
            self.send_header('Content-Length', str(2 * 1024 * 1024))
            self.end_headers()
        else:
            super().do_GET()
server = agent.AgentServer(('127.0.0.1', 0), enrollment, Sampler(), context)
server.RequestHandlerClass = TestHandler
metadata = {'port': server.server_port, 'token': token, 'expires': expires, 'fingerprint': enrollment.fingerprint}
agent.atomic_json(directory / 'pairing-server.json', metadata)
server.serve_forever()
