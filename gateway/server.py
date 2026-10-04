"""Bounded loopback demo gateway; run via `make run` for private credentials/state."""
from __future__ import annotations
import argparse
import http.client
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import json
import os
from pathlib import Path
import re
import socket
import threading
from urllib.parse import parse_qsl, urlsplit
from .control import Denied, strict_json
from .engine import Engine, ROOT
from .provider import LocalProvider


class _HeaderBudget:
    """Bound bytes consumed by stdlib header parsing, including folded lines."""
    def __init__(self, stream, limit=8192):
        self.stream = stream
        self.remaining = limit
    def readline(self, limit=-1):
        bound = self.remaining+1 if limit < 0 else min(limit, self.remaining+1)
        line = self.stream.readline(bound)
        self.remaining -= len(line)
        if self.remaining < 0:
            raise http.client.LineTooLong('header block')
        return line


class Server(ThreadingHTTPServer):
    daemon_threads = True
    request_queue_size = 8
    def __init__(self, address, engine):
        if address[0] not in {'127.0.0.1', 'localhost', '::1'}:
            raise ValueError('The demonstration gateway binds only to loopback')
        self.engine = engine
        self.slots = threading.BoundedSemaphore(8)
        super().__init__(address, Handler)
    def process_request(self, request, client_address):
        if not self.slots.acquire(blocking=False):
            request.close()
            return
        try:
            super().process_request(request, client_address)
        except Exception:
            self.slots.release()
            raise
    def process_request_thread(self, request, client_address):
        try:
            super().process_request_thread(request, client_address)
        finally:
            self.slots.release()
    def handle_error(self, request, client_address):
        pass  # Socket/parser details may include attacker-controlled values.


class Handler(BaseHTTPRequestHandler):
    server_version = 'Mathguard'
    sys_version = ''
    def setup(self):
        super().setup()
        self.connection.settimeout(5)
        # Absolute deadline covers trickled request line, headers and body.
        self.ingress_timer = threading.Timer(5, self.expire_ingress)
        self.ingress_timer.daemon = True
        self.ingress_timer.start()
    def expire_ingress(self):
        try:
            self.connection.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
    def finish(self):
        self.ingress_timer.cancel()
        super().finish()
    def parse_request(self):
        if len(self.raw_requestline) > 2048:
            self.request_version = 'HTTP/1.0'
            self.send_error(414)
            return False
        original_stream = self.rfile
        self.rfile = _HeaderBudget(original_stream)
        try:
            parsed = super().parse_request()
        finally:
            self.rfile = original_stream
        if not parsed:
            return False
        try:
            if sum(len(k)+len(v)+4 for k,v in self.headers.items()) > 8192:
                raise Denied('HEADER_LIMIT')
            for name in ('Host', 'Authorization', 'Content-Type', 'Origin', 'Content-Length'):
                if len(self.headers.get_all(name, [])) > 1:
                    raise Denied('HEADER_INVALID')
            authority = self.headers.get('Host', '')
            port = self.server.server_address[1]
            if authority not in {f'127.0.0.1:{port}', f'localhost:{port}', f'[::1]:{port}'}:
                raise Denied('HOST_INVALID')
            origin = self.headers.get('Origin')
            if origin is not None and origin != 'http://'+authority:
                raise Denied('ORIGIN_FORBIDDEN')
            if any('\r' in value or '\n' in value for value in self.headers.values()):
                raise Denied('HEADER_INVALID')
            if self.headers.get('Expect'):
                raise Denied('EXPECT_UNSUPPORTED')
        except Denied as exc:
            self.send(400, {'outcome': 'BLOCKED', 'reason_codes': [exc.code]})
            return False
        return True
    def log_message(self, *args):
        pass
    def send_error(self, code, message=None, explain=None):
        # BaseHTTPRequestHandler's HTML errors can echo method/URL/header text.
        self.send(code, {'outcome': 'BLOCKED', 'reason_codes': ['HTTP_INVALID']})
    def token(self):
        value = self.headers.get('Authorization', '')
        if not re.fullmatch(r'Bearer [!-~]{1,512}', value):
            return ''
        return value[7:]
    def send(self, code, value, kind='application/json'):
        raw = json.dumps(value, separators=(',', ':'), allow_nan=False).encode() if kind == 'application/json' else value
        self.close_connection = True  # One request per connection, no ambiguous pipelining.
        self.send_response(code)
        self.send_header('Content-Type', kind+('; charset=utf-8' if kind.startswith(('text/', 'application/')) else ''))
        self.send_header('Content-Length', str(len(raw)))
        self.send_header('Connection', 'close')
        self.send_header('Cache-Control', 'no-store')
        self.send_header('X-Content-Type-Options', 'nosniff')
        self.send_header('X-Frame-Options', 'DENY')
        self.send_header('Referrer-Policy', 'no-referrer')
        self.send_header('Cross-Origin-Resource-Policy', 'same-origin')
        self.send_header('Content-Security-Policy', "default-src 'self'; script-src 'self'; style-src 'self'; connect-src 'self'; img-src 'self'; base-uri 'none'; object-src 'none'; frame-ancestors 'none'")
        self.end_headers()
        try:
            self.wfile.write(raw)
        except (BrokenPipeError, ConnectionResetError, OSError):
            pass
    def do_GET(self):
        self.ingress_timer.cancel()
        assets = {'/': (ROOT/'dashboard/index.html', 'text/html'),
          '/app.js': (ROOT/'dashboard/app.js', 'text/javascript'),
          '/style.css': (ROOT/'dashboard/style.css', 'text/css'),
          '/logo.jpeg': (ROOT/'project_logo.jpeg', 'image/jpeg'),
          '/logo.png': (ROOT/'submission/brand/mathguard-classic-mark.png', 'image/png')}
        if self.path in assets:
            path, kind = assets[self.path]
            try:
                return self.send(200, path.read_bytes(), kind)
            except OSError:
                return self.send(404, {'outcome': 'BLOCKED', 'reason_codes': ['ASSET_UNAVAILABLE']})
        if self.path == '/health':
            e = self.server.engine
            return self.send(200, {'service': 'Mathguard', 'mode': e.provider.mode,
                'ready': bool(e.active and e.feed and not e.worker.broken and not e.quarantined),
                'quarantined': e.quarantined})
        try:
            parts = urlsplit(self.path)
            if parts.scheme or parts.netloc or parts.fragment:
                raise Denied('ROUTE_NOT_ALLOWED')
            kwargs = {}
            if parts.query:
                if parts.path not in {'/v1/events', '/v1/audit/export'}:
                    raise Denied('SCHEMA_INVALID')
                fields = parse_qsl(parts.query, strict_parsing=True, keep_blank_values=True)
                if len(fields) > 2 or len({k for k,v in fields}) != len(fields) or any(k not in {'after', 'limit'} for k,v in fields):
                    raise Denied('SCHEMA_INVALID')
                for key, value in fields:
                    if not re.fullmatch(r'0|[1-9][0-9]{0,11}', value):
                        raise Denied('SCHEMA_INVALID')
                    kwargs[key] = int(value)
                if not 1 <= kwargs.get('limit', 2000) <= 2000:
                    raise Denied('SCHEMA_INVALID')
            value = self.server.engine.read(parts.path, self.token(), **kwargs)
            if parts.path == '/v1/audit/export':
                return self.send(200, ('\n'.join(json.dumps(e, allow_nan=False) for e in value)+'\n').encode(), 'application/x-ndjson')
            self.send(200, value)
        except Denied as exc:
            busy = exc.code == 'GATEWAY_BUSY'
            self.send(503 if busy else 401 if exc.code == 'AUTH_REQUIRED' else 403,
                {'outcome': 'ERROR_CLOSED' if busy else 'BLOCKED', 'reason_codes': [exc.code]})
        except (ValueError, UnicodeError):
            self.send(400, {'outcome': 'BLOCKED', 'reason_codes': ['SCHEMA_INVALID']})
        except Exception:
            self.send(503, {'outcome': 'ERROR_CLOSED', 'reason_codes': ['INTERNAL_ERROR']})
    def do_POST(self):
        try:
            if '?' in self.path or '#' in self.path or not self.path.startswith('/'):
                raise Denied('ROUTE_NOT_ALLOWED')
            if self.headers.get('Transfer-Encoding') or len(self.headers.get_all('Content-Length', [])) != 1:
                raise Denied('SCHEMA_INVALID')
            if self.headers.get('Content-Encoding', 'identity').lower() != 'identity':
                raise Denied('CONTENT_ENCODING')
            if self.headers.get('Content-Type', '').split(';')[0].strip().lower() != 'application/json':
                raise Denied('CONTENT_TYPE')
            declared = self.headers['Content-Length']
            if not re.fullmatch(r'[1-9][0-9]{0,7}', declared):
                raise Denied('BODY_LIMIT')
            length = int(declared)
            if length > 32768:
                raise Denied('BODY_LIMIT')
            raw = self.rfile.read(length)
            if len(raw) != length:
                raise Denied('BODY_TRUNCATED')
            body = strict_json(raw)
            self.ingress_timer.cancel()
            result = self.server.engine.handle(self.path, body, self.token())
            self.send(200, result)
        except (Denied, ValueError, TimeoutError, OSError) as exc:
            self.ingress_timer.cancel()
            code = exc.code if isinstance(exc, Denied) else 'SCHEMA_INVALID'
            try:
                value = self.server.engine.ingress_rejection(code)
            except Exception:
                value = {'outcome': 'ERROR_CLOSED', 'reason_codes': ['INTERNAL_ERROR']}
            self.send(400, value)
        except Exception:
            self.ingress_timer.cancel()
            self.send(503, {'outcome': 'ERROR_CLOSED', 'reason_codes': ['INTERNAL_ERROR']})


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--port', type=int, default=8787)
    parser.add_argument('--policy', type=Path, default=ROOT/'policies/demo.json')
    parser.add_argument('--feed', type=Path, default=ROOT/'feeds/demo-signatures.json')
    parser.add_argument('--state', '--state-db', dest='state', type=Path, default=None)
    args = parser.parse_args()
    if not 1 <= args.port <= 65535:
        raise SystemExit('Port must be between 1 and 65535')
    tokens = {}
    for role, principal in [('operator', 0), ('owner', 1), ('agent', 1)]:
        token = os.environ.get('MATHGUARD_'+role.upper()+'_TOKEN', '')
        if not re.fullmatch(r'[!-~]{24,512}', token) or token in tokens:
            raise SystemExit('Run make run to provision distinct private role credentials')
        tokens[token] = (role, principal)
    engine = None
    try:
        provider = LocalProvider(os.environ.get('MATHGUARD_MODEL_URL', 'http://127.0.0.1:11434/v1'), os.environ.get('MATHGUARD_MODEL_KEY', ''))
        engine = Engine(provider, tokens, args.policy, args.feed, state_path=args.state)
        server = Server(('127.0.0.1', args.port), engine)
    except Denied as exc:
        if engine:
            engine.close()
        raise SystemExit('Startup blocked: '+exc.code) from None
    except (ValueError, OSError):
        if engine:
            engine.close()
        raise SystemExit('Startup blocked: check the local endpoint, state path and port') from None
    print(f'Mathguard: http://127.0.0.1:{args.port} — local model; '+('private persistent state' if args.state else 'volatile state'), flush=True)
    try:
        server.serve_forever()
    finally:
        server.server_close()
        engine.close()

if __name__ == '__main__':
    main()
