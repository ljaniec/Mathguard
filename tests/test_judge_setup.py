"""Launcher safety checks. The HTTP service here is an explicit protocol fixture, not an LLM."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from contextlib import redirect_stdout
import importlib.util
import io
import json
import os
from pathlib import Path
import tempfile
import threading
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('mathguard_judge', ROOT / 'scripts/judge.py')
judge = importlib.util.module_from_spec(spec)
spec.loader.exec_module(judge)


class ProtocolFixture(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass

    def send(self, value):
        raw = json.dumps(value).encode()
        self.send_response(200)
        self.send_header('Content-Length', str(len(raw)))
        self.end_headers()
        self.wfile.write(raw)

    def do_GET(self):
        if self.path == '/v1/models':
            self.send({'data': [{'id': 'fixture-local:1b'}]})
        elif self.path == '/api/version':
            self.send({'version': 'protocol-fixture'})
        elif self.path == '/api/tags':
            self.send({'models': [dict(name='fixture-local:1b', digest='a' * 64, size=123,
                                       **self.server.extra)]})
        elif self.path == '/redirect':
            self.send_response(302)
            self.send_header('Location', 'https://example.com/v1/models')
            self.end_headers()
        elif self.path == '/oversized':
            raw = b' ' * 65537
            self.send_response(200)
            self.send_header('Content-Length', str(len(raw)))
            self.end_headers()
            self.wfile.write(raw)

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        self.server.payloads.append(body)
        self.send({'choices': [{'message': {'content': self.server.verdict}}]})


class JudgeSetupTests(unittest.TestCase):
    def setUp(self):
        # Fixture setup must not look like instructions for a genuine live launch.
        quiet = redirect_stdout(io.StringIO())
        quiet.__enter__()
        self.addCleanup(quiet.__exit__, None, None, None)
        self.server = ThreadingHTTPServer(('127.0.0.1', 0), ProtocolFixture)
        self.server.extra = {}
        self.server.payloads = []
        self.server.verdict = '{"risk":0,"verdict":"allow"}'
        thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        thread.start()
        self.addCleanup(lambda: (self.server.shutdown(), self.server.server_close(), thread.join()))
        self.base = 'http://127.0.0.1:' + str(self.server.server_address[1]) + '/v1'
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.directory = Path(self.tmp.name) / 'private'

    def test_real_http_protocol_preflight_and_bounded_semantic_schema(self):
        selected = judge.select_model(judge.model_catalog(self.base))
        record = judge.preflight(self.base, selected)
        self.assertEqual(record['model'], 'fixture-local:1b')
        self.assertEqual(self.server.payloads[0]['response_format'], judge.SEMANTIC_RESPONSE_FORMAT)
        schema = self.server.payloads[0]['response_format']['json_schema']['schema']
        self.assertFalse(schema['additionalProperties'])
        self.assertEqual(set(schema['required']), {'risk', 'verdict'})
        configured = json.loads((ROOT / 'policies/demo.json').read_text())['max_output_tokens']
        self.assertEqual(self.server.payloads[0]['max_tokens'], configured)
        self.assertEqual(self.server.payloads[0]['messages'][0]['content'], judge.SEMANTIC_SYSTEM_PROMPT)
        wire = json.loads(self.server.payloads[0]['messages'][1]['content'])
        self.assertEqual(wire['history'], [wire['candidate']['text']])
        with self.subTest('valid low-risk allow remains compatible'):
            self.server.verdict = '{"risk":10,"verdict":"allow"}'
            self.assertEqual(judge.preflight(self.base, selected)['preflight_verdict'], {'risk': 10, 'verdict': 'allow'})
        for content in ['{"risk":true,"verdict":"allow"}', '{"risk":0,"risk":99,"verdict":"allow"}',
                        '{"risk":0,"verdict":"allow","extra":1}', 'not JSON']:
            self.server.verdict = content
            with self.assertRaises(judge.SetupError):
                judge.preflight(self.base, selected)
        for content in ['{"risk":0,"verdict":"block"}', '{"risk":99,"verdict":"allow"}',
                        '{"risk":50,"verdict":"review"}']:
            self.server.verdict = content
            with self.assertRaises(judge.SetupError):
                judge.preflight(self.base, selected)

    def test_loopback_catalogue_cannot_admit_cloud_or_remote_provider(self):
        for url in ['https://example.com/v1', 'http://127.0.0.1.attacker.test/v1',
                    'http://user:password@127.0.0.1/v1', 'http://127.0.0.1/v1?key=x']:
            with self.assertRaises(judge.SetupError):
                judge.endpoint(url)
        self.assertEqual(judge.endpoint('http://localhost:11434/v1/'), 'http://127.0.0.1:11434/v1')
        with self.assertRaises(judge.SetupError):
            judge.select_model(['gpt-oss:cloud'], 'gpt-oss:cloud')
        self.server.extra = {'remote_host': 'https://cloud.example', 'remote_model': 'cloud-model'}
        with self.assertRaises(judge.SetupError):
            judge.preflight(self.base, 'fixture-local:1b')

    def test_redirect_and_oversized_response_refused_without_proxy_fallback(self):
        origin = self.base[:-3]
        with patch.dict(os.environ, {'HTTP_PROXY': 'http://invalid-proxy.invalid:1'}):
            self.assertEqual(judge.model_catalog(self.base), ['fixture-local:1b'])
            for path in ['/redirect', '/oversized']:
                with self.assertRaises(judge.SetupError):
                    judge.request_json(origin + path)

    def test_repeated_setup_preserves_private_tokens_policy_and_state(self):
        with patch.object(judge, 'build_worker'):
            judge.setup(self.directory, self.base, 'fixture-local:1b')
            original_tokens = judge.credentials(self.directory)
            state = self.directory / 'state.sqlite3'
            state.write_bytes(b'unchanged-durable-state-sentinel')
            pp = self.directory / 'policy.json'
            active = json.loads(pp.read_text())
            active.update(epoch=8, pii_action='block')
            judge.write_private(pp, active)
            judge.setup(self.directory, self.base, 'fixture-local:1b')
        self.assertEqual(judge.credentials(self.directory), original_tokens)
        self.assertEqual(json.loads(pp.read_text())['pii_action'], 'block')
        self.assertEqual(json.loads(pp.read_text())['epoch'], 8)
        self.assertEqual(state.read_bytes(), b'unchanged-durable-state-sentinel')
        self.assertEqual(self.directory.stat().st_mode & 0o777, 0o700)
        self.assertEqual(pp.stat().st_mode & 0o777, 0o600)

    def test_invalid_private_candidate_is_preserved_for_repair(self):
        with patch.object(judge, 'build_worker'):
            judge.setup(self.directory, self.base, 'fixture-local:1b')
            pp = self.directory / 'policy.json'
            pp.write_text('{invalid candidate')
            with self.assertRaises(judge.Denied):
                judge.setup(self.directory, self.base, 'fixture-local:1b')
            self.assertEqual(pp.read_text(), '{invalid candidate')

    def test_credentials_permissions_symlinks_and_role_collision_refused(self):
        judge.private_dir(self.directory)
        target = self.directory / 'credentials.json'
        judge.write_private(target, {'operator': 'A' * 40, 'agent': 'B' * 40, 'owner': 'C' * 40})
        target.chmod(0o644)
        with self.assertRaises(judge.SetupError):
            judge.credentials(self.directory)
        target.chmod(0o600)
        judge.write_private(target, {'operator': 'A' * 40, 'agent': 'A' * 40, 'owner': 'C' * 40})
        with self.assertRaises(judge.SetupError):
            judge.credentials(self.directory)
        target.unlink()
        other = self.directory / 'other.json'
        judge.write_private(other, {})
        target.symlink_to(other)
        with self.assertRaises(judge.SetupError):
            judge.credentials(self.directory)
        with self.assertRaises(judge.SetupError):
            judge.write_private(target, {})

    def test_launcher_passes_persistent_state_and_distinct_roles_without_token_print(self):
        with patch.object(judge, 'build_worker'):
            judge.setup(self.directory, self.base, 'fixture-local:1b')
            with patch.object(judge.os, 'execve') as execute, patch.object(judge.os, 'chdir'), patch('builtins.print') as output:
                judge.run(self.directory, 8787)
        _, argv, env = execute.call_args.args
        self.assertEqual(argv[argv.index('--state') + 1], str(self.directory / 'state.sqlite3'))
        emitted = '\n'.join(str(call) for call in output.call_args_list)
        for role, token in judge.credentials(self.directory).items():
            self.assertEqual(env['MATHGUARD_' + role.upper() + '_TOKEN'], token)
            self.assertNotIn(token, emitted)
        self.assertNotIn('MATHGUARD_MODEL_KEY', env)


if __name__ == '__main__':
    unittest.main()
