"""Exercise the real transport against a local HTTP protocol fixture, not an LLM."""
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import threading
import time
import unittest
from gateway.control import Denied
from gateway.engine import ROOT
from gateway.provider import LocalProvider

class FixtureHandler(BaseHTTPRequestHandler):
    def log_message(self,*args): pass
    def do_POST(self):
        payload=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        self.server.requests.append(payload)
        if payload['model']=='slow': time.sleep(2)
        raw=json.dumps({'choices':[{'message':{'content':'{"risk":0,"verdict":"allow"}'}}],
                        'usage':{'total_tokens':17}}).encode()
        self.send_response(200);self.send_header('Content-Length',str(len(raw)));self.end_headers()
        try:self.wfile.write(raw)
        except BrokenPipeError:pass

class ProviderTests(unittest.TestCase):
    def setUp(self):
        self.server=ThreadingHTTPServer(('127.0.0.1',0),FixtureHandler)
        self.server.requests=[]
        self.thread=threading.Thread(target=self.server.serve_forever,daemon=True);self.thread.start()
        self.addCleanup(lambda:(self.server.shutdown(),self.server.server_close(),self.thread.join()))
        self.provider=LocalProvider('http://127.0.0.1:'+str(self.server.server_address[1])+'/v1')
        self.p=json.loads((ROOT/'policies/demo.json').read_text())
    def test_openai_compatible_protocol_and_usage(self):
        content,tokens=self.provider.complete('test',[{'role':'user','content':'benign'}],self.p,semantic=True)
        self.assertEqual(tokens,17);self.assertEqual(json.loads(content)['verdict'],'allow')
        self.assertFalse(self.server.requests[0]['stream'])
        self.assertEqual(self.server.requests[0]['response_format'],{'type':'json_object'})
    def test_total_adapter_deadline(self):
        self.p['deadline_seconds']=1;start=time.monotonic()
        with self.assertRaises(Denied) as caught:self.provider.complete('slow',[],self.p)
        self.assertEqual(caught.exception.code,'PROVIDER_TIMEOUT');self.assertLess(time.monotonic()-start,2)
    def test_untrusted_plaintext_remote_endpoint_rejected(self):
        with self.assertRaises(ValueError):LocalProvider('http://example.com/v1')
        with self.assertRaises(ValueError):LocalProvider('https://user:password@example.com/v1')
