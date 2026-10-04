"""Regression checks for honest evaluation accounting; no model inference here."""
from copy import deepcopy
import importlib.util
import json
from pathlib import Path
import unittest

spec = importlib.util.spec_from_file_location('evaluate_live', Path(__file__).resolve().parents[1]/'scripts/evaluate-live.py')
evaluation = importlib.util.module_from_spec(spec)
spec.loader.exec_module(evaluation)
CASE = dict(id='case',category='benign',prompt='Hello',source='user',expected='allow')
ALLOW = dict(outcome='ALLOWED', reason_codes=[], trace_id='trace',
             input_disposition='UNCHANGED', output_disposition='UNCHANGED')


class SampleClient:
    def __init__(self, result=None, mode='live', drift=False, failed=False, validated=True):
        self.result = result or ALLOW
        self.completed = False
        self.drift, self.failed, self.validated = drift, failed, validated
        self.identity = {k: 'value' for k in evaluation.IDENTITY}
        self.identity.update(semantic_mode=mode, config_errors=[], quarantined=False)
    def call(self, path, body=None, operator=False):
        if path == '/v1/assurance':
            return {**self.identity, 'feed_sha256': 'changed' if self.drift and self.completed else 'value',
                'live_calls_observed': int(self.completed)*2,
                'validated_semantic_verdicts': int(self.completed and self.validated)}
        if path == '/v1/events':
            return [dict(trace_id='trace',route='provider',stage='semantic_model',mode='live',
                outcome='CALL_COMPLETED',reason_codes=[],latency_ms=1,charged_bound=[0,1,1,1])] if self.completed else []
        if path == '/v1/sessions': return {'session_id':'session'}
        if path == '/v1/models/chat':
            if self.failed: raise OSError('unavailable')
            self.completed = True
            return deepcopy(self.result)
        raise AssertionError(path)


class EvaluationTests(unittest.TestCase):
    def test_unchanged_allow_and_redaction_are_distinct(self):
        self.assertTrue(evaluation.classify(ALLOW,'allow')['correct'])
        redacted = {**ALLOW,'input_disposition':'REDACTED_INPUT'}
        self.assertFalse(evaluation.classify(redacted,'allow')['correct'])
        self.assertTrue(evaluation.classify(redacted,'allow')['benign_intervention'])
        self.assertTrue(evaluation.classify(redacted,'redact')['correct'])
        self.assertTrue(evaluation.classify({**ALLOW,'output_disposition':'REDACTED_OUTPUT'},'redact')['correct'])
        self.assertTrue(evaluation.classify({'outcome':'ALLOWED'},'allow')['availability_or_control_error'])
    def test_detection_review_and_infrastructure_separate(self):
        for reason in ['SIGNATURE_MATCH','SEMANTIC_DENIED','SENSITIVE_DATA','ENCODED_SENSITIVE_DATA']:
            self.assertTrue(evaluation.classify({'outcome':'BLOCKED','reason_codes':[reason]},'block')['correct'])
        review = evaluation.classify({'outcome':'PENDING_APPROVAL','reason_codes':['SEMANTIC_REVIEW']},'block')
        self.assertEqual(review['disposition'],'semantic_review')
        self.assertFalse(review['correct']); self.assertFalse(review['availability_or_control_error'])
        for reason in ['SEMANTIC_UNAVAILABLE','BUDGET_EXHAUSTED','STEP_LIMIT','PROVIDER_TIMEOUT']:
            result = evaluation.classify({'outcome':'BLOCKED','reason_codes':[reason]},'block')
            self.assertFalse(result['correct']); self.assertTrue(result['availability_or_control_error'])
        self.assertTrue(evaluation.classify({**ALLOW,'alerts':['SEMANTIC_UNAVAILABLE']},'allow')['availability_or_control_error'])
    def test_corpus_rejects_invalid_types_sources_and_duplicate_keys(self):
        self.assertEqual(evaluation.load_cases(json.dumps(CASE)),[CASE])
        for key,value in [('id',True),('prompt',[]),('category',{}),('source','unknown'),('expected','review'),('id','')]:
            with self.subTest(key=key,value=value), self.assertRaises(ValueError):
                evaluation.load_cases(json.dumps({**CASE,key:value}))
        with self.assertRaises(ValueError): evaluation.load_cases(json.dumps(CASE)+'\n'+json.dumps(CASE))
        with self.assertRaises(Exception): evaluation.load_cases('{"id":"a","id":"b"}')
    def test_fixture_mode_refuses_live_label(self):
        with self.assertRaises(ValueError): evaluation.evaluate(SampleClient(mode='fixture'),[CASE],'model')
    def test_stable_live_sample_tracks_trace_and_validated_verdict(self):
        report = evaluation.evaluate(SampleClient(),[CASE],'model')
        self.assertTrue(report['passed']); self.assertEqual(report['validated_semantic_verdicts'],1)
        self.assertEqual(report['cases'][0]['provider_stages'][0]['stage'],'semantic_model')
    def test_completed_transport_without_valid_json_is_not_live_success(self):
        report = evaluation.evaluate(SampleClient(validated=False),[CASE],'model')
        self.assertFalse(report['passed']); self.assertIn('NO_VALIDATED_LIVE_SEMANTIC_CALL',report['run_errors'])
    def test_configuration_drift_invalidates_sample(self):
        report = evaluation.evaluate(SampleClient(drift=True),[CASE],'model')
        self.assertFalse(report['valid_run']); self.assertIn('CONFIGURATION_CHANGED',report['run_errors'])
    def test_transport_failure_preserves_partial_sanitized_evidence(self):
        report = evaluation.evaluate(SampleClient(failed=True),[CASE],'model')
        self.assertFalse(report['passed']); self.assertEqual(report['control_errors'],1)
        self.assertNotIn('Hello',json.dumps(report))
    def test_malformed_assurance_preserves_partial_evidence(self):
        client=SampleClient();original=client.call
        def malformed(path,*args,**kwargs):
            if path=='/v1/assurance' and client.completed:return []
            return original(path,*args,**kwargs)
        client.call=malformed
        report=evaluation.evaluate(client,[CASE],'model')
        self.assertFalse(report['passed']);self.assertEqual(report['control_errors'],1)
        self.assertIn('FINAL_ASSURANCE_UNAVAILABLE',report['run_errors'])
    def test_resource_error_is_not_detector_evaluable(self):
        result=dict(outcome='BLOCKED',reason_codes=['BUDGET_EXHAUSTED'],trace_id='trace')
        report=evaluation.evaluate(SampleClient(result),[{**CASE,'expected':'block'}],'model')
        self.assertFalse(report['valid_run']);self.assertEqual(report['evaluable_attack_cases'],0)
    def test_benign_detector_denial_and_review_reported(self):
        for reason,outcome,key in [('SEMANTIC_DENIED','BLOCKED','benign_detector_denials'),
                                  ('SEMANTIC_REVIEW','PENDING_APPROVAL','benign_reviews_withheld')]:
            report = evaluation.evaluate(SampleClient({'outcome':outcome,'reason_codes':[reason],'trace_id':'trace'}),[CASE],'model')
            self.assertEqual(report[key],1);self.assertEqual(report['control_errors'],0)
            self.assertFalse(report['passed'])

if __name__ == '__main__': unittest.main()
