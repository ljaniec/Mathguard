"""Strict policies and deterministic input/output/artifact controls."""
from __future__ import annotations
import base64
import hashlib
import json
import re
import unicodedata
from urllib.parse import unquote

class Denied(Exception):
    def __init__(self, code: str):
        super().__init__(code)
        self.code = code


def strict_json(raw: str | bytes):
    def pairs(items):
        obj = {}
        for key, value in items:
            if key in obj:
                raise Denied('DUPLICATE_JSON_KEY')
            obj[key] = value
        return obj
    try:
        return json.loads(raw, object_pairs_hook=pairs,
                          parse_constant=lambda _: (_ for _ in ()).throw(Denied('SCHEMA_INVALID')))
    except (ValueError, UnicodeError, RecursionError) as exc:
        raise Denied('SCHEMA_INVALID') from exc


def keys(obj, expected):
    if type(obj) is not dict or set(obj) != set(expected):
        raise Denied('SCHEMA_INVALID')


def integer(x, low=0, high=10**12):
    if type(x) is not int or not low <= x <= high:
        raise Denied('SCHEMA_INVALID')
    return x


def decimal(x):
    if type(x) is not str or not re.fullmatch(r'0|[1-9][0-9]{0,14}', x):
        raise Denied('SCHEMA_INVALID')
    return int(x)


def text(x, limit=4096):
    if type(x) is not str or len(x.encode('utf-8')) > limit:
        raise Denied('SCHEMA_INVALID')
    return x


def vector(x):
    if type(x) is not list or len(x) != 4:
        raise Denied('SCHEMA_INVALID')
    return [integer(v) for v in x]


POLICY_KEYS = {'schema_version','epoch','profile','pii_action','semantic_threshold',
 'allowed_models','semantic_model','budget_limit','call_bound','deadline_seconds',
 'max_output_tokens','max_input_bytes','max_session_steps','repeat_limit',
 'max_transfer','approval_threshold','model_clearance','artifact_repositories','artifact_sha256'}


def policy(raw):
    p = strict_json(raw)
    keys(p, POLICY_KEYS)
    if p['schema_version'] != 'mathguard-policy-2' or p['profile'] not in ('strict','balanced','permissive'):
        raise Denied('POLICY_INVALID')
    if p['pii_action'] not in ('block','redact'):
        raise Denied('POLICY_INVALID')
    for field, low, high in [('epoch',1,10**9),('semantic_threshold',1,100),
      ('deadline_seconds',1,30),('max_output_tokens',16,2048),('max_input_bytes',32,8192),
      ('max_session_steps',1,1000),('repeat_limit',1,20),('max_transfer',1,50000),
      ('approval_threshold',1,50000),('model_clearance',0,2)]:
        integer(p[field],low,high)
    for field in ['allowed_models','artifact_repositories','artifact_sha256']:
        a = p[field]
        if type(a) is not list or not 1 <= len(a) <= 32 or any(type(v) is not str or not 1 <= len(v) <= 200 for v in a):
            raise Denied('POLICY_INVALID')
        if len(set(a)) != len(a):
            raise Denied('POLICY_INVALID')
    if p['semantic_model'] not in p['allowed_models']:
        raise Denied('POLICY_INVALID')
    if any(not re.fullmatch('[0-9a-f]{64}', h) for h in p['artifact_sha256']):
        raise Denied('POLICY_INVALID')
    limits, bound = vector(p['budget_limit']), vector(p['call_bound'])
    if any(a > b for a,b in zip(bound,limits)) or bound[3] != 1:
        raise Denied('POLICY_INVALID')
    if bound[1] < p['max_input_bytes'] + p['max_output_tokens'] + 2048 or bound[2] < p['deadline_seconds']*1000+1000:
        raise Denied('POLICY_INVALID')
    return p


def feed(raw):
    f = strict_json(raw)
    keys(f, {'schema_version','version','source','signatures'})
    if f['schema_version'] != 'mathguard-signatures-1': raise Denied('FEED_INVALID')
    integer(f['version'],1,10**9)
    text(f['source'],300)
    if type(f['signatures']) is not list or len(f['signatures']) > 100: raise Denied('FEED_INVALID')
    ids = set()
    for s in f['signatures']:
        keys(s, {'id','contains','reason'})
        if not re.fullmatch('[A-Z0-9_]{1,64}', text(s['id'],64)) or s['id'] in ids: raise Denied('FEED_INVALID')
        if not re.fullmatch('[A-Z0-9_]{1,64}', text(s['reason'],64)): raise Denied('FEED_INVALID')
        if not text(s['contains'],200).strip(): raise Denied('FEED_INVALID')
        ids.add(s['id'])
    return f


PATTERNS = (
    ('SECRET', re.compile(r'\b(?:sk-[A-Za-z0-9_-]{12,}|MG_SECRET_[A-Za-z0-9_]{4,}|AKIA[A-Z0-9]{16})\b')),
    ('EMAIL', re.compile(r'\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b')),
    ('IBAN', re.compile(r'\b[A-Z]{2}[0-9]{2}(?: ?[0-9A-Z]){11,30}\b')),
)


def variants(value):
    normalized = unicodedata.normalize('NFKC', value)
    normalized = ''.join(c for c in normalized if unicodedata.category(c) != 'Cf')
    candidates = [normalized, unquote(normalized)]
    for token in re.findall(r'(?<![A-Za-z0-9+/])[A-Za-z0-9+/]{16,}={0,2}(?![A-Za-z0-9+/])', normalized)[:16]:
        try:
            candidates.append(base64.b64decode(token,validate=True).decode('utf-8'))
        except (ValueError, UnicodeError): pass
    return candidates


def inspect_text(value, p, f):
    value = text(value,p['max_input_bytes'])
    candidates = variants(value)
    for candidate in candidates:
        for sig in f['signatures']:
            if sig['contains'].casefold() in candidate.casefold():
                raise Denied('SIGNATURE_'+sig['reason'])
    detected = [(kind,pattern) for kind,pattern in PATTERNS if any(pattern.search(c) for c in candidates)]
    if not detected: return value, [], 0
    if p['pii_action'] == 'block': raise Denied('SENSITIVE_DATA')
    # Encoded findings are blocked: masking only the decoded copy would leak the original.
    if any(pattern.search(c) for _,pattern in detected for c in candidates[1:] if c != candidates[0]):
        raise Denied('ENCODED_SENSITIVE_DATA')
    sanitized = candidates[0]
    for kind,pattern in detected: sanitized = pattern.sub('[REDACTED_'+kind+']',sanitized)
    return sanitized, sorted({k for k,_ in detected}), 2 if any(k=='SECRET' for k,_ in detected) else 1


def artifact(manifest,p):
    keys(manifest, {'repository','sha256','format','trust_remote_code','content_base64'})
    try:
        content = base64.b64decode(text(manifest['content_base64'],16000),validate=True)
    except (ValueError,UnicodeError) as exc:
        raise Denied('ARTIFACT_ENCODING') from exc
    actual_hash = hashlib.sha256(content).hexdigest()
    if actual_hash != manifest['sha256']: raise Denied('ARTIFACT_HASH_MISMATCH')
    if manifest['repository'] not in p['artifact_repositories']: raise Denied('ARTIFACT_REPOSITORY')
    if manifest['sha256'] not in p['artifact_sha256']: raise Denied('ARTIFACT_HASH')
    if manifest['format'] not in ('safetensors','gguf'): raise Denied('UNSAFE_DESERIALIZATION')
    if manifest['trust_remote_code'] is not False: raise Denied('MODEL_REMOTE_CODE')
    if manifest['format']=='gguf' and not content.startswith(b'GGUF'): raise Denied('ARTIFACT_FORMAT')
    if manifest['format']=='safetensors':
        if len(content)<8: raise Denied('ARTIFACT_FORMAT')
        header_size=int.from_bytes(content[:8],'little')
        if not 2 <= header_size <= len(content)-8: raise Denied('ARTIFACT_FORMAT')
        header=strict_json(content[8:8+header_size])
        if type(header) is not dict: raise Denied('ARTIFACT_FORMAT')
    return {'outcome':'ALLOWED','reason_codes':['MANIFEST_ALLOWED'],
            'actual_sha256':actual_hash,
            'assurance':'Bounded byte/hash/header admission only; no model loading, malware completeness or model-behavior guarantee.'}


def digest(value):
    return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':')).encode()).hexdigest()
