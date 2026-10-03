#!/usr/bin/env python3
"""Evaluate the live gateway on user-supplied JSONL cases; never score outages as detection."""
import argparse
from collections import Counter
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import time
import urllib.request


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--corpus',type=Path,required=True)
    parser.add_argument('--model',required=True)
    parser.add_argument('--label',choices=['development','independent-unseen'],required=True)
    parser.add_argument('--output',type=Path,required=True)
    parser.add_argument('--url',default='http://127.0.0.1:8787')
    args=parser.parse_args()
    token=os.environ['MATHGUARD_AGENT_TOKEN']
    def call(path,body=None):
        request=urllib.request.Request(args.url+path,data=json.dumps(body).encode() if body is not None else None,
          headers={'Authorization':'Bearer '+token,'Content-Type':'application/json'})
        with urllib.request.urlopen(request,timeout=90) as response:return json.load(response)
    before=call('/v1/assurance')
    if before['semantic_mode']!='live':raise SystemExit('Refusing to label fixture results as live evaluation')
    cases=[json.loads(line) for line in args.corpus.read_text().splitlines() if line.strip()]
    if not cases or len(cases)>50:raise SystemExit('Use 1..50 cases per bounded run')
    seen=set()
    for c in cases:
        if set(c)!={'id','category','prompt','source','expected'} or c['expected'] not in {'allow','block','redact'}:
            raise SystemExit('Invalid corpus case')
        if c['id'] in seen:raise SystemExit('Duplicate case ID')
        seen.add(c['id'])
    rows=[]
    for c in cases:
        sid=call('/v1/sessions',{}).get('session_id')
        start=time.monotonic()
        result=call('/v1/models/chat',{'session_id':sid,'model':args.model,'prompt':c['prompt'],'source':c['source']})
        codes=result.get('reason_codes',[])
        detected=result.get('outcome')=='BLOCKED' and any(
          code.startswith('SIGNATURE_') or code in {'SEMANTIC_DENIED','SENSITIVE_DATA','ENCODED_SENSITIVE_DATA'} for code in codes)
        allowed=result.get('outcome')=='ALLOWED'
        redacted=allowed and (result.get('input_disposition')=='REDACTED_INPUT' or result.get('output_disposition')=='REDACTED_OUTPUT')
        correct={'allow':allowed,'block':detected,'redact':redacted}[c['expected']]
        rows.append({'id':c['id'],'category':c['category'],'expected':c['expected'],
          'outcome':result.get('outcome'),'reason_codes':codes,'correct':correct,
          'availability_or_control_error':not (allowed or detected),
          'latency_ms':round((time.monotonic()-start)*1000,3),'trace_id':result.get('trace_id')})
    after=call('/v1/assurance')
    live_delta=after['live_calls_observed']-before['live_calls_observed']
    categories={}
    for category in sorted({r['category'] for r in rows}):
        subset=[r for r in rows if r['category']==category]
        categories[category]={'cases':len(subset),'correct':sum(r['correct'] for r in subset),
          'errors':sum(r['availability_or_control_error'] for r in subset)}
    negative=[r for r in rows if r['expected']=='block'];benign=[r for r in rows if r['expected']=='allow']
    report={'timestamp_utc':datetime.now(timezone.utc).isoformat(),'model':args.model,'corpus_label':args.label,
      'corpus_sha256':hashlib.sha256(args.corpus.read_bytes()).hexdigest(),'assurance':after,
      'live_calls_in_run':live_delta,'categories':categories,'cases':rows,
      'attack_cases_allowed':sum(r['outcome']=='ALLOWED' for r in negative),'attack_cases':len(negative),
      'benign_cases_blocked':sum(r['outcome']=='BLOCKED' and not r['availability_or_control_error'] for r in benign),
      'benign_cases':len(benign),'errors':sum(r['availability_or_control_error'] for r in rows),
      'note':'Observed sample outcomes only. Unseen status is the evaluator declaration; it is not verified by this script.'}
    args.output.parent.mkdir(parents=True,exist_ok=True)
    args.output.write_text(json.dumps(report,indent=2)+'\n')
    print(json.dumps({'report':str(args.output),'cases':len(rows),'live_calls':live_delta,'errors':report['errors']}))
    if live_delta==0 or report['errors'] or not all(r['correct'] for r in rows):raise SystemExit(1)

if __name__=='__main__':main()
