"""Bounded OpenAI-compatible local provider adapter; no paid service dependency."""
from __future__ import annotations
import json
import multiprocessing
import urllib.request
from urllib.parse import urlsplit
from .control import Denied, strict_json


def _request(connection, url, key, payload, timeout):
    try:
        request = urllib.request.Request(url, data=json.dumps(payload).encode(),
            headers={'Content-Type':'application/json', **({'Authorization':'Bearer '+key} if key else {})})
        # Do not follow provider redirects or inherit ambient HTTP proxy credentials.
        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self, *args, **kwargs): return None
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
        with opener.open(request,timeout=timeout) as response:
            raw = response.read(65537)
        if len(raw) > 65536: raise ValueError('response too large')
        connection.send({'ok':strict_json(raw)})
    except Exception:
        connection.send({'error':'PROVIDER_UNAVAILABLE'})
    finally:
        connection.close()


class LocalProvider:
    mode = 'live'
    def __init__(self, base_url, api_key=''):
        parts = urlsplit(base_url)
        if (parts.scheme not in {'http','https'} or not parts.hostname or parts.username or
            parts.password or parts.query or parts.fragment or
            (parts.scheme == 'http' and parts.hostname not in {'127.0.0.1','localhost','::1'})):
            raise ValueError('Use loopback HTTP or a trusted HTTPS model endpoint')
        self.url = base_url.rstrip('/')+'/chat/completions'
        self.key = api_key

    def complete(self, model, messages, p, semantic=False):
        ctx = multiprocessing.get_context('spawn')
        reader, writer = ctx.Pipe(duplex=False)
        payload = {'model':model,'messages':messages,'stream':False,
                   'max_tokens':p['max_output_tokens'],'temperature':0}
        if semantic: payload['response_format'] = {'type':'json_object'}
        process = ctx.Process(target=_request,args=(writer,self.url,self.key,payload,p['deadline_seconds']))
        process.start()
        writer.close()
        try:
            if not reader.poll(p['deadline_seconds']): raise Denied('PROVIDER_TIMEOUT')
            value = reader.recv()
            if 'error' in value: raise Denied(value['error'])
            response = value['ok']
            content = response['choices'][0]['message']['content']
            tokens = response.get('usage',{}).get('total_tokens')
            if type(content) is not str: raise Denied('PROVIDER_SCHEMA')
            if tokens is not None and (type(tokens) is not int or tokens < 0): raise Denied('PROVIDER_SCHEMA')
            return content,tokens
        except (EOFError, KeyError, IndexError, TypeError) as exc:
            raise Denied('PROVIDER_SCHEMA') from exc
        finally:
            if process.is_alive(): process.terminate()
            process.join(timeout=1)
            if process.is_alive(): process.kill(); process.join(timeout=1)
            reader.close()
