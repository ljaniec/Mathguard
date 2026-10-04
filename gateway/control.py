"""Strict policies and deterministic input/output/artifact controls."""
from __future__ import annotations
import base64
from collections import Counter
import hashlib
import html
import json
import math
import re
import struct
import unicodedata
from urllib.parse import unquote

MAX_JSON_BYTES = 262144
MAX_CONFIG_BYTES = 65536
MAX_JSON_DEPTH = 32
MAX_JSON_NODES = 20000
MAX_VARIANT_BYTES = 65536
MAX_ARTIFACT_BYTES = 12000
INERT_GGUF_FIXTURE_SHA256 = 'a9311856600eeba2a2c803baf41eec2eb10d885fefe9f2dffbe5c0a77a317e28'

class Denied(Exception):
    def __init__(self, code: str):
        super().__init__(code)
        self.code = code


def strict_json(raw: str | bytes, limit=MAX_JSON_BYTES):
    """Bounded, UTF-8-only JSON; no duplicate keys or non-finite numbers.

    The node/depth bounds apply independently of the caller's schema. In
    particular, an escaped lone surrogate must not reach a later UTF-8 encoder.
    """
    if type(raw) not in (str, bytes):
        raise Denied('SCHEMA_INVALID')
    try:
        if type(raw) is bytes:
            if len(raw) > limit:
                raise Denied('JSON_TOO_LARGE')
            raw = raw.decode('utf-8')
        elif len(raw.encode('utf-8')) > limit:
            raise Denied('JSON_TOO_LARGE')
    except UnicodeError as exc:
        raise Denied('SCHEMA_INVALID') from exc
    def pairs(items):
        obj = {}
        for key, value in items:
            if key in obj:
                raise Denied('DUPLICATE_JSON_KEY')
            obj[key] = value
        return obj
    def number(value):
        # Catalog IDs are injective integers derived from bounded names; unlike
        # ordinary policy integers, they can legitimately exceed 64 bits.
        if len(value) > 1024:
            raise Denied('SCHEMA_INVALID')
        return int(value)
    def floating(value):
        result = float(value)
        if not math.isfinite(result):
            raise Denied('SCHEMA_INVALID')
        return result
    try:
        value = json.loads(raw, object_pairs_hook=pairs, parse_int=number,
                           parse_float=floating,
                           parse_constant=lambda _: (_ for _ in ()).throw(Denied('SCHEMA_INVALID')))
        pending = [(value, 0)]
        nodes = 0
        while pending:
            item, depth = pending.pop()
            nodes += 1
            if nodes > MAX_JSON_NODES or depth > MAX_JSON_DEPTH:
                raise Denied('SCHEMA_INVALID')
            if type(item) is str:
                item.encode('utf-8')
            elif type(item) is dict:
                pending.extend((x, depth + 1) for pair in item.items() for x in pair)
            elif type(item) is list:
                pending.extend((x, depth + 1) for x in item)
        return value
    except (ValueError, UnicodeError, RecursionError, OverflowError) as exc:
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
    if type(x) is not str:
        raise Denied('SCHEMA_INVALID')
    try:
        if len(x.encode('utf-8')) > limit:
            raise Denied('SCHEMA_INVALID')
    except UnicodeError as exc:
        raise Denied('SCHEMA_INVALID') from exc
    return x


def vector(x):
    if type(x) is not list or len(x) != 4:
        raise Denied('SCHEMA_INVALID')
    return [integer(v) for v in x]


POLICY_KEYS = {'schema_version','epoch','profile','pii_action','semantic_threshold',
 'allowed_models','semantic_model','budget_limit','call_bound','deadline_seconds',
 'max_output_tokens','max_input_bytes','max_session_steps','repeat_limit',
 'max_transfer','approval_threshold','model_clearance','artifact_repositories','artifact_sha256'}
POLICY_KEYS |= {'allowed_tools','irreversible_tools','pii_redact_at','pii_block_at','semantic_review_at'}


def policy(raw):
    p = strict_json(raw, MAX_CONFIG_BYTES)
    keys(p, POLICY_KEYS)
    if p['schema_version'] != 'mathguard-policy-3' or p['profile'] not in ('strict','balanced','permissive'):
        raise Denied('POLICY_INVALID')
    if p['pii_action'] not in ('block','redact'):
        raise Denied('POLICY_INVALID')
    for field, low, high in [('epoch',1,10**9),('semantic_threshold',1,100),
      ('deadline_seconds',1,30),('max_output_tokens',16,2048),('max_input_bytes',32,8192),
      ('max_session_steps',1,1000),('repeat_limit',1,20),('max_transfer',1,50000),
      ('approval_threshold',1,50000),('model_clearance',0,2)]:
        integer(p[field],low,high)
    for field in ['pii_redact_at','pii_block_at','semantic_review_at']:
        integer(p[field],1,101)
    if p['pii_redact_at'] > p['pii_block_at']:
        raise Denied('POLICY_INVALID')
    for field in ['allowed_tools','irreversible_tools']:
        a=p[field]
        if type(a) is not list or len(a)>32 or any(type(v) is not str or not re.fullmatch(r'[A-Za-z0-9_.-]{1,100}',v) for v in a):
            raise Denied('POLICY_INVALID')
        if len(set(a))!=len(a): raise Denied('POLICY_INVALID')
    for field in ['allowed_models','artifact_repositories','artifact_sha256']:
        a = p[field]
        if type(a) is not list or not 1 <= len(a) <= 32 or any(type(v) is not str or not 1 <= len(v) <= 200 for v in a):
            raise Denied('POLICY_INVALID')
        if len(set(a)) != len(a):
            raise Denied('POLICY_INVALID')
    for model in p['allowed_models']:
        model_name(model)
    for repository in p['artifact_repositories']:
        repository_name(repository)
    if model_name(p['semantic_model']) not in p['allowed_models']:
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
    f = strict_json(raw, MAX_CONFIG_BYTES)
    keys(f, {'schema_version','version','source','signatures'})
    if f['schema_version'] != 'mathguard-signatures-1': raise Denied('FEED_INVALID')
    integer(f['version'],1,10**9)
    if not text(f['source'],300).strip() or any(unicodedata.category(c).startswith('C') for c in f['source']):
        raise Denied('FEED_INVALID')
    if type(f['signatures']) is not list or len(f['signatures']) > 100: raise Denied('FEED_INVALID')
    ids = set()
    for s in f['signatures']:
        keys(s, {'id','contains','reason'})
        if not re.fullmatch('[A-Z0-9_]{1,64}', text(s['id'],64)) or s['id'] in ids: raise Denied('FEED_INVALID')
        if not re.fullmatch('[A-Z0-9_]{1,64}', text(s['reason'],64)): raise Denied('FEED_INVALID')
        if not signature_text(text(s['contains'],200)).strip(): raise Denied('FEED_INVALID')
        # Reject invisible/control-only matches and ambiguous provenance. A
        # signature is literal data, never a regex or code evaluated at reload.
        if any(unicodedata.category(c).startswith('C') for c in s['contains']):
            raise Denied('FEED_INVALID')
        ids.add(s['id'])
    return f


def repository_name(value):
    value = text(value, 200)
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,99}(?:/[A-Za-z0-9][A-Za-z0-9_.-]{0,99}){1,3}', value):
        raise Denied('ARTIFACT_REPOSITORY')
    return value


def model_name(value):
    value = text(value, 200)
    # Exact local model IDs, including namespaced Ollama IDs and an optional tag.
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9_.-]{0,99}(?:/[A-Za-z0-9][A-Za-z0-9_.-]{0,99}){0,3}(?::[A-Za-z0-9][A-Za-z0-9_.-]{0,99})?', value):
        raise Denied('POLICY_INVALID')
    return value


PATTERNS = (
    ('SECRET', re.compile(r'(?<![A-Za-z0-9_])(?:sk-[A-Za-z0-9_-]{12,8192}|MG_SECRET_[A-Za-z0-9_]{4,8192}|AKIA[A-Z0-9]{16}|(?:ghp_|github_pat_|glpat-)[A-Za-z0-9_-]{16,8192})(?![A-Za-z0-9_])')),
    # A truncated PEM block is still sensitive: redact through the end of the
    # field rather than leaving its key material behind after the BEGIN marker.
    ('SECRET', re.compile(r'-----BEGIN (?:RSA |EC |OPENSSH |DSA )?PRIVATE KEY-----[\s\S]{0,8192}')),
    ('SECRET', re.compile(r'(?i)\b(?:api[_-]?key|access[_-]?token|client[_-]?secret|password)[\"\']?\s{0,8}[:=]\s{0,8}[\"\']?[^\s\"\',;{}\[\]]{8,8192}')),
    ('SECRET', re.compile(r'(?i)\bBearer[ \t]{1,8}[A-Za-z0-9._~+/-]{16,8192}={0,2}')),
    ('EMAIL', re.compile(r'(?<![A-Za-z0-9._%+-])[A-Za-z0-9._%+-]{1,64}@[A-Za-z0-9-]{1,63}(?:\.[A-Za-z0-9-]{1,63}){0,3}\.[A-Za-z]{2,24}(?![A-Za-z0-9.-])')),
    ('IBAN', re.compile(r'\b[A-Z]{2}[0-9]{2}(?:[ -]?[0-9A-Z]){11,30}\b')),
    ('PESEL', re.compile(r'(?i)\bPESEL[ \t]{0,4}[:=]?[ \t]{0,4}[0-9]{11}\b')),
    ('PHONE', re.compile(r'(?i)(?:\b(?:tel(?:efon)?|phone)[ \t]{0,4}[:=]?[ \t]{0,4}(?:\+48[ -]?)?|(?<![0-9])\+48[ -]?)[0-9]{3}[ -]?[0-9]{3}[ -]?[0-9]{3}(?![0-9])')),
)

BASE64_TOKEN = re.compile(r'(?<![A-Za-z0-9+/_-])[A-Za-z0-9+/_-]{16,8192}={0,2}(?![A-Za-z0-9+/_=-])')
HEX_TOKEN = re.compile(r'(?i)\b(?:hex:|0x)([0-9a-f]{16,8192})\b')
# Deliberately finite common ASCII homoglyphs, not language transliteration.
CONFUSABLES = str.maketrans('АВЕКМНОРСТХаеорсухіЈј', 'ABEKMHOPCTXaeopcyxiJj')
CREDENTIAL_FIELD = re.compile(r'(?i)(?:api[_-]?key|access[_-]?token|client[_-]?secret|password)')


def normalized_text(value):
    normalized = unicodedata.normalize('NFKC', value)
    return ''.join(c for c in normalized if unicodedata.category(c) != 'Cf')


def variant_records(value):
    """Finite text decoding only: never archives, compression or deserialization.

    At most three decoding rounds, 48 candidates and 64 KiB of total variant
    bytes. Exhaustion fails closed instead of silently skipping later tokens.
    """
    original = normalized_text(text(value, 8192))
    if len(original.encode('utf-8')) > 8192:
        raise Denied('ENCODING_LIMIT')
    candidates = [original]
    seen = {original}
    token_decoded = set()
    total = len(original.encode('utf-8'))
    frontier = [original]
    def add(candidate, output, token=False):
        nonlocal total
        candidate = normalized_text(candidate)
        if token:
            token_decoded.add(candidate)
        if candidate in seen:
            return
        size = len(candidate.encode('utf-8'))
        if size > 8192 or len(candidates) >= 48 or total + size > MAX_VARIANT_BYTES:
            raise Denied('ENCODING_LIMIT')
        seen.add(candidate); candidates.append(candidate); output.append(candidate); total += size
    for _ in range(3):
        following = []
        for candidate in frontier:
            inherited_token = candidate in token_decoded
            add(candidate.translate(CONFUSABLES), following, token=inherited_token)
            try:
                add(unquote(candidate, errors='strict'), following, token=inherited_token)
            except UnicodeError:
                pass
            add(html.unescape(candidate), following, token=inherited_token)
            for match in BASE64_TOKEN.finditer(candidate):
                token = match.group()
                try:
                    # Accept the two standard alphabets but reject mixed forms.
                    if any(c in token for c in '+/') and any(c in token for c in '-_'):
                        continue
                    padded = token + '=' * ((-len(token)) % 4)
                    decoded = base64.b64decode(padded, altchars=b'-_', validate=True).decode('utf-8')
                    if decoded and all(c.isprintable() or c in '\n\r\t' for c in decoded):
                        add(decoded, following, token=True)
                except (ValueError, UnicodeError):
                    pass
            for match in HEX_TOKEN.finditer(candidate):
                try:
                    add(bytes.fromhex(match.group(1)).decode('utf-8'), following, token=True)
                except (ValueError, UnicodeError):
                    pass
        if not following:
            break
        frontier = following
    return [(candidate, candidate in token_decoded) for candidate in candidates]


def variants(value):
    return [candidate for candidate, _ in variant_records(value)]


def catalog_id(value):
    """Injective, length-preserving catalog IDs, never collision-prone hash IDs."""
    return int.from_bytes(b'\x01'+value.encode('utf-8'),'big')


def signature_text(value):
    return ' '.join(variants(value)[0].casefold().split())


def control_policy(p,f):
    return dict(strictness=p['profile'],allowedModels=[catalog_id(x) for x in p['allowed_models']],
      allowedTools=[catalog_id(x) for x in p['allowed_tools']],
      irreversibleTools=[catalog_id(x) for x in p['irreversible_tools']],
      pinnedArtifacts=[catalog_id(x) for x in p['artifact_sha256']],
      signatures=[list(signature_text(x['contains']).encode()) for x in f['signatures']],
      piiRedactAt=p['pii_redact_at'],
      piiBlockAt=min(p['pii_block_at'],p['pii_redact_at']) if p['pii_action']=='block' else p['pii_block_at'],
      semReviewAt=min(p['semantic_review_at'],p['semantic_threshold']),semBlockAt=p['semantic_threshold'],
      maxSteps=p['max_session_steps'])


def sensitive_matches(value):
    for kind, pattern in PATTERNS:
        for match in pattern.finditer(value):
            if kind == 'IBAN':
                compact = re.sub('[ -]', '', match.group())
                # The international checksum greatly reduces accidental matches
                # on ordinary catalog IDs. This is still not account ownership.
                digits = ''.join(str(ord(c)-55) if c.isalpha() else c for c in compact[4:]+compact[:4])
                if not 15 <= len(compact) <= 34 or int(digits) % 97 != 1:
                    continue
            if kind == 'PESEL':
                digits = re.search('[0-9]{11}', match.group()).group()
                if (10 - sum(int(n)*w for n,w in zip(digits[:10], [1,3,7,9,1,3,7,9,1,3])) % 10) % 10 != int(digits[-1]):
                    continue
            yield kind, match.start(), match.end()


def redact_text(value):
    matches = sorted(sensitive_matches(value), key=lambda m:(m[1], -m[2]))
    merged = []
    for kind,start,stop in matches:
        if merged and start <= merged[-1][2]:
            old_kind,old_start,old_stop = merged[-1]
            merged[-1] = ('SECRET' if 'SECRET' in (old_kind,kind) else old_kind,
                          old_start,max(old_stop,stop))
        else:
            merged.append((kind,start,stop))
    output, end = [], 0
    for kind, start, stop in merged:
        output.extend([value[end:start], '[REDACTED_'+kind+']']); end = stop
    output.append(value[end:])
    return ''.join(output)


def detection(value,p):
    """Bounded facts only; compiled Lean combines their policy restrictions.

    Valid serialized objects/arrays are inspected as data. Redaction preserves
    keys, numbers, booleans and container types; sensitive keys are refused.
    Hidden/encoded sensitive values are refused by the host, independently of
    adjustable PII thresholds, because safe source-to-decoding redaction is not
    established. Malformed structured tool data remains the SDK's strict parser
    responsibility before callback dispatch.
    """
    value = text(value,p['max_input_bytes'])
    structured = None
    if value.lstrip().startswith(('{','[')):
        try:
            structured = strict_json(value)
        except Denied:
            pass
    base = normalized_text(value)
    leaves, labeled_leaves, credential_values = [], [], []
    if type(structured) in (dict, list):
        def clean_data(item):
            if type(item) is dict:
                for key in item:
                    if key != normalized_text(key):
                        raise Denied('STRUCTURED_KEY_AMBIGUOUS')
                    if any(any(sensitive_matches(c)) for c in variants(key)):
                        raise Denied('STRUCTURED_SENSITIVE_KEY')
                for key, child in item.items():
                    if CREDENTIAL_FIELD.fullmatch(key) and type(child) is not str:
                        raise Denied('STRUCTURED_SENSITIVE_VALUE')
                    if type(child) in (int, float) and any(sensitive_matches(key+': '+str(child))):
                        raise Denied('STRUCTURED_SENSITIVE_VALUE')
                    if type(child) is str:
                        labeled_leaves.append(key+': '+normalized_text(child))
                        if CREDENTIAL_FIELD.fullmatch(key) and child:
                            credential_values.append(child)
                return {key: clean_data(child) for key,child in item.items()}
            if type(item) is list:
                return [clean_data(child) for child in item]
            if type(item) is str:
                result = normalized_text(item)
                leaves.append(result)
                return result
            return item
        structured = clean_data(structured)
        base = json.dumps(structured, ensure_ascii=False, separators=(',',':'))
    indexed, found, total, encoded = {}, ['SECRET'] if credential_values else [], 0, False
    def add_view(view, inspect_pii=True, direct=True):
        nonlocal total,encoded
        records = variant_records(view)
        plain = Counter((kind, records[0][0][start:stop]) for kind,start,stop in sensitive_matches(records[0][0])) if direct else Counter()
        for index,(candidate,token) in enumerate(records):
            if candidate not in indexed:
                size = len(candidate.encode())
                if len(indexed) >= 48 or total+size > MAX_VARIANT_BYTES:
                    raise Denied('ENCODING_LIMIT')
                indexed[candidate] = token; total += size
            if inspect_pii:
                matches = Counter((kind,candidate[start:stop]) for kind,start,stop in sensitive_matches(candidate))
                found.extend(kind for kind,_ in matches)
                if ((not direct or index) and ((token and matches) or (matches-plain))):
                    encoded = True
    add_view(base)
    for context in labeled_leaves:
        add_view(context)
    if leaves:
        # First remove already recognized complete leaf values; reconstruction
        # must not append a benign neighbor to an email and invent new PII.
        safe_leaves = [redact_text(leaf) for leaf in leaves]
        for view in (' '.join(safe_leaves), ''.join(safe_leaves)):
            add_view(view, direct=False)
        # Full reconstructions are signature evidence. Sensitive content that
        # occurs only in the sanitized reconstruction above is refused because
        # mapping a concatenation back into source fields is ambiguous.
        for view in (' '.join(leaves), ''.join(leaves)):
            add_view(view, inspect_pii=False)
    candidates = list(indexed)
    score=100 if encoded else 80 if 'SECRET' in found else 60 if found else 0
    clean=redact_text(candidates[0])
    if type(structured) in (dict, list):
        def redact_data(item):
            if type(item) is dict:
                result = {}
                for key,child in item.items():
                    if CREDENTIAL_FIELD.fullmatch(key) and child:
                        result[key] = '[REDACTED_SECRET]'
                        continue
                    clean_child = redact_data(child)
                    if type(child) is str and clean_child == child:
                        contextual = list(sensitive_matches(key+': '+child))
                        if contextual:
                            kind = 'SECRET' if any(kind=='SECRET' for kind,_,_ in contextual) else contextual[0][0]
                            clean_child = '[REDACTED_'+kind+']'
                    result[key] = clean_child
                return result
            if type(item) is list:
                return [redact_data(child) for child in item]
            return redact_text(item) if type(item) is str else item
        clean = json.dumps(redact_data(structured), ensure_ascii=False, separators=(',',':'))
    content=[]
    for candidate in candidates:
        content.extend(' '.join(candidate.casefold().split()).encode());content.append(256)
    return {'content':content,'piiScore':score,'clean':clean,'kinds':sorted(set(found)),
            'level':2 if 'SECRET' in found else 1 if found else 0,'encoded':encoded}


def signature_candidates(value,p,facts=None):
    """The exact normalized candidate segments submitted to the Lean matcher."""
    content = (facts if facts is not None else detection(value,p))['content']
    segments, current = [], bytearray()
    for byte in content:
        if byte == 256:
            segments.append(current.decode('utf-8')); current.clear()
        else:
            current.append(byte)
    if current:
        segments.append(current.decode('utf-8'))
    return segments


def safetensors_header(content):
    if len(content) < 8:
        raise Denied('ARTIFACT_FORMAT')
    size = int.from_bytes(content[:8], 'little')
    if not 2 <= size <= min(8192, len(content)-8) or content[8:9] != b'{':
        raise Denied('ARTIFACT_FORMAT')
    header = strict_json(content[8:8+size], limit=8192)
    if type(header) is not dict or len(header) > 128:
        raise Denied('ARTIFACT_FORMAT')
    widths = {'BOOL':1,'U8':1,'I8':1,'I16':2,'U16':2,'F16':2,'BF16':2,
              'I32':4,'U32':4,'F32':4,'I64':8,'U64':8,'F64':8}
    payload = len(content)-8-size
    spans = []
    for name, tensor in header.items():
        if name == '__metadata__':
            if type(tensor) is not dict or len(tensor)>64:
                raise Denied('ARTIFACT_FORMAT')
            for key,value in tensor.items():
                text(key,200); text(value,1000)
            continue
        text(name,200)
        keys(tensor, {'dtype','shape','data_offsets'})
        dtype = text(tensor['dtype'],16)
        if dtype not in widths or type(tensor['shape']) is not list or len(tensor['shape'])>8:
            raise Denied('ARTIFACT_FORMAT')
        elements = 1
        for dimension in tensor['shape']:
            elements *= integer(dimension,0,10**6)
            if elements > MAX_ARTIFACT_BYTES:
                raise Denied('ARTIFACT_FORMAT')
        offsets = tensor['data_offsets']
        if type(offsets) is not list or len(offsets) != 2:
            raise Denied('ARTIFACT_FORMAT')
        start,stop = [integer(offset,0,payload) for offset in offsets]
        if stop-start != elements*widths[dtype]:
            raise Denied('ARTIFACT_FORMAT')
        spans.append((start,stop))
    end = 0
    for start,stop in sorted(spans):
        if start != end:
            raise Denied('ARTIFACT_FORMAT')
        end = stop
    if end != payload:
        raise Denied('ARTIFACT_FORMAT')


def gguf_header(content):
    """Bounded GGUF v2/v3 structural subset, never a model loader.

    Only scalar/flat-array metadata and F32/F16 tensors are admitted. A format
    outside this subset is refused rather than guessed; quantized real weights
    belong to the local provider, not this small inert artifact-check endpoint.
    """
    offset = 0
    def take(size):
        nonlocal offset
        if size < 0 or offset+size > len(content):
            raise Denied('ARTIFACT_FORMAT')
        result = content[offset:offset+size]; offset += size
        return result
    def number(fmt):
        return struct.unpack('<'+fmt, take(struct.calcsize('<'+fmt)))[0]
    def string():
        size = number('Q')
        if size > 4096:
            raise Denied('ARTIFACT_FORMAT')
        try:
            return text(take(size).decode('utf-8'),4096)
        except UnicodeError as exc:
            raise Denied('ARTIFACT_FORMAT') from exc
    scalar_formats = {0:'B',1:'b',2:'H',3:'h',4:'I',5:'i',6:'f',7:'B',10:'Q',11:'q',12:'d'}
    def metadata_value(kind, array=False):
        if kind == 8:
            return string()
        if kind in scalar_formats:
            value = number(scalar_formats[kind])
            if kind == 7 and value not in (0,1):
                raise Denied('ARTIFACT_FORMAT')
            if type(value) is float and not math.isfinite(value):
                raise Denied('ARTIFACT_FORMAT')
            return value
        if kind == 9 and not array:
            element_kind, count = number('I'), number('Q')
            if count > 512 or element_kind == 9:
                raise Denied('ARTIFACT_FORMAT')
            return [metadata_value(element_kind, array=True) for _ in range(count)]
        raise Denied('ARTIFACT_FORMAT')
    if take(4) != b'GGUF' or number('I') not in (2,3):
        raise Denied('ARTIFACT_FORMAT')
    tensors, entries = number('Q'), number('Q')
    if tensors > 128 or entries > 128:
        raise Denied('ARTIFACT_FORMAT')
    metadata, metadata_kinds = {}, {}
    for _ in range(entries):
        key = string()
        if not key or key in metadata:
            raise Denied('ARTIFACT_FORMAT')
        kind = number('I')
        metadata[key] = metadata_value(kind)
        metadata_kinds[key] = kind
    alignment = metadata.get('general.alignment',32)
    if 'general.alignment' in metadata and metadata_kinds['general.alignment'] != 4:
        raise Denied('ARTIFACT_FORMAT')
    if type(alignment) is not int or not 1 <= alignment <= 4096 or alignment & (alignment-1):
        raise Denied('ARTIFACT_FORMAT')
    names, spans = set(), []
    for _ in range(tensors):
        name = string()
        if not name or name in names:
            raise Denied('ARTIFACT_FORMAT')
        names.add(name)
        dimensions = number('I')
        if not 1 <= dimensions <= 4:
            raise Denied('ARTIFACT_FORMAT')
        elements = 1
        for _ in range(dimensions):
            dimension = number('Q')
            if not 1 <= dimension <= 10**6:
                raise Denied('ARTIFACT_FORMAT')
            elements *= dimension
            if elements > MAX_ARTIFACT_BYTES:
                raise Denied('ARTIFACT_FORMAT')
        kind, start = number('I'), number('Q')
        if kind not in (0,1) or start % alignment:
            raise Denied('ARTIFACT_FORMAT')
        spans.append((start,start+elements*(4 if kind==0 else 2)))
    data_start = (offset+alignment-1)//alignment*alignment
    # Empty inert GGUF headers need no trailing alignment bytes.
    if not tensors and len(content) == offset:
        return
    if data_start > len(content) or any(content[offset:data_start]):
        raise Denied('ARTIFACT_FORMAT')
    payload = content[data_start:]
    end = 0
    for start,stop in sorted(spans):
        if start < end or stop > len(payload) or any(payload[end:start]):
            raise Denied('ARTIFACT_FORMAT')
        end = stop
    if end != len(payload):
        raise Denied('ARTIFACT_FORMAT')


def artifact(manifest,p):
    keys(manifest, {'repository','sha256','format','trust_remote_code','content_base64'})
    repository = repository_name(manifest['repository'])
    sha = text(manifest['sha256'],64)
    if not re.fullmatch('[0-9a-f]{64}',sha):
        raise Denied('ARTIFACT_HASH')
    format = text(manifest['format'],32)
    if format not in ('safetensors','gguf'):
        raise Denied('UNSAFE_DESERIALIZATION')
    if manifest['trust_remote_code'] is not False:
        raise Denied('MODEL_REMOTE_CODE')
    try:
        encoded = text(manifest['content_base64'],16000)
        content = base64.b64decode(encoded,validate=True)
        if base64.b64encode(content).decode('ascii') != encoded or len(content) > MAX_ARTIFACT_BYTES:
            raise Denied('ARTIFACT_ENCODING')
    except (ValueError,UnicodeError) as exc:
        raise Denied('ARTIFACT_ENCODING') from exc
    actual_hash = hashlib.sha256(content).hexdigest()
    if actual_hash != sha: raise Denied('ARTIFACT_HASH_MISMATCH')
    if repository not in p['artifact_repositories']: raise Denied('ARTIFACT_REPOSITORY')
    if sha not in p['artifact_sha256']: raise Denied('ARTIFACT_HASH')
    fixture = format == 'gguf' and sha == INERT_GGUF_FIXTURE_SHA256
    if format == 'gguf' and not fixture:
        gguf_header(content)
    if format == 'safetensors':
        safetensors_header(content)
    return {'outcome':'ALLOWED','reason_codes':['MANIFEST_ALLOWED'],
            'actual_sha256':actual_hash,
            'assurance':('Known inert demonstration fixture, not a runnable GGUF model. ' if fixture else '')+
              'Bounded byte/hash/structural admission only; no model loading, malware completeness or model-behavior guarantee.'}


def digest(value):
    return hashlib.sha256(json.dumps(value,sort_keys=True,separators=(',',':')).encode()).hexdigest()
