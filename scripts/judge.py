#!/usr/bin/env python3
"""Private, local-model-only setup and launcher. No fixture or API-key fallback."""
from __future__ import annotations
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import secrets
import shutil
import stat
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from urllib.parse import urlsplit

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
from gateway.control import Denied, feed, policy, strict_json
from gateway.semantic import classifier_messages, SEMANTIC_SYSTEM_PROMPT, SEMANTIC_RESPONSE_FORMAT


class SetupError(Exception):
    pass


def runtime_dir():
    explicit = os.environ.get('MATHGUARD_RUNTIME_DIR')
    if explicit:
        return Path(explicit).expanduser().absolute()
    suffix = hashlib.sha256(str(ROOT).encode()).hexdigest()[:10]
    return Path.home() / '.local' / 'state' / 'mathguard' / suffix


def private_dir(path):
    if path.is_symlink():
        raise SetupError('Runtime directory must not be a symbolic link.')
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    info = path.stat()
    if not stat.S_ISDIR(info.st_mode) or info.st_uid != os.getuid():
        raise SetupError('Runtime directory must be a directory owned by this user.')
    if info.st_mode & 0o077:
        raise SetupError('Runtime directory is not private. Run chmod 700 on it, then retry.')


def read_private(path, limit=65536):
    if path.is_symlink():
        raise SetupError('Refusing a symbolic-link runtime file.')
    try:
        info = path.stat()
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or info.st_mode & 0o077:
            raise SetupError('Runtime files must be owner-private regular files (chmod 600).')
        with path.open('rb') as stream:
            raw = stream.read(limit + 1)
    except OSError as exc:
        raise SetupError('Private setup is missing. Run make setup MODEL=<installed-model-id>.') from exc
    if len(raw) > limit:
        raise SetupError('Runtime file exceeds its size limit.')
    return raw


def write_private(path, value):
    if path.is_symlink():
        raise SetupError('Refusing a symbolic-link runtime file.')
    raw = (json.dumps(value, indent=2) + '\n').encode()
    fd, name = tempfile.mkstemp(prefix='.prepare-', dir=path.parent)
    try:
        os.fchmod(fd, 0o600)
        with os.fdopen(fd, 'wb') as stream:
            stream.write(raw)
            stream.flush()
            os.fsync(stream.fileno())
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def endpoint(value):
    try:
        parts = urlsplit(value)
        port = parts.port
    except ValueError as exc:
        raise SetupError('Model URL is invalid.') from exc
    if (parts.scheme not in ('http', 'https') or parts.hostname not in ('localhost', '127.0.0.1', '::1')
            or parts.username or parts.password or parts.query or parts.fragment or parts.path.rstrip('/') != '/v1'):
        raise SetupError('Use a loopback model URL ending /v1, e.g. http://127.0.0.1:11434/v1.')
    host = '127.0.0.1' if parts.hostname == 'localhost' else parts.hostname
    authority = ('[' + host + ']') if ':' in host else host
    if port is not None:
        authority += ':' + str(port)
    return parts.scheme + '://' + authority + '/v1'


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, *args, **kwargs):
        return None


def request_json(url, payload=None, timeout=15):
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    request = urllib.request.Request(url, data=None if payload is None else json.dumps(payload).encode(),
                                     headers={'Content-Type': 'application/json'})
    try:
        with opener.open(request, timeout=timeout) as response:
            raw = response.read(65537)
        if len(raw) > 65536:
            raise SetupError('Local model response exceeded 64 KiB.')
        return strict_json(raw)
    except (OSError, urllib.error.URLError, Denied) as exc:
        raise SetupError('Local model is unavailable or returned invalid JSON. Start Ollama locally with '
                         'OLLAMA_NO_CLOUD=1 ollama serve; check make doctor. No fixture was substituted.') from exc


def model_catalog(base):
    listing = request_json(base + '/models')
    try:
        ids = [item['id'] for item in listing['data']]
    except (KeyError, TypeError) as exc:
        raise SetupError('Local /v1/models response has no valid model catalogue.') from exc
    if (not ids or len(ids) > 128 or
            any(type(item) is not str or not re.fullmatch(r'[A-Za-z0-9_./:-]{1,200}', item) for item in ids)):
        raise SetupError('No usable local model is installed. Run ollama pull qwen2.5:1.5b, then make setup.')
    return sorted(set(ids))


def select_model(ids, requested=None):
    if requested:
        if requested not in ids:
            raise SetupError('Selected model is not installed. Use an exact ID from make doctor or ollama list.')
        selected = requested
    elif len(ids) == 1:
        selected = ids[0]
    else:
        raise SetupError('Several models are installed. Run make setup MODEL=<exact-id>; see make doctor.')
    if 'cloud' in selected.casefold():
        raise SetupError('Cloud model aliases are refused. Pull a local-weight model such as qwen2.5:1.5b.')
    return selected


def verify_ollama_local(base, selected):
    """Ollama-native provenance checks, beyond merely trusting a loopback endpoint."""
    origin = base[:-3]
    version = request_json(origin + '/api/version')
    catalogue = request_json(origin + '/api/tags')
    try:
        matches = [item for item in catalogue['models'] if item.get('name') == selected or item.get('model') == selected]
        item = matches[0]
        if len(matches) != 1 or item.get('remote_host') or item.get('remote_model'):
            raise ValueError('cloud relay')
        digest = item['digest']
        size = item['size']
        if not re.fullmatch(r'(?:sha256:)?[0-9a-f]{64}', digest) or type(size) is not int or size <= 0:
            raise ValueError('weights not local')
        if type(version['version']) is not str:
            raise ValueError('version')
    except (KeyError, IndexError, TypeError, ValueError, AttributeError) as exc:
        raise SetupError('Ollama catalogue does not establish downloaded local weights for this model. '
                         'Cloud relays and unidentifiable weights are refused.') from exc
    return {'engine': 'Ollama', 'engine_version': version['version'], 'model': selected,
            'model_digest': digest, 'model_bytes': size, 'endpoint': base, 'mode': 'live-local'}


def preflight(base, selected, timeout=90):
    record = verify_ollama_local(base, selected)
    benign_text = 'Explain what an AI policy gateway does.'
    sample = policy((ROOT / 'policies/demo.json').read_bytes())
    output_bound = sample['max_output_tokens']
    payload = {'model': selected, 'stream': False, 'temperature': 0, 'max_tokens': output_bound,
               'response_format': SEMANTIC_RESPONSE_FORMAT,
               'messages': classifier_messages([benign_text], {'source': 'user', 'text': benign_text})}
    response = request_json(base + '/chat/completions', payload, timeout)
    try:
        content = response['choices'][0]['message']['content']
        if type(content) is not str or len(content.encode()) > 4096:
            raise ValueError('content')
        verdict = strict_json(content)
        if type(verdict) is not dict or set(verdict) != {'risk', 'verdict'} or type(verdict['risk']) is not int:
            raise ValueError('verdict')
        if not 0 <= verdict['risk'] <= 100 or verdict['verdict'] not in ('allow', 'block', 'review'):
            raise ValueError('verdict')
    except (KeyError, IndexError, TypeError, ValueError, Denied) as exc:
        raise SetupError('Model returned an incompatible semantic verdict. Try an instruction model; '
                         'the gateway requires bounded {risk, verdict} JSON. No fixture was substituted.') from exc
    if verdict['verdict'] != 'allow' or verdict['risk'] >= min(sample['semantic_review_at'], sample['semantic_threshold']):
        raise SetupError('The classifier withheld a fixed harmless readiness probe. '
                         'Choose a capable instruction model such as qwen2.5:1.5b-instruct; controls were not relaxed.')
    record['semantic_prompt_sha256'] = hashlib.sha256(SEMANTIC_SYSTEM_PROMPT.encode()).hexdigest()
    record['semantic_response_format_sha256'] = hashlib.sha256(json.dumps(SEMANTIC_RESPONSE_FORMAT, sort_keys=True, separators=(',', ':')).encode()).hexdigest()
    record['preflight'] = 'Actual shared classifier wire allowed one harmless readiness probe below default review/block thresholds; not a quality benchmark.'
    record['preflight_verdict'] = verdict
    record['preflight_output_bound'] = output_bound
    return record


def build_worker(cache=False):
    if not shutil.which('lake'):
        raise SetupError('Lean is missing. Install elan from https://lean-lang.org/install/ and reopen your terminal; '
                         'the checkout pins Lean 4.28.0. Then repeat make setup.')
    try:
        # A prepared checkout should start offline; cache fetching is first-setup work.
        if cache and not (ROOT / '.lake/packages/mathlib/.lake/build/lib/lean/Mathlib').is_dir():
            subprocess.run(['lake', 'exe', 'cache', 'get'], cwd=ROOT, check=True)
        subprocess.run(['lake', 'build', 'mathguard-worker'], cwd=ROOT, check=True)
    except subprocess.CalledProcessError as exc:
        raise SetupError('Pinned Lean/Mathlib build failed. First setup needs internet and disk space. '
                         'See docs/17-JUDGE-QUICKSTART.md; no Python kernel fallback is used.') from exc


def credentials(directory):
    try:
        tokens = strict_json(read_private(directory / 'credentials.json'))
        if type(tokens) is not dict or set(tokens) != {'operator', 'agent', 'owner'}:
            raise ValueError('roles')
        if any(type(t) is not str or not re.fullmatch(r'[A-Za-z0-9_-]{32,128}', t) for t in tokens.values()):
            raise ValueError('token')
        if len(set(tokens.values())) != 3:
            raise ValueError('distinct')
    except (Denied, ValueError) as exc:
        raise SetupError('Private credentials are invalid. Preserve state; do not delete the runtime directory. '
                         'Restore credentials from a private backup or choose a separate runtime directory.') from exc
    return tokens


def setup(directory, base, requested):
    private_dir(directory)
    selected = select_model(model_catalog(base), requested)
    print('Checking downloaded weights and real local semantic inference…', flush=True)
    record = preflight(base, selected)
    pp = directory / 'policy.json'
    if pp.exists() or pp.is_symlink():
        active = policy(read_private(pp))
        if active['semantic_model'] != selected or selected not in active['allowed_models']:
            active.update(epoch=active['epoch'] + 1, allowed_models=[selected], semantic_model=selected)
    else:
        active = policy((ROOT / 'policies/demo.json').read_bytes())
        active.update(allowed_models=[selected], semantic_model=selected)
    policy(json.dumps(active))
    fp = directory / 'signatures.json'
    if fp.exists() or fp.is_symlink():
        feed(read_private(fp))
    else:
        write_private(fp, feed((ROOT / 'feeds/demo-signatures.json').read_bytes()))
    cp = directory / 'credentials.json'
    if cp.exists() or cp.is_symlink():
        credentials(directory)
    else:
        write_private(cp, {role: secrets.token_urlsafe(32) for role in ('operator', 'agent', 'owner')})
    write_private(pp, active)
    write_private(directory / 'model.json', record)
    build_worker(cache=True)
    print('Setup ready. Run make run, then make credentials in a second terminal.')
    print('Policy for live edits: ' + str(pp))
    print('Private state and credentials: ' + str(directory))
    print('Existing state is preserved. Preflight is connectivity evidence, not detector accuracy.')


def run(directory, port):
    private_dir(directory)
    tokens = credentials(directory)
    record = strict_json(read_private(directory / 'model.json'))
    base = endpoint(os.environ.get('MATHGUARD_MODEL_URL', record['endpoint']))
    selected = select_model(model_catalog(base), record['model'])
    print('Checking local model readiness…', flush=True)
    preflight(base, selected)
    build_worker()
    environ = dict(os.environ)
    environ['MATHGUARD_MODEL_URL'] = base
    for role, token in tokens.items():
        environ['MATHGUARD_' + role.upper() + '_TOKEN'] = token
    environ.pop('MATHGUARD_MODEL_KEY', None)
    args = [sys.executable, '-m', 'gateway.server', '--port', str(port), '--policy', str(directory / 'policy.json'),
            '--feed', str(directory / 'signatures.json'), '--state', str(directory / 'state.sqlite3')]
    print('Dashboard: http://127.0.0.1:' + str(port), flush=True)
    print('Retrieve the three roles explicitly with make credentials. Do not record them.', flush=True)
    print('Live policy: ' + str(directory / 'policy.json'), flush=True)
    os.chdir(ROOT)
    os.execve(sys.executable, args, environ)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('command', choices=['setup', 'run', 'credentials', 'doctor'])
    parser.add_argument('--model', default=os.environ.get('MATHGUARD_MODEL') or os.environ.get('MODEL') or None)
    parser.add_argument('--runtime-dir', type=Path, default=runtime_dir())
    parser.add_argument('--port', type=int, default=8787)
    args = parser.parse_args()
    try:
        if sys.version_info < (3, 10):
            raise SetupError('Python 3.10 or newer is required.')
        if os.environ.get('MATHGUARD_MODEL_KEY'):
            raise SetupError('Remove MATHGUARD_MODEL_KEY. The judge launcher uses free local Ollama weights without API keys.')
        if not 1024 <= args.port <= 65535:
            raise SetupError('Dashboard port must be between 1024 and 65535.')
        base = endpoint(os.environ.get('MATHGUARD_MODEL_URL', 'http://127.0.0.1:11434/v1'))
        if args.command == 'credentials':
            private_dir(args.runtime_dir)
            for role, token in credentials(args.runtime_dir).items():
                print(role.upper() + ' token: ' + token)
        elif args.command == 'doctor':
            print('Python: ' + sys.version.split()[0])
            print('Lean launcher: ' + (shutil.which('lake') or 'MISSING — https://lean-lang.org/install/'))
            print('Runtime: ' + str(args.runtime_dir))
            print('Model endpoint: ' + base)
            print('Installed model IDs: ' + ', '.join(model_catalog(base)))
            print('Start the actual Ollama daemon with OLLAMA_NO_CLOUD=1; this launcher cannot change a running daemon.')
        elif args.command == 'setup':
            setup(args.runtime_dir, base, args.model)
        else:
            run(args.runtime_dir, args.port)
    except (SetupError, Denied, KeyError, TypeError) as exc:
        detail = str(exc) if isinstance(exc, SetupError) else 'Private configuration is invalid. Restore a valid file and repeat setup; existing state was not deleted.'
        print('Mathguard setup: ' + detail, file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
