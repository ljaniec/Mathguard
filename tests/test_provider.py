"""Adversarial local protocol fixtures; these are not model-quality measurements."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
import threading
import time
import unittest
from unittest.mock import patch
from gateway.control import Denied
from gateway.engine import ROOT
from gateway.provider import LocalProvider
from gateway.semantic import SEMANTIC_RESPONSE_FORMAT


class FixtureHandler(BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_POST(self):
        payload = json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        self.server.requests.append((self.path, payload))
        model = payload['model']
        if model == 'slow': time.sleep(2)
        value = {'choices': [{'message': {'role': 'assistant', 'content': '{"risk":0,"verdict":"allow"}'},
                             'index': 0, 'finish_reason': 'stop'}], 'usage': {'total_tokens': 17}}
        if model == 'array': value = []
        elif model == 'choices_empty': value['choices'] = []
        elif model == 'choices_extra': value['choices'] *= 2
        elif model == 'content_type': value['choices'][0]['message']['content'] = 3
        elif model == 'role': value['choices'][0]['message']['role'] = 'tool'
        elif model == 'tool_call': value['choices'][0]['message']['tool_calls'] = [{'function': {'name': 'shell.exec'}}]
        elif model == 'usage_bool': value['usage']['total_tokens'] = True
        elif model == 'usage_negative': value['usage']['total_tokens'] = -1
        elif model == 'output_bound': value['usage'].update(total_tokens=3000, completion_tokens=3000)
        elif model == 'usage_sum': value['usage'].update(prompt_tokens=10, completion_tokens=20)
        elif model == 'wrong_model': value['model'] = 'paid-cloud'
        elif model == 'bad_finish': value['choices'][0]['finish_reason'] = 'tool_calls'
        raw = json.dumps(value).encode()
        if model == 'duplicate': raw = b'{"choices":[],"choices":[]}'
        elif model == 'nonfinite': raw = b'{"choices":NaN}'
        elif model == 'bad_json': raw = b'MG_SECRET_PROVIDER_ERROR'
        elif model == 'oversize': raw = b'x'*65537
        elif model == 'oversize_unknown': raw = b'x'*65537
        elif model == 'redirect':
            self.send_response(307)
            self.send_header('Location', self.server.redirect_url)
            self.end_headers()
            return
        elif model in {'error', 'unsupported_schema'}:
            self.send_response(400 if model == 'unsupported_schema' else 500)
            self.end_headers()
            self.wfile.write(b'MG_SECRET_PROVIDER_ERROR')
            return
        self.send_response(200)
        self.send_header('Content-Type', 'text/plain' if model == 'bad_mime' else 'application/json')
        if model != 'oversize_unknown': self.send_header('Content-Length', str(len(raw)))
        self.end_headers()
        try: self.wfile.write(raw)
        except (BrokenPipeError, ConnectionResetError): pass


class ProviderTests(unittest.TestCase):
    def setUp(self):
        self.server = ThreadingHTTPServer(('127.0.0.1', 0), FixtureHandler)
        self.server.daemon_threads = True
        self.server.requests = []
        self.server.redirect_url = 'http://127.0.0.1:'+str(self.server.server_address[1])+'/unexpected'
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()
        self.addCleanup(lambda: (self.server.shutdown(), self.server.server_close(), self.thread.join()))
        self.provider = LocalProvider('http://127.0.0.1:'+str(self.server.server_address[1])+'/v1')
        self.p = json.loads((ROOT/'policies/demo.json').read_text())
    def complete(self, model):
        return self.provider.complete(model, [{'role': 'user', 'content': 'benign'}], self.p)
    def test_openai_compatible_protocol_and_usage(self):
        content, tokens = self.provider.complete('test:exact-tag', [{'role': 'user', 'content': 'benign'}], self.p, semantic=True)
        self.assertEqual(tokens, 17)
        self.assertEqual(json.loads(content)['verdict'], 'allow')
        path, request = self.server.requests[0]
        self.assertEqual(path, '/v1/chat/completions')
        self.assertEqual(request['model'], 'test:exact-tag')
        self.assertFalse(request['stream'])
        self.assertEqual(request['response_format'], SEMANTIC_RESPONSE_FORMAT)
        schema = request['response_format']['json_schema']['schema']
        self.assertEqual(request['response_format']['type'], 'json_schema')
        self.assertEqual(set(schema['required']), {'risk', 'verdict'})
        self.assertFalse(schema['additionalProperties'])
        self.assertEqual(schema['properties']['risk'], {'type': 'integer', 'minimum': 0, 'maximum': 100})
        self.assertEqual(set(schema['properties']['verdict']['enum']), {'allow', 'block', 'review'})
        self.assertEqual(request['max_tokens'], self.p['max_output_tokens'])
    def test_total_adapter_deadline(self):
        self.p['deadline_seconds'] = 1
        start = time.monotonic()
        with self.assertRaises(Denied) as caught: self.complete('slow')
        self.assertEqual(caught.exception.code, 'PROVIDER_TIMEOUT')
        self.assertLess(time.monotonic()-start, 2)
    def test_remote_endpoints_and_url_ambiguity_rejected(self):
        for url in ['http://example.com/v1', 'https://api.openai.com/v1', 'https://example.com/v1',
                    'http://user:password@127.0.0.1/v1', 'http://127.0.0.1/v1?key=secret',
                    'http://127.0.0.1/v1#fragment', 'http://127.0.0.1:99999/v1',
                    'http://2130706433/v1', 'http://127.1/v1', 'http://localhost.evil/v1',
                    'http://127.0.0.1/v1/../admin', 'http://127.0.0.1\\@evil/v1']:
            with self.subTest(url=url), self.assertRaises(ValueError): LocalProvider(url)
    def test_localhost_canonicalized_without_dns(self):
        self.assertEqual(LocalProvider('http://localhost:11434/v1/').url, 'http://127.0.0.1:11434/v1/chat/completions')
        self.assertEqual(LocalProvider('http://[::1]:11434/v1').url, 'http://[::1]:11434/v1/chat/completions')
    def test_cloud_identifiers_and_header_injection_rejected_before_dispatch(self):
        for model in ['model:cloud', 'model-cloud:latest', 'model\nsecret']:
            with self.subTest(model=model), self.assertRaises(Denied): self.complete(model)
        self.assertEqual(self.server.requests, [])
        with self.assertRaises(ValueError): LocalProvider(self.provider.url.rsplit('/chat/completions', 1)[0], 'secret\r\nInjected: x')
    def test_malformed_response_schemas_are_fail_closed(self):
        for model in ['array', 'choices_empty', 'choices_extra', 'content_type', 'role', 'tool_call',
                      'usage_bool', 'usage_negative', 'usage_sum', 'output_bound', 'wrong_model', 'bad_finish',
                      'duplicate', 'nonfinite', 'bad_json', 'bad_mime']:
            with self.subTest(model=model), self.assertRaises(Denied) as caught: self.complete(model)
            self.assertEqual(caught.exception.code, 'PROVIDER_SCHEMA')
            self.assertNotIn('MG_SECRET', str(caught.exception))
    def test_response_size_bound_with_and_without_declared_length(self):
        for model in ['oversize', 'oversize_unknown']:
            with self.subTest(model=model), self.assertRaises(Denied) as caught: self.complete(model)
            self.assertEqual(caught.exception.code, 'PROVIDER_RESPONSE_LIMIT')
    def test_redirect_is_not_followed(self):
        with self.assertRaises(Denied) as caught: self.complete('redirect')
        self.assertEqual(caught.exception.code, 'PROVIDER_UNAVAILABLE')
        self.assertEqual(len(self.server.requests), 1)
    def test_ambient_proxy_and_proxy_credentials_are_not_used(self):
        with patch.dict(os.environ, {'http_proxy': 'http://user:secret@127.0.0.1:9',
                                     'HTTP_PROXY': 'http://user:secret@127.0.0.1:9', 'NO_PROXY': '', 'no_proxy': ''}):
            self.assertEqual(self.complete('test')[1], 17)
        self.assertEqual(self.server.requests[0][0], '/v1/chat/completions')
    def test_provider_error_body_is_not_exposed(self):
        for model in ['error', 'unsupported_schema']:
            with self.subTest(model=model):
                before = len(self.server.requests)
                with self.assertRaises(Denied) as caught:
                    self.provider.complete(model, [{'role': 'user', 'content': 'benign'}], self.p, semantic=True)
                self.assertEqual(str(caught.exception), 'PROVIDER_UNAVAILABLE')
                # No retry with a weaker JSON format when the schema is refused.
                self.assertEqual(len(self.server.requests), before+1)
                self.assertEqual(self.server.requests[-1][1]['response_format'], SEMANTIC_RESPONSE_FORMAT)
    def test_bad_outgoing_shape_and_deadline_refused_before_dispatch(self):
        for messages in [[{'role': 'tool', 'content': 'x'}], [{'role': 'user', 'content': 'x', 'tool_calls': []}],
                         [{'role': 'user', 'content': 5}], [{'role': 'user', 'content': 'x'*70000}]]:
            with self.subTest(messages_type=type(messages)), self.assertRaises(Denied):
                self.provider.complete('test', messages, self.p)
        self.p['deadline_seconds'] = 1000
        with self.assertRaises(Denied): self.complete('test')
        self.assertEqual(self.server.requests, [])
