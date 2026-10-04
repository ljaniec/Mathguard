"""State/approval/crash-boundary tests against the actual compiled Lean worker.

Fixtures exercise composition and recovery, not local-model threat accuracy.
"""
from concurrent.futures import ThreadPoolExecutor
import base64
from copy import deepcopy
import json
from pathlib import Path
import sqlite3
import tempfile
import threading
import time
import unittest
from unittest.mock import patch

from gateway.control import Denied
from gateway.engine import Engine, ROOT, Worker
from gateway.state import StateStore, encode
from test_gateway import FixtureProvider


class RuntimeHardeningTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.pp=Path(self.temp.name)/'policy.json'
        self.fp=Path(self.temp.name)/'feed.json'
        self.sp=Path(self.temp.name)/'state.sqlite3'
        self.pp.write_bytes((ROOT/'policies/demo.json').read_bytes())
        self.fp.write_bytes((ROOT/'feeds/demo-signatures.json').read_bytes())
        self.credentials={'agent':('agent',1),'owner':('owner',1),'bob':('agent',2),'operator':('operator',0)}
        self.provider=FixtureProvider()
        self.engine=None
        self.addCleanup(self.close)
        self.start()

    def close(self):
        if self.engine:
            self.engine.close()
            self.engine=None

    def start(self):
        self.engine=Engine(self.provider,self.credentials,self.pp,self.fp,state_path=self.sp)
        self.sid=self.engine.handle('/v1/sessions',{},'agent')['session_id']

    def restart(self):
        self.close()
        self.start()

    def request(self,amount='2500',rid='restart-request',revision='0',epoch='7'):
        return {'schema_version':'mathguard-action-1','request_id':rid,'session_id':self.sid,
          'expected_revision':revision,'policy_epoch':epoch,'tool':'ledger.transfer',
          'arguments':{'source':'alice-main','destination':'bob-main','amount_minor':amount,'currency':'PLN'},
          'approval_ref':None}

    def action(self,body): return self.engine.handle('/v1/actions',body,'agent')
    def state(self): return self.engine.worker.call(op='snapshot')
    def update(self,**changes):
        value=json.loads(self.pp.read_text());value.update(changes);self.pp.write_text(json.dumps(value))
        return self.engine.handle('/v1/policy/reload',{},'operator')
    def denied(self,value,code):
        self.assertIn(value['outcome'],{'BLOCKED','ERROR_CLOSED'})
        self.assertIn(code,value['reason_codes'])

    def test_restart_restores_ledger_quota_receipt_and_exact_retry(self):
        request=self.request()
        first=self.action(request)
        self.assertEqual(first['outcome'],'COMMITTED')
        before=self.state(); calls=len(self.provider.calls); old_sid=self.sid
        self.restart()
        self.assertEqual(self.state(),before)
        self.assertNotIn(old_sid,self.engine.sessions)
        request['session_id']=self.sid
        replay=self.action(request)
        self.assertEqual(replay['outcome'],'REPLAYED')
        self.assertEqual(replay['receipt']['commit_id'],first['receipt']['commit_id'])
        self.assertEqual(replay['receipt']['committed_revision'],first['receipt']['committed_revision'])
        self.assertEqual(self.state(),before)
        self.assertEqual(len(self.provider.calls),calls)
        self.assertTrue(self.engine.storage_status()['recovered'])

    def test_restart_restores_last_good_after_invalid_files(self):
        self.action(self.request())
        self.update(epoch=8)
        before=self.state()
        self.pp.write_text('{invalid')
        self.fp.write_text('{}')
        self.restart()
        self.assertEqual(self.engine.active['epoch'],8)
        self.assertEqual(self.state(),before)
        self.assertCountEqual(self.engine.config_errors,['POLICY_RELOAD_REJECTED','FEED_RELOAD_REJECTED'])

    def test_rejected_reload_replays_without_activating_rejected_candidate(self):
        self.action(self.request())
        before=self.state()
        result=self.update(epoch=8,budget_limit=[0,0,0,0])
        self.assertTrue(result['last_good_retained'])
        self.restart()
        self.assertEqual(self.state(),before)
        self.assertEqual(self.engine.active['epoch'],7)

    def test_feed_only_reload_survives_restart(self):
        value=json.loads(self.fp.read_text());value['version']=2
        self.fp.write_text(json.dumps(value))
        self.engine.handle('/v1/policy/reload',{},'operator')
        self.restart()
        self.assertEqual(self.engine.feed['version'],2)

    def test_approval_nonce_floor_restored_and_outstanding_refs_invalidated(self):
        first=self.request(amount='10000')
        first['approval_ref']=self.engine.handle('/v1/approvals',first,'owner')['approval_ref']
        self.assertEqual(self.engine.approvals[first['approval_ref']]['nonce'],1)
        self.assertEqual(self.action(first)['outcome'],'COMMITTED')
        self.restart()
        self.assertEqual(self.engine.approvals,{})
        self.assertEqual(self.engine.interaction_approvals,{})
        second=self.request(amount='10000',rid='second-approved',revision='1')
        second['approval_ref']=self.engine.handle('/v1/approvals',second,'owner')['approval_ref']
        self.assertGreater(self.engine.approvals[second['approval_ref']]['nonce'],1)
        self.assertEqual(self.action(second)['outcome'],'COMMITTED')
        self.assertEqual(self.state()['revision'],2)

    def test_financial_approval_binds_session_and_feed(self):
        body=self.request(amount='10000')
        body['approval_ref']=self.engine.handle('/v1/approvals',body,'owner')['approval_ref']
        other=self.engine.handle('/v1/sessions',{},'agent')['session_id']
        self.denied(self.action({**body,'session_id':other}),'APPROVAL_INVALID')
        value=json.loads(self.fp.read_text());value['version']=2;self.fp.write_text(json.dumps(value))
        self.denied(self.action(body),'STALE_APPROVAL')
        self.assertEqual(self.state()['revision'],0)

    def test_duplicate_concurrent_commit_is_durable_once(self):
        body=self.request()
        with ThreadPoolExecutor(max_workers=4) as pool:
            values=list(pool.map(lambda _:self.action(deepcopy(body)),range(4)))
        self.assertEqual(sum(x['outcome']=='COMMITTED' for x in values),1)
        self.assertEqual(sum(x['outcome']=='REPLAYED' for x in values),3)
        self.restart()
        self.assertEqual(self.state()['revision'],1)
        self.assertEqual(self.state()['journal_length'],1)

    def test_second_process_owner_and_permissions_are_rejected(self):
        with self.assertRaises(Denied) as caught:
            Engine(self.provider,self.credentials,self.pp,self.fp,state_path=self.sp)
        self.assertEqual(caught.exception.code,'STATE_IN_USE')
        self.close();self.sp.chmod(0o644)
        with self.assertRaises(Denied) as caught:
            self.start()
        self.assertEqual(caught.exception.code,'STATE_FILE_PERMISSIONS')

    def test_empty_existing_database_does_not_reset_state(self):
        self.close();self.sp.write_bytes(b'')
        with self.assertRaises(Denied) as caught:self.start()
        self.assertEqual(caught.exception.code,'STATE_CORRUPT')

    def test_oversized_existing_database_is_rejected_before_sqlite_scan(self):
        self.close()
        with self.sp.open('r+b') as stream:stream.truncate(128*1024*1024+1)
        with self.assertRaises(Denied) as caught:self.start()
        self.assertEqual(caught.exception.code,'STATE_CAPACITY')

    def test_tampered_result_or_journal_gap_closes_startup(self):
        self.action(self.request())
        self.close()
        with sqlite3.connect(self.sp) as db:
            db.execute("UPDATE commands SET response='{}' WHERE id=1")
        with self.assertRaises(Denied) as caught:self.start()
        self.assertEqual(caught.exception.code,'STATE_CORRUPT')

    def test_worker_binary_binding_closes_startup(self):
        self.close()
        with sqlite3.connect(self.sp) as db:
            db.execute("UPDATE meta SET value='changed' WHERE key='worker_sha256'")
        with self.assertRaises(Denied) as caught:self.start()
        self.assertEqual(caught.exception.code,'STATE_WORKER_CHANGED')

    def test_unknown_worker_intent_is_not_discarded_or_replayed(self):
        before=self.state()
        self.engine.store.begin_command({'op':'reserve','bound':[0,0,0,1]})
        self.close()
        with self.assertRaises(Denied) as caught:self.start()
        self.assertEqual(caught.exception.code,'STATE_UNCERTAIN')
        with sqlite3.connect(self.sp) as db:
            self.assertEqual(db.execute('SELECT count(*) FROM commands WHERE response IS NULL').fetchone()[0],1)
        self.assertEqual(before['spent'],[0,0,0,0])

    def test_ledger_result_and_operation_audit_rollback_together(self):
        original=self.engine.store._insert_event
        def fail_execute(event):
            if event.get('operation')=='execute':raise sqlite3.OperationalError('injected')
            return original(event)
        with patch.object(self.engine.store,'_insert_event',side_effect=fail_execute):
            response=self.action(self.request())
        self.denied(response,'STATE_WRITE_FAILED')
        self.close()
        with sqlite3.connect(self.sp) as db:
            envelope,result=db.execute('SELECT envelope,response FROM commands ORDER BY id DESC LIMIT 1').fetchone()
            self.assertEqual(json.loads(envelope)['request']['op'],'execute')
            self.assertIsNone(result)
            self.assertEqual(db.execute("SELECT count(*) FROM audit WHERE payload LIKE '%\"operation\":\"execute\"%'").fetchone()[0],0)
        with self.assertRaises(Denied) as caught:self.start()
        self.assertEqual(caught.exception.code,'STATE_UNCERTAIN')

    def test_reservation_is_durable_before_upstream_dispatch(self):
        original=self.provider.complete
        def verify(*args,**kwargs):
            with sqlite3.connect(self.sp) as db:
                envelope,result=db.execute('SELECT envelope,response FROM commands ORDER BY id DESC LIMIT 1').fetchone()
                self.assertEqual(json.loads(envelope)['request']['op'],'reserve')
                self.assertIn('ticket',json.loads(result))
            return original(*args,**kwargs)
        self.provider.complete=verify
        body={'schema_version':'mathguard-interaction-1','session_id':self.sid,
              'kind':'agent_message','target':'','content':'Harmless note','approval_ref':None}
        self.assertEqual(self.engine.handle('/v1/interactions',body,'agent')['outcome'],'ALLOWED')

    def test_recovered_pending_reservation_quarantines_and_never_refunds(self):
        reserved=self.engine.worker.call(op='reserve',bound=[0,16384,16000,1])
        self.assertIn('ticket',reserved)
        before=self.state()
        self.restart()
        self.assertTrue(self.engine.quarantined)
        self.assertEqual(self.state(),before)
        body={'session_id':self.sid,'model':'local-model','prompt':'Hello','source':'user'}
        self.denied(self.engine.handle('/v1/models/chat',body,'agent'),'PROVIDER_QUARANTINED')
        result=self.engine.handle('/v1/provider/recover',{'quarantine_id':self.engine.quarantine_id,
               'upstream_stopped':True},'operator')
        self.assertTrue(result['resource_charges_preserved'])
        state=self.state()
        self.assertEqual(state['spent'],[0,16384,16000,1])
        self.assertEqual(state['reserved'],[0,0,0,0]);self.assertEqual(state['pending'],0)
        self.restart()
        self.assertFalse(self.engine.quarantined)
        self.assertEqual(self.state()['spent'],state['spent'])

    def test_rejected_settlement_does_not_forget_pending_reservation(self):
        reserved=self.engine.worker.call(op='reserve',bound=[0,10,0,1])
        with self.assertRaises(Denied) as caught:
            self.engine.worker.call(op='settle',ticket=reserved['ticket'],actual=[0,11,0,1])
        self.assertEqual(caught.exception.code,'WORKER_REQUEST_REJECTED')
        self.assertIn(reserved['ticket'],self.engine.worker.pending_tickets)
        self.restart()
        self.assertTrue(self.engine.quarantined)
        self.assertEqual(self.state()['pending'],1)
        self.assertIn(reserved['ticket'],self.engine.worker.pending_tickets)

    def test_corrupt_typed_summary_closes_startup(self):
        self.close()
        with sqlite3.connect(self.sp) as db:
            db.execute("UPDATE meta SET value='{}' WHERE key='summary'")
        with self.assertRaises(Denied) as caught:self.start()
        self.assertEqual(caught.exception.code,'STATE_CORRUPT')

    def test_removed_journal_tail_is_detected_by_operation_audit(self):
        self.action(self.request())
        self.close()
        with sqlite3.connect(self.sp) as db:
            db.execute('DELETE FROM commands WHERE id=(SELECT max(id) FROM commands)')
        with self.assertRaises(Denied) as caught:self.start()
        self.assertEqual(caught.exception.code,'STATE_CORRUPT')

    def test_persistent_audit_is_metadata_only_and_paginated(self):
        secret='alice@example.com MG_SECRET_SYNTHETIC_12345'
        body={'schema_version':'mathguard-interaction-1','session_id':self.sid,
              'kind':'agent_message','target':'','content':secret,'approval_ref':None}
        self.assertEqual(self.engine.handle('/v1/interactions',body,'agent')['outcome'],'ALLOWED')
        first=self.engine.read('/v1/audit/export','operator',limit=2)
        self.assertEqual(len(first),2)
        follow=self.engine.read('/v1/audit/export','operator',after=first[-1]['audit_id'],limit=2)
        self.assertEqual(follow,[])
        earliest=self.engine.read('/v1/audit/export','operator',after=0,limit=2)
        self.assertEqual([x['audit_id'] for x in earliest],[1,2])
        subsequent=self.engine.read('/v1/audit/export','operator',after=2,limit=2)
        self.assertEqual([x['audit_id'] for x in subsequent],[3,4])
        all_events=self.engine.read('/v1/audit/export','operator',after=1,limit=2000)
        raw=json.dumps(all_events)
        self.assertNotIn('alice@example.com',raw);self.assertNotIn('MG_SECRET_SYNTHETIC_12345',raw)
        self.close()
        self.assertNotIn(secret.encode(),self.sp.read_bytes())

    def test_bounded_sessions_expire_and_reclaim_related_approvals(self):
        self.engine.sessions[self.sid]['created']=time.monotonic()-3601
        self.engine.approvals['old']={'expires':int(time.time())+300,'session_id':self.sid}
        self.engine.interaction_approvals['old']={'expires':int(time.time())+300,'session_id':self.sid}
        self.engine.handle('/v1/sessions',{},'agent')
        self.assertNotIn(self.sid,self.engine.sessions)
        self.assertNotIn('old',self.engine.approvals)
        self.assertNotIn('old',self.engine.interaction_approvals)

    def test_capacity_failure_precedes_dispatch(self):
        self.engine.store.command_count=20000
        body={'schema_version':'mathguard-interaction-1','session_id':self.sid,
              'kind':'agent_message','target':'','content':'Hello','approval_ref':None}
        self.denied(self.engine.handle('/v1/interactions',body,'agent'),'STATE_CAPACITY')
        self.assertEqual(self.provider.calls,[])

    def test_intent_write_rollback_precedes_worker_and_provider(self):
        before=self.state()
        self.engine.store.db.execute("CREATE TRIGGER reject_intent BEFORE INSERT ON commands BEGIN SELECT RAISE(ABORT,'injected'); END")
        body={'schema_version':'mathguard-interaction-1','session_id':self.sid,
              'kind':'agent_message','target':'','content':'Hello','approval_ref':None}
        self.denied(self.engine.handle('/v1/interactions',body,'agent'),'STATE_WRITE_FAILED')
        self.assertEqual(self.provider.calls,[])
        self.assertEqual(self.engine.worker.worker.call(op='snapshot'),before)
        with sqlite3.connect(self.sp) as db:
            self.assertEqual(db.execute('SELECT count(*) FROM commands WHERE response IS NULL').fetchone()[0],0)

    def test_generic_approval_concurrent_consumption_is_single_use(self):
        body={'schema_version':'mathguard-interaction-1','session_id':self.sid,
              'kind':'tool_call','target':'demo.publish','content':'A public note','approval_ref':None}
        body['approval_ref']=self.engine.handle('/v1/interactions/approve',body,'owner')['approval_ref']
        with ThreadPoolExecutor(max_workers=4) as pool:
            results=list(pool.map(lambda _:self.engine.handle('/v1/interactions',deepcopy(body),'agent'),range(4)))
        self.assertEqual(sum(x['outcome']=='ALLOWED' for x in results),1)
        self.assertEqual(sum('APPROVAL_INVALID' in x['reason_codes'] for x in results),3)

    def test_busy_admission_bounds_reads_ingress_and_actions(self):
        class Busy:
            def acquire(self,*,timeout):
                if timeout!=5:raise AssertionError('unbounded admission')
                return False
            def release(self):raise AssertionError('not acquired')
        with patch.object(self.engine,'lock',Busy()):
            self.denied(self.engine.handle('/v1/sessions',{},'agent'),'GATEWAY_BUSY')
            self.denied(self.engine.ingress_rejection('BODY_LIMIT'),'GATEWAY_BUSY')
            with self.assertRaises(Denied) as caught:self.engine.read('/v1/status','operator')
            self.assertEqual(caught.exception.code,'GATEWAY_BUSY')

    def test_malformed_worker_response_cannot_authorize(self):
        invalid=[{'deny':False,'ask':False,'redact':False,'executes':True,'generation':1,'reasons':'unsafe'},
                 {'deny':True,'ask':False,'redact':False,'executes':True,'generation':1,'reasons':[]},
                 {'ticket':True,'state':self.state()}]
        for value in invalid:
            with self.subTest(value=value),self.assertRaises(ValueError):
                Worker.validate('reserve' if 'ticket' in value else 'control_decide',value)

    def test_semantic_output_veto_withholds_answer_after_proposer(self):
        original=self.provider.complete
        def output_veto(model,messages,policy,semantic=False):
            if semantic and len(self.provider.calls)==2:
                self.provider.verdict='block'
            return original(model,messages,policy,semantic)
        self.provider.complete=output_veto
        result=self.engine.handle('/v1/models/chat',{'session_id':self.sid,'model':'local-model',
               'prompt':'A harmless question','source':'user'},'agent')
        self.denied(result,'SEMANTIC_DENIED')
        self.assertNotIn('output',result)
        self.assertEqual(len(self.provider.calls),3)
        self.assertEqual(self.state()['spent'][3],3)

    def test_live_pii_tightening_rewrites_memory_before_all_provider_stages(self):
        self.update(epoch=8,pii_redact_at=101,pii_block_at=101)
        chat={'session_id':self.sid,'model':'local-model','prompt':'Contact alice@example.com','source':'user'}
        self.assertEqual(self.engine.handle('/v1/models/chat',chat,'agent')['outcome'],'ALLOWED')
        self.assertIn('alice@example.com',json.dumps(self.engine.sessions[self.sid]['history']))
        self.provider.calls.clear()
        self.update(epoch=9,pii_redact_at=60,pii_block_at=100)
        result=self.engine.handle('/v1/models/chat',{**chat,'prompt':'A harmless follow-up'},'agent')
        self.assertEqual(result['outcome'],'ALLOWED')
        self.assertEqual(len(self.provider.calls),3)
        self.assertNotIn('alice@example.com',json.dumps(self.provider.calls))
        self.assertNotIn('alice@example.com',json.dumps(self.engine.sessions[self.sid]['history']))
        self.assertEqual(self.engine.sessions[self.sid]['confidentiality'],1)

    def test_live_block_tightening_withholds_old_memory_before_dispatch(self):
        self.update(epoch=8,pii_redact_at=101,pii_block_at=101)
        chat={'session_id':self.sid,'model':'local-model','prompt':'Contact alice@example.com','source':'user'}
        self.assertEqual(self.engine.handle('/v1/models/chat',chat,'agent')['outcome'],'ALLOWED')
        self.provider.calls.clear()
        self.update(epoch=9,pii_action='block',pii_redact_at=60,pii_block_at=100)
        result=self.engine.handle('/v1/models/chat',{**chat,'prompt':'A harmless follow-up'},'agent')
        self.denied(result,'SENSITIVE_DATA')
        self.assertEqual(self.provider.calls,[])

    def test_financial_classifier_revalidates_memory_without_chat_observe(self):
        self.update(epoch=8,pii_redact_at=101,pii_block_at=101)
        chat={'session_id':self.sid,'model':'local-model','prompt':'Contact alice@example.com','source':'user'}
        self.assertEqual(self.engine.handle('/v1/models/chat',chat,'agent')['outcome'],'ALLOWED')
        self.provider.calls.clear()
        self.update(epoch=9,pii_redact_at=60,pii_block_at=100)
        result=self.action(self.request(epoch='9'))
        self.assertEqual(result['outcome'],'COMMITTED')
        self.assertEqual(len(self.provider.calls),1)
        self.assertNotIn('alice@example.com',json.dumps(self.provider.calls))

    def test_already_redacted_structured_credential_memory_remains_usable(self):
        body={'schema_version':'mathguard-interaction-1','session_id':self.sid,
              'kind':'tool_call','target':'demo.echo','content':'{"password":"sensitivevalue123","count":2}',
              'approval_ref':None}
        result=self.engine.handle('/v1/interactions',body,'agent')
        self.assertEqual(result['outcome'],'ALLOWED',result)
        self.assertEqual(json.loads(result['content']),{'password':'[REDACTED_SECRET]','count':2})
        self.assertNotIn('sensitivevalue123',json.dumps(self.provider.calls))

    def test_revalidated_history_encoded_guard_is_threshold_independent(self):
        self.update(epoch=8,pii_redact_at=101,pii_block_at=101)
        self.engine.sessions[self.sid]['history']=[base64.b64encode(b'MG_SECRET_SYNTHETIC_12345').decode()]
        result=self.engine.handle('/v1/models/chat',{'session_id':self.sid,'model':'local-model',
               'prompt':'A harmless follow-up','source':'user'},'agent')
        self.denied(result,'ENCODED_SENSITIVE_DATA')
        self.assertEqual(self.provider.calls,[])

    def test_worker_stalled_input_has_an_absolute_deadline(self):
        path=Path(self.temp.name)/'non-reading-worker'
        path.write_text('#!/usr/bin/env python3\nimport time\ntime.sleep(30)\n')
        path.chmod(0o700)
        worker=Worker(path)
        self.addCleanup(worker.close)
        start=time.monotonic()
        with self.assertRaises(Denied) as caught:worker.call(op='configure',unused='x'*200000)
        self.assertEqual(caught.exception.code,'WORKER_UNAVAILABLE')
        self.assertLess(time.monotonic()-start,6.5)
        self.assertTrue(worker.broken)


if __name__=='__main__':unittest.main()
