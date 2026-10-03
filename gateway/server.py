"""Local demo server. Bind to loopback; place behind an authenticated TLS ingress for remote use."""
from __future__ import annotations
import argparse
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import secrets
import threading
from .control import Denied, strict_json
from .engine import Engine, ROOT
from .provider import LocalProvider


class Server(ThreadingHTTPServer):
    daemon_threads = True
    request_queue_size = 8
    def __init__(self,address,engine):
        self.engine=engine
        self.slots=threading.BoundedSemaphore(8)
        super().__init__(address,Handler)
    def process_request(self,request,client_address):
        if not self.slots.acquire(blocking=False):
            request.close()
            return
        try: super().process_request(request,client_address)
        except Exception: self.slots.release(); raise
    def process_request_thread(self,request,client_address):
        try: super().process_request_thread(request,client_address)
        finally: self.slots.release()


class Handler(BaseHTTPRequestHandler):
    def setup(self):
        super().setup()
        self.connection.settimeout(5)
    def log_message(self,*args): pass  # Never log user-supplied URLs or payloads.
    def token(self):
        value=self.headers.get('Authorization','')
        return value[7:] if value.startswith('Bearer ') else ''
    def send(self,code,value,kind='application/json'):
        raw = json.dumps(value,separators=(',',':')).encode() if kind=='application/json' else value
        self.send_response(code)
        self.send_header('Content-Type',kind+'; charset=utf-8')
        self.send_header('Content-Length',str(len(raw)))
        self.send_header('Cache-Control','no-store')
        self.send_header('X-Content-Type-Options','nosniff')
        self.send_header('Content-Security-Policy',"default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; frame-ancestors 'none'")
        self.end_headers()
        try: self.wfile.write(raw)
        except (BrokenPipeError,ConnectionResetError): pass
    def do_GET(self):
        assets={'/':('index.html','text/html'),'/app.js':('app.js','text/javascript'),'/style.css':('style.css','text/css')}
        if self.path in assets:
            name,kind=assets[self.path]
            return self.send(200,(ROOT/'dashboard'/name).read_bytes(),kind)
        if self.path=='/health':
            return self.send(200,{'service':'Mathguard','mode':self.server.engine.provider.mode})
        try:
            value=self.server.engine.read(self.path,self.token())
            if self.path=='/v1/audit/export':
                return self.send(200,('\n'.join(json.dumps(e) for e in value)+'\n').encode(),'application/x-ndjson')
            self.send(200,value)
        except Denied as exc:
            self.send(401 if exc.code=='AUTH_REQUIRED' else 403,{'outcome':'BLOCKED','reason_codes':[exc.code]})
    def do_POST(self):
        try:
            if self.headers.get('Transfer-Encoding') or len(self.headers.get_all('Content-Length',[]))!=1:
                raise Denied('SCHEMA_INVALID')
            if self.headers.get('Content-Type','').split(';')[0]!='application/json': raise Denied('CONTENT_TYPE')
            length=int(self.headers['Content-Length'])
            if not 0 < length <= 32768: raise Denied('BODY_LIMIT')
            raw=self.rfile.read(length)
            if len(raw)!=length: raise Denied('BODY_TRUNCATED')
            body=strict_json(raw)
            result=self.server.engine.handle(self.path,body,self.token())
            self.send(200,result)
        except (Denied,ValueError,TimeoutError) as exc:
            self.send(400,self.server.engine.ingress_rejection(exc.code if isinstance(exc,Denied) else 'SCHEMA_INVALID'))


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port',type=int,default=8787)
    parser.add_argument('--policy',type=Path,default=ROOT/'policies/demo.json')
    parser.add_argument('--feed',type=Path,default=ROOT/'feeds/demo-signatures.json')
    args=parser.parse_args()
    tokens={}
    for role,principal in [('operator',0),('owner',1),('agent',1)]:
        token=os.environ.get('MATHGUARD_'+role.upper()+'_TOKEN') or secrets.token_urlsafe(32)
        if len(token)<24 or token in tokens: raise SystemExit('Use distinct tokens of at least 24 characters')
        tokens[token]=(role,principal)
        # Explicit local console credential handoff; never goes into audit/export.
        print(role.upper()+' token: '+token,flush=True)
    provider=LocalProvider(os.environ.get('MATHGUARD_MODEL_URL','http://127.0.0.1:11434/v1'),os.environ.get('MATHGUARD_MODEL_KEY',''))
    engine=Engine(provider,tokens,args.policy,args.feed)
    server=Server(('127.0.0.1',args.port),engine)
    print(f'Mathguard: http://127.0.0.1:{args.port} — local model required; volatile state',flush=True)
    try: server.serve_forever()
    finally: server.server_close(); engine.close()

if __name__=='__main__': main()
