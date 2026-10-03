#!/usr/bin/env python3
"""Small reference agent. Every model and tool request goes through Mathguard."""
import argparse
import json
import os
import urllib.request
import uuid


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('instruction')
    p.add_argument('--model',default='local-model')
    p.add_argument('--url',default='http://127.0.0.1:8787')
    a=p.parse_args()
    token=os.environ['MATHGUARD_AGENT_TOKEN']
    def call(path,body=None):
        r=urllib.request.Request(a.url+path,data=json.dumps(body).encode() if body is not None else None,
          headers={'Content-Type':'application/json','Authorization':'Bearer '+token})
        with urllib.request.urlopen(r,timeout=70) as response: return json.load(response)
    session=call('/v1/sessions',{})['session_id']
    snapshot=call('/v1/ledger/summary')
    prompt=('Return only JSON with exactly destination (bob-main or merchant) and amount_minor '
      '(positive integer encoded as a decimal string, PLN minor units). Do not execute anything. User request: '+a.instruction)
    proposal=call('/v1/models/chat',{'session_id':session,'model':a.model,'prompt':prompt,'source':'user'})
    if proposal.get('outcome')!='ALLOWED': print(json.dumps(proposal,indent=2));return
    action=json.loads(proposal['output'])
    if set(action)!={'destination','amount_minor'}: raise SystemExit('Invalid structured proposal')
    envelope={'schema_version':'mathguard-action-1','request_id':'agent-'+uuid.uuid4().hex,
      'session_id':session,'expected_revision':snapshot['revision'],'policy_epoch':snapshot['policy_epoch'],
      'tool':'ledger.transfer','arguments':{'source':'alice-main','destination':action['destination'],
      'amount_minor':action['amount_minor'],'currency':'PLN'},'approval_ref':None}
    print(json.dumps({'proposal':envelope,'decision':call('/v1/actions',envelope)},indent=2))

if __name__=='__main__': main()
