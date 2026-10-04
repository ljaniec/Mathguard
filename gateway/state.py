"""Owned single-node storage for compiled-worker transitions and sanitized audit.

This is a tested IO adapter, not a formally verified database protocol. A durable
intent always precedes a mutating worker call. Unknown tails are never discarded.
Local filesystem ownership is the trust boundary; hashes detect inconsistency,
not a malicious administrator who can replace the entire database.
"""
from __future__ import annotations

import fcntl
import hashlib
import json
import os
from pathlib import Path
import sqlite3
import stat
import time

from .control import Denied, strict_json

MAX_COMMANDS = 20000
MAX_AUDIT_EVENTS = 100000
MAX_DATABASE_BYTES = 128 * 1024 * 1024
MUTATIONS = frozenset({'configure', 'control_configure', 'reserve', 'settle', 'charge', 'execute'})


def encode(value):
    return json.dumps(value, sort_keys=True, separators=(',', ':'), ensure_ascii=True)


def chain(previous, payload, response=''):
    return hashlib.sha256((previous + '\n' + payload + '\n' + response).encode()).hexdigest()


def validate_envelope(value):
    if type(value) is not dict or set(value)!={'request','config'}: raise Denied('STATE_CORRUPT')
    request=value['request']
    fields={'configure':{'op','epoch','limit','maxTransfer','approvalThreshold','controls'},
      'control_configure':{'op','controls'},'reserve':{'op','bound'},'charge':{'op','ticket'},
      'settle':{'op','ticket','actual'},'execute':{'op','request','context'}}
    if type(request) is not dict or type(request.get('op')) is not str:
        raise Denied('STATE_CORRUPT')
    if set(request)!=fields.get(request['op']): raise Denied('STATE_CORRUPT')
    config=value['config']
    if config is not None:
        if (type(config) is not dict or set(config)!={'policy','feed'} or
            any(type(x) is not str or len(x.encode())>65536 for x in config.values()) or
            request['op'] not in {'configure','control_configure'}): raise Denied('STATE_CORRUPT')
    return value


def validate_summary(value):
    names={'counters','posture','event_seq','live_calls','semantic_verdicts','observed_usage',
           'quarantined','quarantine_reason'}
    natural=lambda x:type(x) is int and 0<=x<=10**180
    if type(value) is not dict or set(value)!=names: raise Denied('STATE_CORRUPT')
    for name in ['event_seq','live_calls','semantic_verdicts']:
        if not natural(value[name]): raise Denied('STATE_CORRUPT')
    for name in ['counters','posture']:
        if (type(value[name]) is not dict or len(value[name])>32 or
            any(type(k) is not str or len(k)>64 or not natural(v) for k,v in value[name].items())):
            raise Denied('STATE_CORRUPT')
    usage=value['observed_usage']
    if type(usage) is not dict or set(usage)!={'tokens','compute_ms','calls','reported_token_calls'}:
        raise Denied('STATE_CORRUPT')
    if any(not natural(usage[k]) for k in ['tokens','calls','reported_token_calls']):raise Denied('STATE_CORRUPT')
    if type(usage['compute_ms']) not in {int,float} or not 0<=usage['compute_ms']<=10**180:
        raise Denied('STATE_CORRUPT')
    if type(value['quarantined']) is not bool or not (value['quarantine_reason'] is None or
        type(value['quarantine_reason']) is str and len(value['quarantine_reason'])<=64):
        raise Denied('STATE_CORRUPT')
    return value


class StateStore:
    def __init__(self, path, worker_sha256):
        self.path = Path(path).absolute()
        self.db = None
        self.lock_fd = None
        self.healthy = True
        self.error = None
        self.recovered = False
        try:
            parent = self.path.parent.stat()
            if parent.st_uid != os.getuid() or parent.st_mode & 0o022:
                raise Denied('STATE_DIRECTORY_PERMISSIONS')
            self.lock_fd = self._owned_file(Path(str(self.path) + '.lock'))
            try:
                fcntl.flock(self.lock_fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as exc:
                raise Denied('STATE_IN_USE') from exc
            created = not self.path.exists()
            fd = self._owned_file(self.path)
            owned=os.fstat(fd)
            os.close(fd)
            if owned.st_size>MAX_DATABASE_BYTES:raise Denied('STATE_CAPACITY')
            self.file_identity=(owned.st_dev,owned.st_ino)
            self.db = sqlite3.connect(str(self.path), timeout=2, isolation_level=None,
                                      check_same_thread=False)
            self.db.execute('PRAGMA journal_mode=DELETE')
            self.db.execute('PRAGMA synchronous=FULL')
            self.db.execute('PRAGMA busy_timeout=2000')
            self.db.execute('PRAGMA max_page_count=32768')
            if created:
                self.db.executescript('''BEGIN IMMEDIATE;
                    CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
                    CREATE TABLE commands (id INTEGER PRIMARY KEY, envelope TEXT NOT NULL,
                        response TEXT, previous TEXT NOT NULL, hash TEXT);
                    CREATE TABLE audit (id INTEGER PRIMARY KEY, payload TEXT NOT NULL,
                        previous TEXT NOT NULL, hash TEXT NOT NULL);
                    COMMIT;''')
                self.db.execute('INSERT INTO meta VALUES (?,?)', ('schema', 'mathguard-state-1'))
                self.db.execute('INSERT INTO meta VALUES (?,?)', ('worker_sha256', worker_sha256))
            self._validate(worker_sha256)
        except Denied:
            self.close()
            raise
        except (OSError, sqlite3.Error, ValueError, TypeError) as exc:
            self.close()
            raise Denied('STATE_CORRUPT') from exc

    @staticmethod
    def _owned_file(path):
        flags = os.O_RDWR | os.O_CREAT | getattr(os, 'O_NOFOLLOW', 0)
        try:
            fd = os.open(path, flags, 0o600)
            value = os.fstat(fd)
            if not stat.S_ISREG(value.st_mode) or value.st_uid != os.getuid() or value.st_mode & 0o077:
                os.close(fd)
                raise Denied('STATE_FILE_PERMISSIONS')
            return fd
        except OSError as exc:
            raise Denied('STATE_FILE_UNSAFE') from exc

    def _validate(self, worker_sha256):
        if self.db.execute('PRAGMA integrity_check').fetchone() != ('ok',):
            raise Denied('STATE_CORRUPT')
        meta = dict(self.db.execute('SELECT key,value FROM meta'))
        if meta.get('schema') != 'mathguard-state-1':
            raise Denied('STATE_SCHEMA')
        if meta.get('worker_sha256') != worker_sha256:
            raise Denied('STATE_WORKER_CHANGED')
        for table, payload in [('commands', 'envelope'), ('audit', 'payload')]:
            previous = ''
            expected = 1
            count = self.db.execute('SELECT count(*) FROM ' + table).fetchone()[0]
            if count > (MAX_COMMANDS if table == 'commands' else MAX_AUDIT_EVENTS):
                raise Denied('STATE_CAPACITY')
            columns = f'id,{payload},previous,hash' + (',response' if table == 'commands' else '')
            for row in self.db.execute('SELECT ' + columns + ' FROM ' + table + ' ORDER BY id'):
                ident, raw, prior, digest = row[:4]
                response = row[4] if table == 'commands' else ''
                if response is None:
                    raise Denied('STATE_UNCERTAIN')
                if ident != expected or prior != previous or digest != chain(prior, raw, response):
                    raise Denied('STATE_CORRUPT')
                parsed=strict_json(raw)
                if table=='commands': validate_envelope(parsed)
                elif type(parsed) is not dict or parsed.get('audit_id')!=ident:
                    raise Denied('STATE_CORRUPT')
                if response:
                    strict_json(response)
                expected += 1
                previous = digest
        self.command_count = self.db.execute('SELECT count(*) FROM commands').fetchone()[0]
        self.audit_count = self.db.execute('SELECT count(*) FROM audit').fetchone()[0]
        recorded={}
        for (raw,) in self.db.execute('SELECT payload FROM audit'):
            item=strict_json(raw)
            if item.get('stage')=='worker_commit':
                ident=item.get('command_id')
                if type(ident) is not int or not 1<=ident<=self.command_count or ident in recorded:
                    raise Denied('STATE_CORRUPT')
                recorded[ident]=item.get('operation')
        for ident,raw in self.db.execute('SELECT id,envelope FROM commands'):
            if recorded.get(ident)!=strict_json(raw)['request']['op']:raise Denied('STATE_CORRUPT')
        self.recovered = bool(self.command_count)
        if 'summary' in meta: validate_summary(strict_json(meta['summary']))

    def close(self):
        if self.db is not None:
            self.db.close()
            self.db = None
        if self.lock_fd is not None:
            os.close(self.lock_fd)
            self.lock_fd = None

    def fail(self, code):
        self.healthy = False
        self.error = code
        return Denied(code)

    def _check(self, commands=0, audit=0):
        if not self.healthy:
            raise Denied(self.error or 'STATE_UNAVAILABLE')
        try:
            current=self.path.stat()
            if (current.st_dev,current.st_ino)!=self.file_identity or current.st_mode & 0o077:
                raise self.fail('STATE_FILE_CHANGED')
        except OSError as exc:
            raise self.fail('STATE_UNAVAILABLE') from exc
        if (self.command_count + commands > MAX_COMMANDS or
                self.audit_count + audit > MAX_AUDIT_EVENTS or
                current.st_size >= MAX_DATABASE_BYTES):
            raise self.fail('STATE_CAPACITY')

    def _transaction(self, callback):
        try:
            self.db.execute('BEGIN IMMEDIATE')
            result = callback()
            self.db.execute('COMMIT')
            return result
        except Exception as exc:
            try:
                self.db.execute('ROLLBACK')
            except sqlite3.Error:
                pass
            if isinstance(exc, Denied):
                self.fail(exc.code)
                raise
            raise self.fail('STATE_WRITE_FAILED') from exc

    def begin_command(self, request, config=None):
        self._check(commands=1, audit=1)
        envelope = encode({'request': request, 'config': config})
        validate_envelope(strict_json(envelope))
        if len(envelope.encode()) > 262144:
            raise self.fail('STATE_RECORD_LIMIT')
        previous = self.db.execute('SELECT hash FROM commands ORDER BY id DESC LIMIT 1').fetchone()
        if previous and previous[0] is None:
            raise self.fail('STATE_UNCERTAIN')
        ident = self.command_count + 1
        self._transaction(lambda: self.db.execute(
            'INSERT INTO commands VALUES (?,?,NULL,?,NULL)',
            (ident, envelope, previous[0] if previous else '')))
        self.command_count += 1
        return ident

    def finish_command(self, ident, response):
        self._check(audit=1)
        raw_response = encode(response)
        if len(raw_response.encode()) > 262144:
            raise self.fail('STATE_RECORD_LIMIT')
        row = self.db.execute('SELECT envelope,previous,response FROM commands WHERE id=?', (ident,)).fetchone()
        if not row or row[2] is not None:
            raise self.fail('STATE_UNCERTAIN')
        event = {'stage': 'worker_commit', 'route': 'worker',
                 'outcome': 'STATE_RECORDED' if type(response) is dict and 'error' in response else 'STATE_COMMITTED',
                 'operation': strict_json(row[0])['request']['op'], 'command_id': ident,
                 'reason_codes': [], 'timestamp': int(time.time())}
        def finish():
            self.db.execute('UPDATE commands SET response=?,hash=? WHERE id=?',
                            (raw_response, chain(row[1], row[0], raw_response), ident))
            self._insert_event(event)
        self._transaction(finish)
        self.audit_count += 1

    def _insert_event(self, event):
        previous = self.db.execute('SELECT hash FROM audit ORDER BY id DESC LIMIT 1').fetchone()
        ident = self.audit_count + 1
        event = {**event, 'audit_id': ident}
        raw = encode(event)
        if len(raw.encode()) > 16384:
            raise Denied('STATE_RECORD_LIMIT')
        prior = previous[0] if previous else ''
        self.db.execute('INSERT INTO audit VALUES (?,?,?,?)', (ident, raw, prior, chain(prior, raw)))

    def append_event(self, event, summary=None):
        self._check(audit=1)
        def append():
            self._insert_event(event)
            if summary is not None:
                self.db.execute('INSERT OR REPLACE INTO meta VALUES (?,?)', ('summary', encode(summary)))
        self._transaction(append)
        self.audit_count += 1

    def entries(self):
        for envelope, response in self.db.execute('SELECT envelope,response FROM commands ORDER BY id'):
            yield strict_json(envelope), strict_json(response)

    def summary(self):
        row = self.db.execute('SELECT value FROM meta WHERE key=?', ('summary',)).fetchone()
        return validate_summary(strict_json(row[0])) if row else {}

    def events(self, after=None, limit=2000):
        if (after is not None and (type(after) is not int or after < 0)) or type(limit) is not int or not 1 <= limit <= 2000:
            raise Denied('AUDIT_WINDOW_INVALID')
        if after is not None:
            rows = self.db.execute('SELECT payload FROM audit WHERE id>? ORDER BY id LIMIT ?', (after, limit))
            return [strict_json(row[0]) for row in rows]
        rows = self.db.execute('SELECT payload FROM audit ORDER BY id DESC LIMIT ?', (limit,)).fetchall()
        return [strict_json(row[0]) for row in reversed(rows)]

    def status(self):
        return {'mode': 'sqlite', 'healthy': self.healthy, 'error': self.error,
                'commands': self.command_count, 'audit_events': self.audit_count,
                'max_commands': MAX_COMMANDS, 'max_audit_events': MAX_AUDIT_EVENTS,
                'max_database_bytes': MAX_DATABASE_BYTES, 'recovered': self.recovered,
                'session_restore': 'invalidated'}


class JournaledWorker:
    """Replay the same compiled worker, never a Python implementation of its state."""
    def __init__(self, worker, store):
        self.worker = worker
        self.store = store
        self.configuration = None
        self.commits = []
        self.pending_tickets = set()
        deadline=time.monotonic()+30
        try:
            for envelope, expected in store.entries():
                if time.monotonic()>deadline: raise Denied('STATE_REPLAY_TIMEOUT')
                validate_envelope(envelope)
                request = envelope['request']
                if type(request) is not dict or request.get('op') not in MUTATIONS:
                    raise Denied('STATE_CORRUPT')
                try:
                    actual = worker.call(**request)
                except Denied as exc:
                    if exc.code!='WORKER_REQUEST_REJECTED': raise
                    actual={'error':'WORKER_REQUEST_REJECTED'}
                if encode(actual) != encode(expected):
                    raise Denied('STATE_REPLAY_MISMATCH')
                self._observe(request, actual)
                if envelope['config'] is not None and not (type(actual) is dict and 'error' in actual):
                    self.configuration = envelope['config']
        except Exception as exc:
            worker.close()
            store.close()
            if isinstance(exc, Denied):
                raise
            raise Denied('STATE_CORRUPT') from exc

    def _observe(self, request, response):
        if type(response) is dict and 'error' in response: return
        if request['op'] == 'reserve' and 'ticket' in response:
            self.pending_tickets.add(response['ticket'])
        if request['op'] in {'charge', 'settle'}:
            self.pending_tickets.discard(request['ticket'])
        if request['op'] == 'execute' and response.get('outcome') == 'COMMITTED':
            self.commits.append((request, response))

    def call(self, **request):
        config = request.pop('_persist_config', None)
        if request.get('op') not in MUTATIONS:
            return self.worker.call(**request)
        ident = self.store.begin_command(request, config)
        try:
            response = self.worker.call(**request)
        except Denied as exc:
            if exc.code == 'WORKER_REQUEST_REJECTED':
                # A rejected command makes no transition in Worker.dispatch.
                self.store.finish_command(ident, {'error': 'WORKER_REQUEST_REJECTED'})
            else:
                self.store.fail('STATE_UNCERTAIN')
            raise
        self.store.finish_command(ident, response)
        self._observe(request, response)
        if config is not None:
            self.configuration = config
        return response

    @property
    def broken(self): return self.worker.broken or not self.store.healthy

    def close(self):
        self.worker.close()
        self.store.close()

    def __getattr__(self, name): return getattr(self.worker, name)
