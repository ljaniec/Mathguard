"""Control-layer client for applications, agent messages and MCP tool callbacks.

Examples (all use the same authenticated gateway; this creates no agent):
    client.chat('Summarize this note', 'installed-model:tag')  # application -> AI
    client.send_message('A project note', peer.receive)       # agent -> agent
    client.call_tool('demo.echo', {'text': 'note'}, mcp.call)  # agent -> MCP

The 100-second I/O timeout accommodates three local stages at the configured
30-second maximum. A client timeout is not confirmation that a request stopped.
Callbacks are trusted host integration code, not a sandbox or MCP transport/OAuth
implementation. A callback side effect cannot be undone when its result is blocked.
"""
from __future__ import annotations
import json
import urllib.error
import urllib.request
from .control import Denied, strict_json
from .provider import local_endpoint, NoRedirect

RESPONSE_LIMIT = 262144
REQUEST_LIMIT = 32768
SAFE_REASON_CODES = {
    'AUTH_REQUIRED', 'ROLE_FORBIDDEN', 'SESSION_FORBIDDEN', 'SESSION_EXPIRED',
    'APPROVAL_REQUIRED', 'APPROVAL_INVALID', 'APPROVAL_EXPIRED', 'STALE_APPROVAL',
    'MODEL_NOT_ALLOWED', 'TOOL_NOT_ALLOWED', 'ENCODED_SENSITIVE_DATA', 'SENSITIVE_DATA',
    'SEMANTIC_DENIED', 'SEMANTIC_UNAVAILABLE', 'BUDGET_EXHAUSTED', 'STEP_LIMIT',
    'REPEAT_LIMIT', 'CONFIG_UNAVAILABLE', 'PROVIDER_QUARANTINED', 'FLOW_DENIED',
    'SCHEMA_INVALID', 'ROUTE_NOT_ALLOWED', 'CONTROL_DENIED', 'GATEWAY_BUSY',
}


def _codes(value):
    codes = value.get('reason_codes') if type(value) is dict else None
    if (type(codes) is list and 1 <= len(codes) <= 16 and
            all(type(c) is str and c in SAFE_REASON_CODES for c in codes)):
        return ','.join(codes)
    return 'CONTROL_DENIED'


def _json(value):
    try:
        raw = json.dumps(value, ensure_ascii=False, allow_nan=False)
        if len(raw.encode()) > REQUEST_LIMIT:
            raise Denied('GATEWAY_REQUEST_LIMIT')
        return raw
    except (ValueError, TypeError, UnicodeError, RecursionError):
        raise Denied('GATEWAY_SCHEMA') from None


class ControlClient:
    def __init__(self, base_url, token, session_id=None, *, timeout=100):
        self.base_url = local_endpoint(base_url, provider=False)
        if type(token) is not str or not token or len(token) > 512 or any(ord(c) < 33 or ord(c) > 126 for c in token):
            raise ValueError('Invalid gateway credential')
        if type(timeout) not in (int, float) or not 1 <= timeout <= 100:
            raise ValueError('Gateway timeout must be between 1 and 100 seconds')
        self.token = token
        self.timeout = timeout
        self.opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
        if session_id is None:
            value = self._post('/v1/sessions', {})
            session_id = value.get('session_id')
            if type(session_id) is not str or not 1 <= len(session_id) <= 100:
                raise Denied(_codes(value))
        if type(session_id) is not str or not 1 <= len(session_id) <= 100:
            raise ValueError('Invalid session identifier')
        self.session_id = session_id

    def _post(self, path, body):
        request = urllib.request.Request(self.base_url+path, data=_json(body).encode(),
          headers={'Authorization': 'Bearer '+self.token, 'Content-Type': 'application/json',
                   'Accept': 'application/json'})
        try:
            with self.opener.open(request, timeout=self.timeout) as response:
                if response.headers.get_content_type() != 'application/json':
                    raise Denied('GATEWAY_SCHEMA')
                raw = response.read(RESPONSE_LIMIT+1)
                if len(raw) > RESPONSE_LIMIT:
                    raise Denied('GATEWAY_RESPONSE_LIMIT')
                value = strict_json(raw)
                if type(value) is not dict:
                    raise Denied('GATEWAY_SCHEMA')
                return value
        except urllib.error.HTTPError as error:
            # Error bodies/redirect destinations can contain sensitive text.
            error.close()
            raise Denied('GATEWAY_HTTP_ERROR') from None
        except (urllib.error.URLError, OSError, TimeoutError):
            raise Denied('GATEWAY_UNAVAILABLE') from None
        except Denied as exc:
            if exc.code.startswith('GATEWAY_'):
                raise
            raise Denied('GATEWAY_SCHEMA') from None

    def envelope(self, kind, content, target='', approval_ref=None):
        return dict(schema_version='mathguard-interaction-1', session_id=self.session_id,
          kind=kind, target=target, content=content, approval_ref=approval_ref)

    def inspect(self, kind, content, target='', approval_ref=None):
        return self._post('/v1/interactions', self.envelope(kind, content, target, approval_ref))

    def allow(self, kind, content, target='', approval_ref=None):
        decision = self.inspect(kind, content, target, approval_ref)
        if decision.get('outcome') != 'ALLOWED':
            raise Denied(_codes(decision))
        if type(decision.get('content')) is not str:
            raise Denied('GATEWAY_SCHEMA')
        return decision['content']

    def chat(self, prompt, model, source='user'):
        """Application-to-agent/model route: gate input and output in the gateway."""
        decision = self._post('/v1/models/chat', dict(session_id=self.session_id,
            model=model, prompt=prompt, source=source))
        if decision.get('outcome') != 'ALLOWED':
            raise Denied(_codes(decision))
        if type(decision.get('output')) is not str:
            raise Denied('GATEWAY_SCHEMA')
        return decision['output']

    def call_tool(self, name, arguments, invoke, approval_ref=None):
        """Gate MCP/tool arguments before dispatch and its result before release."""
        clean = self.allow('tool_call', _json(arguments), name, approval_ref)
        try:
            arguments = strict_json(clean)
        except Denied:
            raise Denied('GATEWAY_SCHEMA') from None
        try:
            result = invoke(name, arguments)
        except Exception:
            raise Denied('TRUSTED_CALLBACK_FAILURE') from None
        output = self.allow('tool_result', _json(result), name)
        try:
            return strict_json(output)
        except Denied:
            raise Denied('GATEWAY_SCHEMA') from None

    def send_message(self, content, deliver):
        """Gate outgoing agent message and any reply before releasing it."""
        clean = self.allow('agent_message', content)
        try:
            result = deliver(clean)
        except Exception:
            raise Denied('TRUSTED_CALLBACK_FAILURE') from None
        if result is None:
            return None
        if type(result) is str:
            return self.allow('agent_message', result)
        output = self.allow('agent_message', _json(result))
        try:
            return strict_json(output)
        except Denied:
            raise Denied('GATEWAY_SCHEMA') from None
