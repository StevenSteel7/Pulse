"""Exercise the exact Python payload shipped inside the single-file installer."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import threading
import unittest
from unittest.mock import patch
import urllib.error
import urllib.request

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = (ROOT / 'linux-agent/install.sh').read_text()
PAYLOAD = SCRIPT.split("<<'PY_AGENT'\n", 1)[1].split('\nPY_AGENT\n', 1)[0]
TEMP = tempfile.TemporaryDirectory()
MODULE_PATH = Path(TEMP.name) / 'agent.py'
MODULE_PATH.write_text(PAYLOAD)
spec = importlib.util.spec_from_file_location('pulse_agent', MODULE_PATH)
agent = importlib.util.module_from_spec(spec)
spec.loader.exec_module(agent)


def fixture(name, text):
    path = Path(TEMP.name) / name
    path.write_text(text)
    return str(path)


class AgentTests(unittest.TestCase):
    def test_cpu_delta_excludes_guest_and_bounds_values(self):
        path = fixture('stat', 'cpu  10 20 30 40 50 60 70 80 999 999\n')
        self.assertEqual(agent.read_cpu(path), (360, 90))
        self.assertEqual(agent.cpu_percent((100, 50), (200, 125)), 25)
        self.assertEqual(agent.cpu_percent((100, 50), (100, 50)), 0)
        self.assertEqual(agent.cpu_percent((100, 50), (200, 200)), 0)

    def test_memory_available_and_old_kernel_fallback(self):
        path = fixture('memory', 'MemTotal: 25165824 kB\nMemAvailable: 18874368 kB\n')
        self.assertEqual(agent.memory_stats(path), {'used_gb': 6, 'total_gb': 24, 'percent': 25})
        path = fixture('memory-old', 'MemTotal: 100 kB\nMemFree: 10 kB\nBuffers: 10 kB\nCached: 20 kB\nSReclaimable: 10 kB\nShmem: 5 kB\n')
        self.assertEqual(agent.memory_stats(path)['percent'], 55)

    def test_arm_topology_falls_back_to_virtual_cpus(self):
        path = fixture('arm', 'processor : 0\nCPU implementer : 0x41\n\nprocessor : 1\n')
        with patch.object(agent.os, 'cpu_count', return_value=4):
            self.assertEqual(agent.physical_cores(path), 4)
        path = fixture('x86', 'physical id : 0\ncore id : 0\n\nphysical id : 0\ncore id : 0\n\nphysical id : 0\ncore id : 1\n')
        self.assertEqual(agent.physical_cores(path), 2)

    def test_sample_contract(self):
        with patch.object(agent, 'physical_cores', return_value=4), patch.object(agent, 'read_cpu', side_effect=[(100, 50), (200, 125)]):
            sampler = agent.Sampler()
            with patch('builtins.open', return_value=io.StringIO('86400.12 5.0')), \
                 patch.object(agent, 'memory_stats', return_value={'used_gb': 6, 'total_gb': 24, 'percent': 25}), \
                 patch.object(agent.os, 'cpu_count', return_value=4):
                sample = sampler.collect()
        self.assertEqual(sample['cpu']['logical_cores'], 4)
        self.assertEqual(sample['cpu']['percent'], 25)
        self.assertEqual(sample['uptime_seconds'], 86400)
        self.assertEqual(sample['gpu'], {'available': False})
        self.assertGreater(sample['disk']['total_gb'], 0)
        json.dumps(sample, allow_nan=False)
        output = os.environ.get('PULSE_TEST_FIXTURE')
        if output:
            Path(output).write_text(json.dumps(sample))

    def test_http_auth_health_unknown_and_empty_sample(self):
        class FakeSampler:
            lock = threading.Lock()
            snapshot = {'hostname': 'oracle-test', 'gpu': {'available': False}}
        sampler = FakeSampler()
        server = agent.StatsServer(('127.0.0.1', 0), sampler, 'a' * 64)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))
        base = 'http://127.0.0.1:{}'.format(server.server_port)
        def get(path, key=None):
            request = urllib.request.Request(base + path, headers={'X-API-Key': key} if key else {})
            try:
                response = opener.open(request, timeout=2)
            except urllib.error.HTTPError as error:
                response = error
            with contextlib.closing(response):
                return response.code, json.load(response), response.headers
        try:
            self.assertEqual(get('/health')[:2], (200, {'ok': True}))
            self.assertEqual(get('/stats')[0], 401)
            self.assertEqual(get('/stats', 'wrong')[0], 401)
            self.assertEqual(get('/stats', '\u00e9')[0], 401)
            status, body, headers = get('/stats', 'a' * 64)
            self.assertEqual(status, 200)
            self.assertEqual(body['hostname'], 'oracle-test')
            self.assertEqual(headers['Cache-Control'], 'no-store')
            self.assertEqual(get('/unknown')[0], 404)
            with sampler.lock:
                sampler.snapshot = None
            self.assertEqual(get('/stats', 'a' * 64)[0], 503)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()


if __name__ == '__main__':
    unittest.main()
