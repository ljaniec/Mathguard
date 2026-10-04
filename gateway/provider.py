"""Bounded local OpenAI-compatible adapter (Ollama); no paid API dependency.

The local model daemon is trusted deployment infrastructure. Disable Ollama cloud
features on that daemon; a loopback address alone cannot attest where it computes.
Terminating the adapter does not prove cancellation of an upstream GPU job.
"""
from __future__ import annotations
import ipaddress
from copy import deepcopy
import json
import multiprocessing
import re
import time
import urllib.error
import urllib.request
from urllib.parse import urlsplit, urlunsplit
from .control import Denied, strict_json
from .semantic import SEMANTIC_RESPONSE_FORMAT

RESPONSE_LIMIT = 65536
REQUEST_LIMIT = 65536


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def local_endpoint(base_url, *, provider=True):
    """Canonical numeric loopback URL: no DNS, credentials, queries or redirects."""
    try:
        if type(base_url) is not str or len(base_url) > 512 or any(c.isspace() or ord(c) < 32 for c in base_url):
            raise ValueError
        parts = urlsplit(base_url)
        host = parts.hostname
        if host == 'localhost':
            host = '127.0.0.1'
        address = ipaddress.ip_address(host or '')
        port = parts.port
        if (parts.scheme not in {'http', 'https'} or not address.is_loopback or
                parts.username is not None or parts.password is not None or parts.query or parts.fragment or
                port is not None and not 1 <= port <= 65535 or
                parts.path.rstrip('/') not in ({'', '/v1'} if provider else {''})):
            raise ValueError
        authority = '['+str(address)+']' if address.version == 6 else str(address)
        if port is not None:
            authority += ':'+str(port)
        return urlunsplit((parts.scheme, authority, parts.path.rstrip('/'), '', ''))
    except (ValueError, TypeError) as exc:
        raise ValueError('Use a numeric loopback model endpoint or localhost; remote endpoints are disabled') from None


def _request(connection, url, key, payload, timeout):
    try:
        request = urllib.request.Request(url, data=json.dumps(payload, allow_nan=False).encode(),
            headers={'Content-Type': 'application/json', 'Accept': 'application/json',
                     **({'Authorization': 'Bearer '+key} if key else {})})
        # Neither follow redirects nor inherit ambient proxy URLs/credentials.
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
        with opener.open(request, timeout=timeout) as response:
            if (response.status != 200 or
                    response.headers.get_content_type() != 'application/json' or
                    response.headers.get('Content-Encoding', 'identity').lower() != 'identity'):
                raise Denied('PROVIDER_SCHEMA')
            declared = response.headers.get_all('Content-Length', [])
            if len(declared) > 1:
                raise Denied('PROVIDER_SCHEMA')
            if declared and (not re.fullmatch(r'[0-9]{1,8}', declared[0]) or int(declared[0]) > RESPONSE_LIMIT):
                raise Denied('PROVIDER_RESPONSE_LIMIT')
            raw = response.read(RESPONSE_LIMIT+1)
            if len(raw) > RESPONSE_LIMIT:
                raise Denied('PROVIDER_RESPONSE_LIMIT')
            if declared and len(raw) != int(declared[0]):
                raise Denied('PROVIDER_SCHEMA')
        try:
            value = strict_json(raw)
        except Denied:
            raise Denied('PROVIDER_SCHEMA') from None
        connection.send({'ok': value})
    except Denied as exc:
        connection.send({'error': exc.code})
    except Exception:
        # Do not expose a URL, credential, provider error body or exception detail.
        connection.send({'error': 'PROVIDER_UNAVAILABLE'})
    finally:
        connection.close()


def _response(value, model, output_bound):
    try:
        if type(value) is not dict or ('model' in value and value['model'] != model):
            raise ValueError
        choices = value['choices']
        if type(choices) is not list or len(choices) != 1 or type(choices[0]) is not dict:
            raise ValueError
        choice = choices[0]
        if 'index' in choice and (type(choice['index']) is not int or choice['index'] != 0):
            raise ValueError
        if 'finish_reason' in choice and choice['finish_reason'] not in {'stop', 'length'}:
            raise ValueError
        message = choice['message']
        if type(message) is not dict or message.get('role', 'assistant') != 'assistant':
            raise ValueError
        # This adapter returns text; it never dispatches provider-supplied tool calls.
        if message.get('tool_calls') or message.get('function_call'):
            raise ValueError
        content = message['content']
        if type(content) is not str or len(content.encode('utf-8')) > RESPONSE_LIMIT:
            raise ValueError
        usage = value.get('usage', {})
        if type(usage) is not dict:
            raise ValueError
        for field in ('total_tokens', 'prompt_tokens', 'completion_tokens'):
            if field in usage and (type(usage[field]) is not int or not 0 <= usage[field] <= 10**9):
                raise ValueError
        if usage.get('completion_tokens', 0) > output_bound:
            raise ValueError
        if all(field in usage for field in ('total_tokens', 'prompt_tokens', 'completion_tokens')):
            if usage['total_tokens'] != usage['prompt_tokens']+usage['completion_tokens']:
                raise ValueError
        return content, usage.get('total_tokens')
    except (ValueError, KeyError, TypeError, UnicodeError):
        raise Denied('PROVIDER_SCHEMA') from None


class LocalProvider:
    mode = 'live'
    def __init__(self, base_url, api_key=''):
        self.url = local_endpoint(base_url)+'/chat/completions'
        if type(api_key) is not str or len(api_key) > 512 or any(ord(c) < 32 or ord(c) > 126 for c in api_key):
            raise ValueError('Invalid local provider credential')
        self.key = api_key

    def complete(self, model, messages, p, semantic=False):
        # Exact installed identifiers are forwarded; aliases are not invented here.
        if (type(model) is not str or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.:/-]{0,199}', model) or
                re.search(r'(?:[:\-]cloud)(?::|$)', model, re.I)):
            raise Denied('LOCAL_MODEL_REQUIRED')
        deadline = p['deadline_seconds']
        output_bound = p['max_output_tokens']
        if type(deadline) is not int or not 1 <= deadline <= 30 or type(output_bound) is not int or not 16 <= output_bound <= 2048:
            raise Denied('PROVIDER_SCHEMA')
        if type(messages) is not list or len(messages) > 32:
            raise Denied('PROVIDER_SCHEMA')
        for m in messages:
            if (type(m) is not dict or set(m) != {'role', 'content'} or
                    m['role'] not in ('system', 'user', 'assistant') or type(m['content']) is not str):
                raise Denied('PROVIDER_SCHEMA')
        payload = {'model': model, 'messages': messages, 'stream': False,
                   'max_tokens': output_bound, 'temperature': 0}
        if semantic:
            payload['response_format'] = deepcopy(SEMANTIC_RESPONSE_FORMAT)
        try:
            if len(json.dumps(payload, allow_nan=False).encode()) > REQUEST_LIMIT:
                raise Denied('PROVIDER_REQUEST_LIMIT')
        except (UnicodeError, ValueError):
            raise Denied('PROVIDER_SCHEMA') from None
        ctx = multiprocessing.get_context('spawn')
        reader, writer = ctx.Pipe(duplex=False)
        process = ctx.Process(target=_request, args=(writer, self.url, self.key, payload, deadline))
        started = False
        try:
            expires = time.monotonic()+deadline
            process.start()
            started = True
            writer.close()
            if not reader.poll(max(0, expires-time.monotonic())):
                raise Denied('PROVIDER_TIMEOUT')
            value = reader.recv()
            if type(value) is not dict or set(value) not in ({'ok'}, {'error'}):
                raise Denied('PROVIDER_SCHEMA')
            if 'error' in value:
                code = value['error']
                raise Denied(code if code in {'PROVIDER_UNAVAILABLE', 'PROVIDER_SCHEMA', 'PROVIDER_RESPONSE_LIMIT'} else 'PROVIDER_SCHEMA')
            return _response(value['ok'], model, output_bound)
        except (EOFError, KeyError, IndexError, TypeError):
            raise Denied('PROVIDER_SCHEMA') from None
        except (OSError, RuntimeError):
            raise Denied('PROVIDER_UNAVAILABLE') from None
        finally:
            writer.close()
            reader.close()
            if started:
                if process.is_alive():
                    process.terminate()
                process.join(timeout=.5)
                if process.is_alive():
                    process.kill()
                    process.join(timeout=.5)
