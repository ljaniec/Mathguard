"""Serialized control layer using the compiled Lean worker and optional owned storage."""
from __future__ import annotations
from collections import Counter, deque
from copy import deepcopy
from pathlib import Path
import hashlib
import json
import os
import re
import secrets
import selectors
import subprocess
import threading
import time
from .control import (Denied, artifact, catalog_id, control_policy, decimal, detection,
                      digest, feed, integer, keys, policy, signature_candidates, signature_text, strict_json, text)
from .state import JournaledWorker, StateStore
from .semantic import classifier_messages

ROOT = Path(__file__).resolve().parents[1]
ACCOUNTS = ['alice-main','bob-main','merchant']
ASSURANCE = 'model-v1:55;refinement:5;Next:43;Control:53;compiled-gate;runtime-tested'


class GateStopped(Exception):
    def __init__(self,decision,reasons):
        self.response={'outcome':'BLOCKED' if decision['deny'] else 'PENDING_APPROVAL',
          'reason_codes':reasons,'decision':decision}


class Worker:
    def __init__(self, executable=None):
        path = Path(executable or ROOT/'.lake/build/bin/mathguard-worker')
        self.binary_sha256 = hashlib.sha256(path.read_bytes()).hexdigest()
        self.process = subprocess.Popen([str(path)], stdin=subprocess.PIPE,stdout=subprocess.PIPE,
                                        stderr=subprocess.DEVNULL,bufsize=0)
        self.broken = False
        self.lock = threading.RLock()
        self.closed = False
        self.selector = selectors.DefaultSelector()
        self.selector.register(self.process.stdout,selectors.EVENT_READ)
        os.set_blocking(self.process.stdin.fileno(),False)
        self.write_selector = selectors.DefaultSelector()
        self.write_selector.register(self.process.stdin,selectors.EVENT_WRITE)

    def call(self, **request):
        request.pop('_persist_config', None)
        with self.lock:
            return self._call(request)

    def _call(self, request):
        if self.broken: raise Denied('WORKER_UNAVAILABLE')
        try:
            data = json.dumps(request,separators=(',',':')).encode()+b'\n'
            if len(data)>262144: raise ValueError()
            deadline = time.monotonic()+5
            remaining_data=memoryview(data)
            while remaining_data:
                remaining=deadline-time.monotonic()
                if remaining<=0 or not self.write_selector.select(remaining):raise TimeoutError()
                try: count=os.write(self.process.stdin.fileno(),remaining_data[:65536])
                except BlockingIOError:continue
                if not count: raise EOFError()
                remaining_data=remaining_data[count:]
            output = b''
            while not output.endswith(b'\n'):
                remaining = deadline-time.monotonic()
                if remaining <= 0 or not self.selector.select(remaining): raise TimeoutError()
                chunk = os.read(self.process.stdout.fileno(),65536)
                if not chunk: raise EOFError()
                output += chunk
                if len(output) > 262144: raise ValueError()
            response = strict_json(output)
            self.validate(request['op'],response)
        except Exception as exc:
            self.broken = True
            self.close()
            raise Denied('WORKER_UNAVAILABLE') from exc
        if type(response) is dict and 'error' in response:
            raise Denied('WORKER_REQUEST_REJECTED')
        return response

    @staticmethod
    def validate(op,response):
        nat=lambda x: type(x) is int and 0<=x<=10**180
        if type(response) is dict and set(response)=={'error'} and response['error']=='WORKER_REQUEST_REJECTED':
            return
        def snapshot(value):
            names={'revision','balances','debited','journal_length','epoch','limit','spent','reserved','pending'}
            if type(value) is not dict or set(value)!=names: raise ValueError()
            for name in names-{'balances','debited','limit','spent','reserved'}:
                if not nat(value[name]): raise ValueError()
            for name,size in [('balances',3),('debited',3),('limit',4),('spent',4),('reserved',4)]:
                if type(value[name]) is not list or len(value[name])!=size or not all(nat(x) for x in value[name]):
                    raise ValueError()
        if op in {'snapshot','configure','charge','settle'}: snapshot(response)
        elif op=='control_configure':
            if not nat(response): raise ValueError()
        elif op in {'control_hard','control_decide'}:
            if type(response) is not dict or set(response)!={'deny','ask','redact','executes','generation','reasons'}:
                raise ValueError()
            if any(type(response[k]) is not bool for k in ['deny','ask','redact','executes']): raise ValueError()
            if response['executes']!=(not response['deny'] and not response['ask']): raise ValueError()
            if not nat(response['generation']): raise ValueError()
            if (type(response['reasons']) is not list or len(response['reasons'])>128 or
                any(type(x) is not str or len(x)>128 for x in response['reasons'])): raise ValueError()
        elif op=='flow':
            if type(response) is not bool: raise ValueError()
        elif op=='reserve' and type(response) is dict and set(response)=={'ticket','state'}:
            if not nat(response['ticket']): raise ValueError()
            snapshot(response['state'])
        elif op in {'reserve','preview','execute'}:
            if type(response) is not dict or set(response)!={'outcome','reason','state'}: raise ValueError()
            if response['outcome'] not in {'BLOCKED','PENDING_APPROVAL','ALLOWED','COMMITTED','REPLAYED'}: raise ValueError()
            if type(response['reason']) is not str or not re.fullmatch('[A-Z_]{1,64}',response['reason']): raise ValueError()
            snapshot(response['state'])
        else: raise ValueError()

    def close(self):
        if self.closed: return
        self.closed=True
        if self.process.poll() is None:
            self.process.terminate()
            try: self.process.wait(timeout=1)
            except subprocess.TimeoutExpired: self.process.kill(); self.process.wait(timeout=1)
        for stream in (self.process.stdin,self.process.stdout):
            if stream: stream.close()
        self.selector.close()
        self.write_selector.close()


class Engine:
    def __init__(self, provider, credentials, policy_path=None, feed_path=None, worker=None, state_path=None):
        self.lock = threading.RLock()
        self.worker = worker or Worker()
        self.store = None
        if state_path is not None:
            try:
                self.store = StateStore(state_path,self.worker.binary_sha256)
                self.worker = JournaledWorker(self.worker,self.store)
            except Exception:
                self.worker.close()
                if self.store: self.store.close()
                raise
        self.provider = provider
        self.credentials = credentials  # token -> (role, principal); never comes from request JSON
        self.policy_path = Path(policy_path or ROOT/'policies/demo.json')
        self.feed_path = Path(feed_path or ROOT/'feeds/demo-signatures.json')
        self.active = None
        self.feed = None
        self.policy_bytes = None
        self.feed_bytes = None
        self.events = deque(maxlen=2000)
        self.event_seq = 0
        self.counters = Counter()
        self.posture = Counter()
        self.latencies = deque(maxlen=2000)
        self.control_latencies = deque(maxlen=2000)
        self.sessions = {}
        self.approvals = {}
        self.receipts = {}
        self.interaction_approvals = {}
        self.next_approval_nonce = 1
        self.quarantined = False
        self.quarantine_id = None
        self.quarantine_reason = None
        self.instance_id = secrets.token_hex(8)
        self.started_at = int(time.time())
        self.config_errors = []
        self.live_calls = 0
        self.semantic_verdicts = 0
        self.observed_usage = {'tokens':0,'compute_ms':0,'calls':0,'reported_token_calls':0}
        self.current_trace = None
        try:
            if self.store: self._restore()
            self.reload()
        except Exception:
            self.worker.close()
            raise

    def close(self): self.worker.close()

    def _restore(self):
        config=self.worker.configuration
        if config:
            try:
                self.policy_bytes=config['policy'].encode()
                self.feed_bytes=config['feed'].encode()
                self.active=policy(self.policy_bytes)
                self.feed=feed(self.feed_bytes)
            except Exception as exc: raise Denied('STATE_CONFIG_INVALID') from exc
        for request,result in self.worker.commits:
            q=request['request']; principal=request['context']['principal']
            approval=request['context']['approval']
            if approval: self.next_approval_nonce=max(self.next_approval_nonce,approval['nonce']+1)
            rid_bytes=q['id'].to_bytes((q['id'].bit_length()+7)//8,'big')
            if rid_bytes[:1]!=b'\x01': raise Denied('STATE_REPLAY_MISMATCH')
            try: rid=rid_bytes[1:].decode('ascii')
            except UnicodeError as exc: raise Denied('STATE_REPLAY_MISMATCH') from exc
            self.receipts[(q['id'],principal)]={'commit_id':rid,
              'arguments':{'source':ACCOUNTS[q['source']],'destination':ACCOUNTS[q['destination']],
                'amount_minor':str(q['amount']),'currency':'PLN'},
              'committed_revision':str(result['state']['revision']),
              'source_balance_minor':str(result['state']['balances'][q['source']])}
        summary=self.store.summary()
        for name in ['counters','posture']:
            setattr(self,name,Counter(summary.get(name,{})))
        self.event_seq=summary.get('event_seq',0)
        self.live_calls=summary.get('live_calls',0)
        self.semantic_verdicts=summary.get('semantic_verdicts',0)
        self.observed_usage.update(summary.get('observed_usage',{}))
        self.events.extend(self.store.events())
        if summary.get('quarantined') or self.worker.pending_tickets:
            self.quarantine(summary.get('quarantine_reason') or 'RECOVERED_INFLIGHT_CALL')

    def storage_status(self):
        return self.store.status() if self.store else {'mode':'volatile','healthy':True,'error':None,
          'audit_events':len(self.events),'session_restore':'not_available'}

    def _audit(self,event):
        self.events.append(event)
        if self.store:
            summary={'counters':dict(self.counters),'posture':dict(self.posture),'event_seq':self.event_seq,
              'live_calls':self.live_calls,'semantic_verdicts':self.semantic_verdicts,
              'observed_usage':self.observed_usage,'quarantined':self.quarantined,
              'quarantine_reason':self.quarantine_reason}
            self.store.append_event(event,summary)

    def prune(self):
        now=time.monotonic()
        expired={sid for sid,s in self.sessions.items() if now-s['created']>3600}
        for sid in expired: del self.sessions[sid]
        wall=int(time.time())
        for records in [self.approvals,self.interaction_approvals]:
            for ref,record in list(records.items()):
                if (records is self.interaction_approvals and record['expires']<wall) or record.get('session_id') in expired:
                    del records[ref]

    def authenticate(self, token):
        for key,value in self.credentials.items():
            if secrets.compare_digest(key,token): return value
        raise Denied('AUTH_REQUIRED')

    def reload(self):
        if self.store and not self.store.healthy: raise Denied(self.store.error or 'STATE_UNAVAILABLE')
        errors = []
        candidate_policy,candidate_feed=self.active,self.feed
        policy_raw,feed_raw=self.policy_bytes,self.feed_bytes
        for kind,path,parser in [('policy',self.policy_path,policy),('feed',self.feed_path,feed)]:
            try:
                with path.open('rb') as stream: raw = stream.read(65537)
                if len(raw)>65536: raise Denied('CONFIG_TOO_LARGE')
                old_raw = self.policy_bytes if kind=='policy' else self.feed_bytes
                if raw == old_raw: continue
                value = parser(raw)
                if kind=='policy':
                    candidate_policy,policy_raw = value,raw
                else:
                    if self.feed and value['version'] <= self.feed['version']: raise Denied('FEED_VERSION')
                    candidate_feed,feed_raw = value,raw
            except (OSError,Denied) as exc:
                errors.append(kind.upper()+'_RELOAD_REJECTED')
        if candidate_policy and candidate_feed and (policy_raw!=self.policy_bytes or feed_raw!=self.feed_bytes):
            try:
                controls=control_policy(candidate_policy,candidate_feed)
                config={'policy':policy_raw.decode(),'feed':feed_raw.decode()}
                if policy_raw!=self.policy_bytes:
                    self.worker.call(op='configure',epoch=candidate_policy['epoch'],limit=candidate_policy['budget_limit'],
                      maxTransfer=candidate_policy['max_transfer'],
                      approvalThreshold=1 if 'ledger.transfer' in candidate_policy['irreversible_tools'] else candidate_policy['approval_threshold'],
                      controls=controls,_persist_config=config)
                else:
                    self.worker.call(op='control_configure',controls=controls,_persist_config=config)
                self.active,self.feed=candidate_policy,candidate_feed
                self.policy_bytes,self.feed_bytes=policy_raw,feed_raw
            except Denied:
                errors.append('POLICY_RELOAD_REJECTED')
        self.config_errors = errors
        return {'active_epoch':self.active['epoch'] if self.active else None,
                'active_feed':self.feed['version'] if self.feed else None,
                'errors':errors,'last_good_retained':bool(errors and self.active and self.feed)}

    def ready(self):
        if self.store and not self.store.healthy: raise Denied(self.store.error or 'STATE_UNAVAILABLE')
        if not self.active or not self.feed: raise Denied('CONFIG_UNAVAILABLE')
        if self.worker.broken: raise Denied('WORKER_UNAVAILABLE')

    def session(self, session_id, principal):
        if type(session_id) is not str or session_id not in self.sessions: raise Denied('SESSION_INVALID')
        s = self.sessions[session_id]
        if s['principal'] != principal: raise Denied('SESSION_FORBIDDEN')
        if time.monotonic()-s['created'] > 3600: raise Denied('SESSION_EXPIRED')
        return s

    def step(self,s,key):
        if s['steps'] >= self.active['max_session_steps']: raise Denied('STEP_LIMIT')
        s['steps'] += 1
        s['repeats'][key] += 1
        if s['repeats'][key] > self.active['repeat_limit']: raise Denied('LOOP_LIMIT')

    def control(self,s,value='',kind='prompt',target='',approved=False,semantic=None,hard=False,format=None):
        started=time.monotonic()
        facts=detection(value,self.active)
        interaction=dict(principal=s['principal'] if s else 0,authenticated=True,kind=kind,
          target=catalog_id(target),content=facts['content'],piiScore=facts['piiScore'],approved=approved)
        if kind=='artifact': interaction['format']=format
        d=self.worker.call(op='control_hard' if hard else 'control_decide',
          steps=max(0,s['steps']-1) if s else 0,interaction=interaction,
          semantic=semantic or {'status':'risk','score':0})
        self.control_latencies.append((time.monotonic()-started)*1000)
        return d,facts

    def enforce(self,d,value='',facts=None):
        mapping={'noValidPolicy':'CONFIG_UNAVAILABLE','unauthenticated':'AUTH_REQUIRED',
          'stepLimit':'STEP_LIMIT','modelNotAllowed':'MODEL_NOT_ALLOWED','toolNotAllowed':'TOOL_NOT_ALLOWED',
          'irreversibleNeedsApproval':'APPROVAL_REQUIRED','artifactNotPinned':'ARTIFACT_HASH',
          'unsafeArtifactFormat':'UNSAFE_DESERIALIZATION','piiBlocked':'SENSITIVE_DATA',
          'piiRedacted':'PII_REDACTED','semanticBlocked':'SEMANTIC_DENIED',
          'semanticReview':'SEMANTIC_REVIEW','semanticUnavailable':'SEMANTIC_UNAVAILABLE'}
        reasons=[]
        for r in d['reasons']:
            key=r.rsplit('.',1)[-1]
            if key=='signatureMatch':
                matched=[x['reason'] for x in self.feed['signatures']
                  if any(signature_text(x['contains']) in c for c in signature_candidates(value,self.active,facts))]
                reasons.extend('SIGNATURE_'+x for x in matched or ['MATCH'])
            else: reasons.append(mapping.get(key,key))
        if not d['executes']: raise GateStopped(d,reasons)
        return reasons

    def observe(self,s,value,kind='prompt',target='',approved=False):
        d,facts=self.control(s,value,kind,target,approved,hard=True)
        if facts['encoded']: raise Denied('ENCODED_SENSITIVE_DATA')
        self.enforce(d,value,facts)
        clean=facts['clean'] if d['redact'] else value
        kinds=facts['kinds'] if d['redact'] else []
        s['confidentiality'] = max(s['confidentiality'],facts['level'])
        combined = '\n'.join(s['history']+[clean])
        if len(combined.encode()) > self.active['max_input_bytes']: raise Denied('CONTEXT_LIMIT')
        previous=s['history']
        s['history']=previous+[clean]
        try: self.refresh_history(s)
        except Exception:
            s['history']=previous
            raise
        return clean,kinds

    def refresh_history(self,s):
        """Reapply the current policy before serializing memory for any provider.

        Earlier admissions are not authority to release content after a live
        tightening. Preserve each archived string; if a cross-entry redaction
        cannot be attributed safely, withhold the context instead of guessing.
        """
        clean=[]
        for value in s['history']:
            d,facts=self.control(s,value,hard=True)
            if facts['encoded']: raise Denied('ENCODED_SENSITIVE_DATA')
            self.enforce(d,value,facts)
            s['confidentiality']=max(s['confidentiality'],facts['level'])
            clean.append(facts['clean'] if d['redact'] else value)
        combined='\n'.join(clean)
        if len(combined.encode())>self.active['max_input_bytes']:raise Denied('CONTEXT_LIMIT')
        d,facts=self.control(s,combined,hard=True)
        if facts['encoded']:raise Denied('ENCODED_SENSITIVE_DATA')
        self.enforce(d,combined,facts)
        if d['redact'] and facts['clean']!=combined:raise Denied('CONTEXT_REDACTION_UNSAFE')
        s['history']=clean

    def flow(self,s):
        if not self.worker.call(op='flow',confidentiality=s['confidentiality'],trust=1,
             clearance=self.active['model_clearance'],acceptsUntrusted=True):
            raise Denied('FLOW_DENIED')

    def quarantine(self,reason):
        self.quarantined=True
        self.quarantine_id=self.quarantine_id or secrets.token_hex(16)
        self.quarantine_reason=reason

    def model_call(self,s,model,messages,semantic=False):
        self.refresh_history(s)
        if self.quarantined: raise Denied('PROVIDER_QUARANTINED')
        d,_=self.control(s,kind='model',target=model,hard=True)
        self.enforce(d)
        self.flow(s)
        message_bytes=sum(len(m['content'].encode('utf-8')) for m in messages)
        if message_bytes+self.active['max_output_tokens']+2048 > self.active['call_bound'][1]:
            raise Denied('INPUT_BUDGET_ENVELOPE')
        reservation = self.worker.call(op='reserve',bound=self.active['call_bound'])
        if 'ticket' not in reservation: raise Denied('BUDGET_EXHAUSTED')
        ticket = reservation['ticket']
        started = time.monotonic()
        reported = None
        failure = None
        try:
            content,reported = self.provider.complete(model,messages,self.active,semantic=semantic)
            elapsed = (time.monotonic()-started)*1000
            if self.provider.mode=='live': self.live_calls += 1
            if reported is not None and reported > self.active['call_bound'][1]:
                raise Denied('USAGE_BOUND_EXCEEDED')
            if elapsed > self.active['call_bound'][2]:
                raise Denied('COMPUTE_BOUND_EXCEEDED')
            return content
        except Denied as exc:
            failure = exc.code
            # Adapter cancellation cannot prove remote GPU cancellation. Quarantine
            # further dispatch, retain the full charge, and expose the limitation.
            self.quarantine(exc.code)
            raise
        except Exception as exc:
            self.quarantine('PROVIDER_UNAVAILABLE')
            failure='PROVIDER_UNAVAILABLE'
            raise Denied(failure) from exc
        finally:
            self.worker.call(op='charge',ticket=ticket)
            self.observed_usage['calls']+=1
            self.observed_usage['compute_ms']+=round((time.monotonic()-started)*1000,3)
            if type(reported) is int and reported>=0:
                self.observed_usage['tokens']+=reported
                self.observed_usage['reported_token_calls']+=1
            self.event_seq += 1
            self._audit({'event_id':self.event_seq,'trace_id':self.current_trace,
              'stage':'semantic_model' if semantic else 'proposer_model','route':'provider',
              'outcome':'ERROR_CLOSED' if failure else 'CALL_COMPLETED','reason_codes':[failure] if failure else [],
              'charged_bound':list(self.active['call_bound']),'reported_tokens':reported,
              'latency_ms':round((time.monotonic()-started)*1000,3),'policy_epoch':self.active['epoch'],
              'feed_version':self.feed['version'],'mode':self.provider.mode,'timestamp':int(time.time())})

    def semantic(self,s,candidate,kind='prompt',target='',approved=False,gate_value=None):
        self.refresh_history(s)
        fallback=None
        try:
            content = self.model_call(s,self.active['semantic_model'],
              classifier_messages(s['history'],candidate),semantic=True)
        except Denied as exc:
            if exc.code not in {'PROVIDER_TIMEOUT','PROVIDER_UNAVAILABLE','PROVIDER_SCHEMA','PROVIDER_RESPONSE_LIMIT'}: raise
            fallback={'status':'timeout' if exc.code=='PROVIDER_TIMEOUT' else 'malformed'}
        value=None
        try:
            if fallback is None:
                value = strict_json(content)
                keys(value,{'risk','verdict'})
                integer(value['risk'],0,100)
                if value['verdict'] not in ('allow','block','review'): raise Denied('SEMANTIC_SCHEMA')
                self.semantic_verdicts += 1
        except Denied:
            fallback={'status':'malformed'}
            value=None
        score=0 if value is None else max(value['risk'],100 if value['verdict']=='block' else
          min(self.active['semantic_review_at'],self.active['semantic_threshold']) if value['verdict']=='review' else 0)
        sem=fallback or {'status':'risk','score':score}
        gate_value=json.dumps(candidate,ensure_ascii=False) if gate_value is None else gate_value
        d,_=self.control(s,gate_value,kind,target,approved,semantic=sem)
        reasons=self.enforce(d,gate_value)
        return {'risk':None if fallback else score,'decision':d,'alerts':reasons if fallback else []}

    def canonical(self,body,principal):
        keys(body,{'schema_version','request_id','session_id','expected_revision','policy_epoch','tool','arguments','approval_ref'})
        if body['schema_version']!='mathguard-action-1': raise Denied('SCHEMA_INVALID')
        if body['tool']!='ledger.transfer': raise Denied('TOOL_NOT_ALLOWED')
        d,_=self.control(None,kind='tool',target=body['tool'],approved=True,hard=True)
        self.enforce(d)
        s = self.session(body['session_id'],principal)
        rid = text(body['request_id'],64)
        if not re.fullmatch('[A-Za-z0-9_-]{1,64}',rid): raise Denied('SCHEMA_INVALID')
        args = body['arguments']
        keys(args,{'source','destination','amount_minor','currency'})
        if args['currency']!='PLN' or args['source'] not in ACCOUNTS or args['destination'] not in ACCOUNTS:
            raise Denied('SCHEMA_INVALID')
        # Length-tagged bytes, not a collision-prone hash, injectively map request IDs.
        ident = int.from_bytes(b'\x01'+rid.encode('ascii'),'big')
        q = dict(id=ident,source=ACCOUNTS.index(args['source']),destination=ACCOUNTS.index(args['destination']),
          amount=decimal(args['amount_minor']),expectedRevision=decimal(body['expected_revision']),policyEpoch=decimal(body['policy_epoch']))
        ref = body['approval_ref']
        if ref is not None and (type(ref) is not str or ref not in self.approvals): raise Denied('APPROVAL_INVALID')
        approval = deepcopy(self.approvals.get(ref))
        if approval and (approval['boundRequest']!=q or approval['principal']!=principal): raise Denied('APPROVAL_INVALID')
        if approval and approval.get('session_id')!=body['session_id']: raise Denied('APPROVAL_INVALID')
        if approval and (q['id'],principal) not in self.receipts:
            if approval['epoch']!=self.active['epoch'] or approval['feed_version']!=self.feed['version']:
                raise Denied('STALE_APPROVAL')
        kernel_approval={k:approval[k] for k in ['nonce','principal','boundRequest','expires']} if approval else None
        ctx = dict(principal=principal,now=int(time.time()),approval=kernel_approval)
        return s,q,ctx

    def financial(self,body,principal):
        s,q,ctx = self.canonical(body,principal)
        before = self.worker.call(op='snapshot')
        preview = self.worker.call(op='preview',request=q,context=ctx)
        assessment={}
        if preview['outcome']=='BLOCKED':
            if preview['reason']=='APPROVAL_INVALID' and ctx['approval'] and ctx['now']>ctx['approval']['expires']:
                raise Denied('APPROVAL_EXPIRED')
            raise Denied(preview['reason'])
        if preview['outcome']!='REPLAYED':
            if len(self.receipts)>=10000: raise Denied('RECEIPT_CAPACITY')
            self.step(s,'ledger:'+digest(q))
            assessment=self.semantic(s,{'tool':'ledger.transfer','arguments':body['arguments']},kind='tool',target='ledger.transfer',approved=bool(ctx['approval']))
            # Global lock keeps policy/state fixed across the asynchronous provider process.
        ctx['now']=int(time.time())  # Recheck expiry after potentially slow semantic work.
        final = preview if preview['outcome']=='REPLAYED' else self.worker.call(op='execute',request=q,context=ctx)
        outcome = final['outcome']
        if outcome=='BLOCKED':
            if final['reason']=='APPROVAL_INVALID' and ctx['approval'] and ctx['now']>ctx['approval']['expires']:
                raise Denied('APPROVAL_EXPIRED')
            raise Denied(final['reason'])
        if outcome=='COMMITTED':
            self.receipts[(q['id'],principal)] = dict(commit_id=body['request_id'],
              arguments=deepcopy(body['arguments']),committed_revision=str(final['state']['revision']),
              source_balance_minor=str(final['state']['balances'][q['source']]))
            if body['approval_ref']: self.approvals[body['approval_ref']]['used']=True
        receipt = deepcopy(self.receipts.get((q['id'],principal))) if outcome in {'COMMITTED','REPLAYED'} else None
        if receipt: receipt['replayed'] = outcome=='REPLAYED'
        return {'outcome':outcome,**assessment,'reason_codes':[final['reason']]+assessment.get('alerts',[]), 'request_id':body['request_id'],
          'policy_epoch':str(self.active['epoch']), 'ledger_revision_before':str(before['revision']),
          'ledger_revision_after':str(final['state']['revision']), 'receipt':receipt,
          'approval_requirements':['high_value'] if outcome=='PENDING_APPROVAL' else [],
          'output_disposition':'UNCHANGED','assurance_ref':ASSURANCE}

    def intercept(self,body,principal,issue_approval=False):
        keys(body,{'schema_version','session_id','kind','target','content','approval_ref'})
        if body['schema_version']!='mathguard-interaction-1': raise Denied('SCHEMA_INVALID')
        kinds={'prompt':'prompt','agent_message':'prompt','tool_call':'tool',
               'tool_result':'tool','model_output':'prompt'}
        if type(body['kind']) is not str or body['kind'] not in kinds: raise Denied('SCHEMA_INVALID')
        target=text(body['target'],100)
        if kinds[body['kind']]=='prompt' and target: raise Denied('SCHEMA_INVALID')
        value=text(body['content'],self.active['max_input_bytes'])
        s=self.session(body['session_id'],principal)
        # Ledger effects have their own exact-request/nonce/revision protocol.
        if target=='ledger.transfer': raise Denied('USE_LEDGER_ACTION_ROUTE')
        if body['kind']=='tool_call' and not re.fullmatch(r'[A-Za-z0-9_.-]{1,100}',target):
            raise Denied('SCHEMA_INVALID')
        bound=digest({k:v for k,v in body.items() if k!='approval_ref'})
        ref=body['approval_ref']
        record=None
        approved=False
        if ref is not None:
            if type(ref) is not str: raise Denied('APPROVAL_INVALID')
            record=self.interaction_approvals.get(ref)
            if not record or record['bound']!=bound or record['principal']!=principal or record['used']:
                raise Denied('APPROVAL_INVALID')
            if record['epoch']!=self.active['epoch'] or record['feed_version']!=self.feed['version']:
                raise Denied('STALE_APPROVAL')
            if record['expires']<int(time.time()): raise Denied('APPROVAL_EXPIRED')
            approved=True
        if issue_approval:
            if ref is not None or body['kind']!='tool_call' or target not in self.active['irreversible_tools']:
                raise Denied('APPROVAL_NOT_REQUIRED')
            approved=True  # Classify the exact proposal before issuing authority; never dispatch here.
        # Tool results are input data, not a second invocation of an irreversible tool.
        gate_kind='tool' if body['kind']=='tool_call' else 'prompt'
        if body['kind']=='tool_result':
            d,_=self.control(s,kind='tool',target=target,approved=True,hard=True)
            self.enforce(d)
        self.step(s,'interaction:'+bound)
        clean,redacted=self.observe(s,value,gate_kind,target,approved)
        assessment=self.semantic(s,{'kind':body['kind'],'target':target,'text':clean},
          gate_kind,target,approved,gate_value=value)
        self.flow(s)
        if record and record['expires']<int(time.time()): raise Denied('APPROVAL_EXPIRED')
        if issue_approval:
            if len(self.interaction_approvals)>=1000: raise Denied('APPROVAL_CAPACITY')
            ref=secrets.token_urlsafe(24)
            self.interaction_approvals[ref]={'bound':bound,'principal':principal,'epoch':self.active['epoch'],
              'feed_version':self.feed['version'],'session_id':body['session_id'],
              'expires':int(time.time())+300,'used':False}
            return {'approval_ref':ref,'expires':self.interaction_approvals[ref]['expires'],'executed':False}
        # Consume a separate proved budget ticket before authorizing an SDK tool dispatch.
        if body['kind']=='tool_call':
            r=self.worker.call(op='reserve',bound=[0,0,0,1])
            if 'ticket' not in r: raise Denied('BUDGET_EXHAUSTED')
            self.worker.call(op='charge',ticket=r['ticket'])
        if record: record['used']=True
        return {'outcome':'ALLOWED','content':clean,'kind':body['kind'],'target':target,**assessment,
          'reason_codes':assessment['alerts'],
          'input_disposition':'REDACTED_INPUT' if redacted else 'UNCHANGED',
          'dispatch_authorized':body['kind']=='tool_call','assurance_ref':ASSURANCE}

    def route(self,path,body,role,principal):
        if path=='/v1/policy/reload':
            if role!='operator': raise Denied('ROLE_FORBIDDEN')
            keys(body,set())
            return self.reload()
        if path=='/v1/policy/validate':
            if role!='operator': raise Denied('ROLE_FORBIDDEN')
            policy(json.dumps(body))
            return {'valid':True,'activated':False}
        self.ready()
        if path=='/v1/provider/recover':
            if role!='operator': raise Denied('ROLE_FORBIDDEN')
            keys(body,{'quarantine_id','upstream_stopped'})
            if not self.quarantined: raise Denied('PROVIDER_NOT_QUARANTINED')
            if body['upstream_stopped'] is not True or body['quarantine_id']!=self.quarantine_id:
                raise Denied('RECOVERY_CONFIRMATION_REQUIRED')
            if self.store:
                for ticket in sorted(self.worker.pending_tickets):
                    self.worker.call(op='charge',ticket=ticket)
            self.quarantined=False
            self.quarantine_id=None
            self.quarantine_reason=None
            return {'recovered':True,'state_preserved':True,'resource_charges_preserved':True}
        if path=='/v1/sessions':
            if role not in {'agent','owner'}: raise Denied('ROLE_FORBIDDEN')
            keys(body,set())
            if len(self.sessions)>=100: raise Denied('SESSION_CAPACITY')
            sid=secrets.token_urlsafe(18)
            self.sessions[sid]={'principal':principal,'created':time.monotonic(),'steps':0,
                'repeats':Counter(),'confidentiality':0,'history':[]}
            return {'session_id':sid}
        if path=='/v1/actions':
            if role not in {'agent','owner'}: raise Denied('ROLE_FORBIDDEN')
            return self.financial(body,principal)
        if path in {'/v1/interactions','/v1/interactions/approve'}:
            if role not in {'agent','owner'}: raise Denied('ROLE_FORBIDDEN')
            if path.endswith('/approve') and role!='owner': raise Denied('ROLE_FORBIDDEN')
            return self.intercept(body,principal,issue_approval=path.endswith('/approve'))
        if path=='/v1/approvals':
            if role!='owner': raise Denied('ROLE_FORBIDDEN')
            s,q,ctx=self.canonical(body,principal)
            if body['approval_ref'] is not None: raise Denied('APPROVAL_INVALID')
            preview=self.worker.call(op='preview',request=q,context=ctx)
            if preview['outcome']!='PENDING_APPROVAL': raise Denied('APPROVAL_NOT_REQUIRED')
            if len(self.approvals)>=1000:
                self.approvals={ref:a for ref,a in self.approvals.items() if a['expires']>=int(time.time())}
            if len(self.approvals)>=1000: raise Denied('APPROVAL_CAPACITY')
            ref=secrets.token_urlsafe(24)
            self.approvals[ref]={'nonce':self.next_approval_nonce,'principal':principal,
                'boundRequest':q,'expires':int(time.time())+300,'session_id':body['session_id'],
                'epoch':self.active['epoch'],'feed_version':self.feed['version'],'used':False}
            self.next_approval_nonce+=1
            return {'approval_ref':ref,'expires':self.approvals[ref]['expires'],'executed':False}
        if path=='/v1/models/chat':
            if role not in {'agent','owner'}: raise Denied('ROLE_FORBIDDEN')
            keys(body,{'session_id','model','prompt','source'})
            if body['source'] not in ('user','tool','document'): raise Denied('SCHEMA_INVALID')
            s=self.session(body['session_id'],principal)
            self.step(s,'chat:'+digest(body['prompt']))
            clean,input_kinds=self.observe(s,body['prompt'],kind='model',target=body['model'])
            assessment=self.semantic(s,{'source':body['source'],'text':clean},kind='model',target=body['model'],gate_value=body['prompt'])
            answer=self.model_call(s,body['model'],[{'role':'user','content':clean}])
            output,kinds=self.observe(s,answer)
            output_assessment=self.semantic(s,{'source':'model_output','text':output},gate_value=answer)
            alerts=list(dict.fromkeys(assessment['alerts']+output_assessment['alerts']))
            return {'outcome':'ALLOWED','output':output,**assessment,'output_assessment':output_assessment,
              'alerts':alerts,'reason_codes':alerts,
              'output_disposition':'REDACTED_OUTPUT' if kinds else 'UNCHANGED',
              'input_disposition':'REDACTED_INPUT' if input_kinds else 'UNCHANGED'}
        if path=='/v1/artifacts/check':
            if role!='operator': raise Denied('ROLE_FORBIDDEN')
            keys(body,{'repository','sha256','format','trust_remote_code','content_base64'})
            d,_=self.control(None,kind='artifact',target=text(body['sha256'],64),format=text(body['format'],32),hard=True)
            self.enforce(d)
            return {**artifact(body,self.active),'decision':d}
        raise Denied('ROUTE_NOT_ALLOWED')

    def handle(self,path,body,token):
        start=time.monotonic()
        trace=secrets.token_hex(8)
        if not self.lock.acquire(timeout=5):
            return {'outcome':'ERROR_CLOSED','reason_codes':['GATEWAY_BUSY'],'trace_id':trace}
        try:
            self.current_trace=trace
            principal=None
            try:
                role,principal=self.authenticate(token)
                self.prune()
                self.reload()  # Edits take effect at the next request; immutable snapshot during one request.
                response=self.route(path,body,role,principal)
            except GateStopped as exc:
                response=exc.response
            except Denied as exc:
                response={'outcome':'ERROR_CLOSED' if any(s in exc.code for s in ['UNAVAILABLE','TIMEOUT','QUARANTINED']) else 'BLOCKED',
                          'reason_codes':[exc.code]}
            except Exception:
                response={'outcome':'ERROR_CLOSED','reason_codes':['INTERNAL_ERROR']}
            elapsed=(time.monotonic()-start)*1000
            response['trace_id']=trace
            self.event_seq+=1
            outcome=response.get('outcome','CONTROL')
            self.counters[outcome]+=1
            if response.get('input_disposition')=='REDACTED_INPUT' or response.get('output_disposition')=='REDACTED_OUTPUT':
                self.posture['redacted_interactions']+=1
            if response.get('alerts'): self.posture['semantic_fallback_alerts']+=1
            if outcome=='PENDING_APPROVAL': self.posture['awaiting_review']+=1
            self.latencies.append(elapsed)
            event={'event_id':self.event_seq,'trace_id':trace,'principal':principal,
              'route':path if path in KNOWN_ROUTES else 'unknown', 'outcome':outcome,
              'reason_codes':response.get('reason_codes',[]), 'latency_ms':round(elapsed,3),
              'decision':response.get('decision'),
              'policy_epoch':self.active['epoch'] if self.active else None,
              'feed_version':self.feed['version'] if self.feed else None,'mode':self.provider.mode,
              'timestamp':int(time.time()),'assurance_ref':ASSURANCE}
            try: self._audit(event)
            except Denied as exc:
                response={'outcome':'ERROR_CLOSED','reason_codes':[exc.code], 'trace_id':trace}
            return response
        finally:
            self.current_trace=None
            self.lock.release()

    def ingress_rejection(self,code):
        if not self.lock.acquire(timeout=5):
            return {'outcome':'ERROR_CLOSED','reason_codes':['GATEWAY_BUSY'],'trace_id':secrets.token_hex(8)}
        try:
            trace=secrets.token_hex(8)
            self.event_seq+=1
            self.counters['BLOCKED']+=1
            try: self._audit({'event_id':self.event_seq,'trace_id':trace,'stage':'ingress',
              'route':'ingress','outcome':'BLOCKED','reason_codes':[code],'latency_ms':None,
              'policy_epoch':self.active['epoch'] if self.active else None,
              'feed_version':self.feed['version'] if self.feed else None,'mode':self.provider.mode,
              'timestamp':int(time.time())})
            except Denied as exc: code=exc.code
            return {'outcome':'BLOCKED','reason_codes':[code],'trace_id':trace}
        finally: self.lock.release()

    def read(self,path,token,*,after=None,limit=2000):
        if not self.lock.acquire(timeout=5): raise Denied('GATEWAY_BUSY')
        try:
            role,principal=self.authenticate(token)
            if path=='/v1/ledger/summary':
                if role not in {'agent','owner'}: raise Denied('ROLE_FORBIDDEN')
                self.ready()
                state=self.worker.call(op='snapshot')
                return {'revision':str(state['revision']),'policy_epoch':str(state['epoch']),
                  'account':ACCOUNTS[principal-1],'balance_minor':str(state['balances'][principal-1])}
            if path=='/v1/assurance':
                return {'model_targets':55,'additional_equality_targets':5,'next_axiom_records':43,
                  'control_axiom_records':53,'generic_gate':'compiled Mathguard.Control.storeDecision / hardDecision',
                  'runtime':'tested serialized worker with owned durable journal' if self.store else 'tested volatile serialized worker',
                  'storage':self.storage_status(),
                  'worker_sha256':self.worker.binary_sha256,'semantic_mode':self.provider.mode,
                  'instance_id':self.instance_id,
                  'policy_sha256':hashlib.sha256(self.policy_bytes).hexdigest() if self.policy_bytes else None,
                  'feed_sha256':hashlib.sha256(self.feed_bytes).hexdigest() if self.feed_bytes else None,
                  'policy_epoch':self.active['epoch'] if self.active else None,
                  'feed_version':self.feed['version'] if self.feed else None,
                  'semantic_model':self.active['semantic_model'] if self.active else None,
                  'config_errors':list(self.config_errors),
                  'validated_semantic_verdicts':self.semantic_verdicts,
                  'live_calls_observed':self.live_calls,'quarantined':self.quarantined,
                  'limitations':(['No distributed quotas; sessions and approvals are invalidated on restart',
                    'Unknown durable command tails require verified backup/operator repair; no automatic rollback',
                    'Storage integrity assumes trusted local file ownership; hashes are not an anti-rollback anchor'] if self.store else
                    ['No durable storage or distributed quotas'])+['No complete prompt-injection or artifact-safety guarantee',
                    'Provider bounds, authentication, parsing and runtime composition are not proved',
                    'Timeout kills adapter, not necessarily the upstream GPU job; further calls are quarantined',
                    'SDK authorization does not make arbitrary external callbacks exactly once or crash atomic']}
            if role!='operator': raise Denied('ROLE_FORBIDDEN')
            if path=='/v1/events' or path=='/v1/audit/export':
                if self.store: return self.store.events(after,limit)
                if (after is not None and (type(after) is not int or after<0)) or type(limit) is not int or not 1<=limit<=2000:
                    raise Denied('AUDIT_WINDOW_INVALID')
                return ([e for e in self.events if e['event_id']>after][:limit] if after is not None else list(self.events)[-limit:])
            if path=='/v1/report':
                decision_count=sum(v for k,v in self.counters.items() if k!='CONTROL')
                reasons=Counter(code for event in self.events for code in event['reason_codes'])
                return {'generated_at':int(time.time()),'deployment':'single-node, owned SQLite journal' if self.store else 'single-process, volatile',
                  'storage':self.storage_status(),'observed_usage':dict(self.observed_usage),
                  'audit_export':{'scope':'newest bounded window by default; start full pagination with after=0' if self.store else 'retained volatile window',
                    'max_events_per_page':2000,'id_field':'audit_id' if self.store else 'event_id'},
                  'decisions':decision_count,'outcomes':dict(self.counters),'top_reasons':reasons.most_common(8),
                  'security_posture':dict(self.posture),
                  'active_policy_epoch':self.active['epoch'] if self.active else None,
                  'config_errors':self.config_errors,'quarantined':self.quarantined,
                  'resource_accounting':'configured upper bounds charged; not measured financial bills',
                  'semantic_mode':self.provider.mode,'live_calls_observed':self.live_calls,
                  'retained_events':len(self.events),'events_dropped':0 if self.store else max(0,self.event_seq-len(self.events)),
                  'assurance':ASSURANCE,'ready_for_submission':False,
                  'remaining_evidence':['live model quality evaluation','submission deck and operator rehearsal']}
            if path=='/v1/status':
                lat=sorted(self.latencies)
                quantile=lambda q: lat[max(0,min(len(lat)-1,__import__('math').ceil(len(lat)*q)-1))] if lat else None
                controls=sorted(self.control_latencies)
                cq=lambda q: controls[max(0,min(len(controls)-1,__import__('math').ceil(len(controls)*q)-1))] if controls else None
                return {'ready':bool(self.active and self.feed and not self.worker.broken),
                  'storage':self.storage_status(),'observed_usage':dict(self.observed_usage),
                  'audit':{'storage':'sqlite' if self.store else 'volatile','retained_events':len(self.events),
                    'events_dropped':0 if self.store else max(0,self.event_seq-len(self.events)),
                    'total_events':self.store.audit_count if self.store else self.event_seq,
                    'export_max_events':2000},
                  'state':self.worker.call(op='snapshot') if not self.worker.broken else None,
                  'instance_id':self.instance_id,'started_at':self.started_at,
                  'quarantine_id':self.quarantine_id,'quarantine_reason':self.quarantine_reason,
                  'policy':self.active,'feed_version':self.feed['version'] if self.feed else None,
                  'config_errors':self.config_errors,'quarantined':self.quarantined,'counters':dict(self.counters),
                  'security_posture':dict(self.posture),
                  'latency_ms':{'p50':quantile(.5),'p95':quantile(.95),'samples':len(lat)},
                  'control_latency_ms':{'p50':cq(.5),'p95':cq(.95),'samples':len(controls),
                    'scope':'detector facts + compiled gate round trip; provider excluded'},
                  'mode':self.provider.mode,'live_calls':self.live_calls,'retained_events':len(self.events)}
            raise Denied('ROUTE_NOT_ALLOWED')
        finally: self.lock.release()

KNOWN_ROUTES={'/v1/sessions','/v1/actions','/v1/approvals','/v1/models/chat','/v1/interactions','/v1/interactions/approve',
 '/v1/policy/reload','/v1/policy/validate','/v1/artifacts/check','/v1/provider/recover'}
