"""Small HTTP interception SDK for applications, agents and MCP client wrappers.

Only ALLOWED responses release sanitized content to the caller. External callbacks
are trusted integration code; this SDK does not sandbox them or implement MCP OAuth.
"""
from __future__ import annotations
import json
import urllib.request
from urllib.parse import urlsplit
from .control import Denied, strict_json


class ControlClient:
    def __init__(self,base_url,token,session_id=None):
        parts=urlsplit(base_url)
        if (parts.scheme not in {'http','https'} or not parts.hostname or parts.username or
            parts.password or parts.query or parts.fragment or
            (parts.scheme=='http' and parts.hostname not in {'127.0.0.1','localhost','::1'})):
            raise ValueError('Use loopback HTTP or a trusted HTTPS gateway endpoint')
        self.base_url=base_url.rstrip('/')
        self.token=token
        class NoRedirect(urllib.request.HTTPRedirectHandler):
            def redirect_request(self,*args,**kwargs): return None
        self.opener=urllib.request.build_opener(urllib.request.ProxyHandler({}),NoRedirect())
        self.session_id=session_id or self._post('/v1/sessions',{})['session_id']

    def _post(self,path,body):
        request=urllib.request.Request(self.base_url+path,data=json.dumps(body).encode(),
          headers={'Authorization':'Bearer '+self.token,'Content-Type':'application/json'})
        with self.opener.open(request,timeout=65) as response:
            raw=response.read(262145)
            if len(raw)>262144:raise Denied('GATEWAY_RESPONSE_LIMIT')
            return strict_json(raw)

    def envelope(self,kind,content,target='',approval_ref=None):
        return dict(schema_version='mathguard-interaction-1',session_id=self.session_id,
          kind=kind,target=target,content=content,approval_ref=approval_ref)

    def inspect(self,kind,content,target='',approval_ref=None):
        return self._post('/v1/interactions',self.envelope(kind,content,target,approval_ref))

    def allow(self,kind,content,target='',approval_ref=None):
        decision=self.inspect(kind,content,target,approval_ref)
        if decision.get('outcome')!='ALLOWED':
            raise Denied(','.join(decision.get('reason_codes',['CONTROL_DENIED'])))
        return decision['content']

    def call_tool(self,name,arguments,invoke,approval_ref=None):
        """Wrap an MCP/tools-call callback and inspect its result before returning it."""
        clean=self.allow('tool_call',json.dumps(arguments,ensure_ascii=False),name,approval_ref)
        # Parsing sanitized JSON before dispatch prevents malformed redaction forwarding.
        result=invoke(name,strict_json(clean))
        output=self.allow('tool_result',json.dumps(result,ensure_ascii=False),name)
        return strict_json(output)

    def send_message(self,content,deliver):
        return deliver(self.allow('agent_message',content))
