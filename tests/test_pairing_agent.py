import contextlib
import io
import hashlib
import hmac
import importlib.util
import json
import os
from pathlib import Path
import ssl
import tempfile
import threading
import time
import unittest
from unittest.mock import patch
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('paired_agent', ROOT / 'paired-agent/agent.py')
agent = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agent)
TOKEN = 'a' * 64
CREDENTIAL = 'b' * 64
NONCE = 'c' * 64

class PairingTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.cert_dir = tempfile.TemporaryDirectory()
        agent.ensure_certificate(Path(cls.cert_dir.name))

    @classmethod
    def tearDownClass(cls):
        cls.cert_dir.cleanup()

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.directory = Path(self.temp.name)
        for name in ['server.crt', 'server.key']:
            (self.directory / name).write_bytes((Path(self.cert_dir.name) / name).read_bytes())
        self.expires = int(time.time()) + 600
        with contextlib.redirect_stdout(io.StringIO()):
            agent.configure(self.directory, TOKEN, self.expires, '127.0.0.1', 8843)
        self.enrollment = agent.Enrollment(self.directory)

    def tearDown(self):
        self.temp.cleanup()

    def test_proof_binds_nonce_certificate_device_and_expiry(self):
        info = self.enrollment.info(NONCE)
        expected = hmac.new(bytes.fromhex(TOKEN), info['payload'].encode(), hashlib.sha256).hexdigest()
        self.assertEqual(expected, info['proof'])
        payload = json.loads(info['payload'])
        self.assertEqual(payload['nonce'], NONCE)
        self.assertEqual(payload['fingerprint'], agent.certificate_fingerprint(self.directory))
        self.assertEqual(payload['expires'], self.expires)
        self.assertNotIn(TOKEN, json.dumps(info))
        self.assertIsNone(self.enrollment.info('invalid'))

    def test_expiry_is_enforced_and_erases_token(self):
        with patch.object(agent.time, 'time', return_value=self.expires + 1):
            self.assertIsNone(self.enrollment.info(NONCE))
            self.assertFalse(self.enrollment.approve(TOKEN, CREDENTIAL))
        self.assertNotIn('pairing_token', json.loads((self.directory / 'state.json').read_text()))

    def test_one_time_approval_hash_only_persistence_and_revoke(self):
        self.assertFalse(self.enrollment.authorized(CREDENTIAL))
        self.assertFalse(self.enrollment.approve('0' * 64, CREDENTIAL))
        self.assertTrue(self.enrollment.approve(TOKEN, CREDENTIAL))
        self.assertFalse(self.enrollment.approve(TOKEN, 'd' * 64))
        self.assertIsNone(self.enrollment.info(NONCE))
        saved = (self.directory / 'state.json').read_text()
        self.assertNotIn(TOKEN, saved)
        self.assertNotIn(CREDENTIAL, saved)
        restarted = agent.Enrollment(self.directory)
        self.assertTrue(restarted.authorized(CREDENTIAL))
        self.assertFalse(restarted.revoke('0' * 64))
        self.assertTrue(restarted.revoke(CREDENTIAL))
        self.assertFalse(restarted.authorized(CREDENTIAL))
        self.assertTrue(restarted.revoke(CREDENTIAL), 'Revocation retry is idempotent')
        with self.assertRaises(ValueError):
            agent.configure(self.directory, TOKEN, self.expires, '127.0.0.1', 8843)

    def test_concurrent_approval_has_one_winner(self):
        results = []
        threads = [threading.Thread(target=lambda: results.append(self.enrollment.approve(TOKEN, CREDENTIAL))) for _ in range(8)]
        for thread in threads: thread.start()
        for thread in threads: thread.join()
        self.assertEqual(results.count(True), 1)

    def test_new_enrollment_revokes_old_credential(self):
        self.enrollment.approve(TOKEN, CREDENTIAL)
        agent.configure(self.directory, 'd' * 64, self.expires, '127.0.0.1', 8843)
        new = agent.Enrollment(self.directory)
        self.assertFalse(new.authorized(CREDENTIAL))
        self.assertIsNotNone(new.info(NONCE))
        self.assertEqual(new.state['device_id'], self.enrollment.state['device_id'])

    def test_atomic_persistence_failure_does_not_consume_token(self):
        with patch.object(agent, 'atomic_json', side_effect=OSError('disk full')):
            with self.assertRaises(OSError): self.enrollment.approve(TOKEN, CREDENTIAL)
        self.assertIsNotNone(self.enrollment.info(NONCE))
        self.assertFalse(self.enrollment.authorized(CREDENTIAL))

    def test_expired_install_does_not_change_state(self):
        old = (self.directory / 'state.json').read_bytes()
        with self.assertRaises(ValueError): agent.configure(self.directory, 'd' * 64, int(time.time()) - 1, '127.0.0.1', 8843)
        self.assertEqual((self.directory / 'state.json').read_bytes(), old)

    def test_live_https_requires_approval_then_revokes(self):
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.load_cert_chain(str(self.directory / 'server.crt'), str(self.directory / 'server.key'))
        class FakeSampler:
            lock = threading.Lock()
            snapshot = {'hostname': 'test-device'}
        server = agent.AgentServer(('127.0.0.1', 0), self.enrollment, FakeSampler(), context)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        # Test-only TLS bypass: production Swift separately verifies proof + pin.
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), urllib.request.HTTPSHandler(context=ssl._create_unverified_context()))
        def request(path, body=None, key=None):
            headers = {'X-API-Key': key} if key else {}
            value = urllib.request.Request('https://127.0.0.1:{}{}'.format(server.server_port, path),
                                           data=json.dumps(body).encode() if body is not None else None, headers=headers)
            try: response = opener.open(value, timeout=3)
            except urllib.error.HTTPError as error: response = error
            with response: return response.status, json.load(response)
        try:
            old_port = self.enrollment.state['port']
            self.enrollment.state['port'] = server.server_port
            agent.atomic_json(self.directory / 'state.json', self.enrollment.state)
            agent.check_service(self.directory)
            self.assertEqual(request('/stats', key=CREDENTIAL)[0], 401)
            self.assertEqual(request('/pairing?nonce=' + NONCE)[0], 200)
            self.assertEqual(request('/pairing/approve', {'token': '0' * 64, 'credential': CREDENTIAL})[0], 403)
            self.assertEqual(request('/pairing/approve', {'token': TOKEN, 'credential': CREDENTIAL})[0], 200)
            self.assertEqual(request('/stats', key=CREDENTIAL)[0], 200)
            self.assertEqual(request('/pairing?nonce=' + NONCE)[0], 410)
            self.assertEqual(request('/pairing/approve', {'token': TOKEN, 'credential': CREDENTIAL})[0], 403)
            self.assertEqual(request('/revoke', {}, CREDENTIAL)[0], 200)
            self.assertEqual(request('/stats', key=CREDENTIAL)[0], 401)
            self.assertEqual(request('/revoke', {}, CREDENTIAL)[0], 200)
            for _ in range(180): server.allow_request()
            self.assertEqual(request('/health')[0], 429)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()

if __name__ == '__main__': unittest.main()
