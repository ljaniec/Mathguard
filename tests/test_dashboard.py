"""Dashboard contracts and JavaScript behavior in a minimal DOM harness.

These checks exercise rendering, credential hygiene and request/retry behavior.
They do not replace visual/browser QA or measure semantic model accuracy.
"""
from html.parser import HTMLParser
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]


class Markup(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids = []
        self.attrs = {}
        self.scripts = []

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if 'id' in attrs:
            self.ids.append(attrs['id'])
            self.attrs[attrs['id']] = (tag, attrs)
        if tag == 'script':
            self.scripts.append(attrs)


HARNESS = r"""
const fs=require('node:fs'),vm=require('node:vm'),assert=require('node:assert/strict');
const input=JSON.parse(fs.readFileSync(0,'utf8'));
class Element {
 constructor(tag='div'){this.tag=tag;this.children=[];this.value='';this.disabled=false;this.hidden=false;this.attrs={};this.handlers={};this.ownText='';}
 get textContent(){return this.ownText+this.children.map(c=>c.textContent||'').join('');}
 set textContent(v){this.ownText=String(v);this.children=[];}
 append(...items){this.children.push(...items);}
 replaceChildren(...items){this.children=items;this.ownText='';}
 setAttribute(k,v){this.attrs[k]=v;}
 addEventListener(k,fn){this.handlers[k]=fn;}
 remove(){}
 click(){this.clicked=true;return this.handlers.click?.();}
}
const elements=Object.fromEntries(input.ids.map(id=>[id,new Element()]));
const timers=[],fetches=[],downloads=[];
const context={console,TextEncoder,TextDecoder,AbortController,Date,Math,JSON,Number,String,Array,Promise,Error,RegExp,Uint8Array,
 document:{hidden:false,body:new Element('body'),getElementById:id=>{assert.ok(elements[id],'missing '+id);return elements[id];},createElement:tag=>new Element(tag),addEventListener(){}},
 window:{addEventListener(){}},crypto:{randomUUID:()=> 'id-123'},
 Blob:class{constructor(parts,options){this.parts=parts;this.options=options;}},
 URL:{createObjectURL:b=>{downloads.push(b);return 'blob:local-only';},revokeObjectURL(){}},
 setTimeout:(fn,ms)=>{const timer={fn,ms};timers.push(timer);return timer;},clearTimeout:t=>{if(t)t.cleared=true;},setInterval:()=>1,
 fetch:async(path,options)=>{fetches.push({path,options});return {ok:true,status:200,headers:{get:()=>null},text:async()=> '{}'};}
};
vm.createContext(context);vm.runInContext(input.source,context);
async function run(code){return await vm.runInContext('(async()=>{'+code+'})()',context);}
(async()=>{
 switch(input.case){
 case 'safe-render':
  await run(`$('operator').value='operator-private-token';
  renderStatus({ready:true,mode:'fixture',policy:{epoch:7,profile:'balanced',semantic_model:'<img src=x onerror=evil()>',allowed_models:['fixture-model']},feed_version:2,counters:{ALLOWED:2,COMMITTED:1,REPLAYED:1,BLOCKED:3,ERROR_CLOSED:2,PENDING_APPROVAL:4},security_posture:{redacted_interactions:1},config_errors:['<script>evil()</script>'],state:{limit:[100,1000,10000,20],spent:[10,100,1000,2],reserved:[20,200,2000,1]},storage:{mode:'sqlite',healthy:true,audit_events:4},observed_usage:{tokens:123,compute_ms:321.5,calls:2,reported_token_calls:1},latency_ms:{p95:11,samples:3},control_latency_ms:{p95:2,samples:3}});
  renderEvents([{audit_id:1,outcome:'BLOCKED',reason_codes:['<script>evil()</script>'],policy_epoch:7,feed_version:2,latency_ms:1,mode:'fixture'}]);`);
  assert.equal(elements.metrics.children.length,4);
  assert.deepEqual(elements.metrics.children.map(c=>c.children[0].textContent),['4','5','4','1']);
  assert.match(elements.provider.textContent,/TEST FIXTURE/);
  assert.match(elements['provider-detail'].textContent,/<img/);
  assert.match(elements.events.textContent,/<script>/);
  assert.equal(elements.resources.children[0].children[2].children[0].textContent,'70 headroom');
  assert.match(elements.resources.textContent,/10 charged \+ 20 reserved/);
  assert.match(elements.observed.textContent,/elapsed adapter time/);
  assert.match(elements.observed.textContent,/321\.5 ms/);
  assert.match(elements.instance.textContent,/durable SQLite/);
  assert.equal(elements.warnings.hidden,false);
  break;
 case 'redaction':
  await run(`$('operator').value='operator-private-token';$('agent').value='agent-private-token';show('report-result',{authorization:'operator-private-token',approval_ref:'opaque-approval',session_id:'opaque-session',note:'contains agent-private-token',tokens:123});`);
  assert.doesNotMatch(elements['report-result'].textContent,/private-token|opaque-approval|opaque-session/);
  assert.match(elements['report-result'].textContent,/"tokens": 123/);
  break;
 case 'role-network':
  await run(`$('owner').value='owner-private-token';await api('/v1/approvals',{approval_ref:null},'owner');`);
  assert.equal(fetches.length,1);assert.equal(fetches[0].path,'/v1/approvals');
  assert.equal(fetches[0].options.headers.Authorization,'Bearer owner-private-token');
  assert.equal(fetches[0].options.credentials,'omit');assert.equal(fetches[0].options.redirect,'error');
  assert.ok(fetches[0].options.signal);assert.doesNotMatch(fetches[0].options.body,/private-token/);
  assert.ok(timers.some(t=>t.ms===55000&&t.cleared));
  break;
 case 'request-errors':
  context.fetch=async()=>({ok:false,status:403,headers:{get:()=>null},text:async()=>JSON.stringify({reason_codes:['<script>secret</script>','AUTH_REQUIRED']})});
  await assert.rejects(run(`$('operator').value='operator-private-token';await api('/v1/status');`),/REQUEST_FAILED, AUTH_REQUIRED/);
  context.fetch=async()=>({ok:true,headers:{get:()=>String(2097153)},body:{cancel:async()=>{}}});
  await assert.rejects(run(`await api('/v1/status');`),/safety limit/);
  let cancelled=false,released=false;
  context.fetch=async()=>({ok:true,headers:{get:()=>null},body:{getReader:()=>({read:async()=>({done:false,value:new Uint8Array(2097153)}),cancel:async()=>{cancelled=true;},releaseLock:()=>{released=true;}})}});
  await assert.rejects(run(`await api('/v1/status');`),/safety limit/);
  assert.ok(cancelled&&released,'oversized stream is cancelled and released');
  context.fetch=async()=>{const e=new Error('aborted');e.name='AbortError';throw e;};
  await assert.rejects(run(`await api('/v1/actions',{});`),/may still finish.*exact retry/);
  break;
 case 'exact-retry':
  context.fetch=async(path,options)=>{fetches.push({path,options});return {ok:true,headers:{get:()=>null},text:async()=>JSON.stringify(path==='/v1/actions'?{outcome:'REPLAYED',reason_codes:[]}:{})};};
  await run(`connected=true;sid='session-1';$('agent').value='agent-private-token';last={request_id:'fixed-id',arguments:{amount_minor:'2500'},approval_ref:'fixed-approval'};refresh=async()=>{};await submitTransfer();await submitTransfer();`);
  assert.equal(fetches.length,2);assert.equal(fetches[0].options.body,fetches[1].options.body);
  assert.match(elements['decision-explanation'].textContent,/No second effect/);
  assert.doesNotMatch(elements['transfer-result'].textContent,/fixed-approval/);
  break;
 case 'refresh-single-flight':
  context.fetch=async(path,options)=>{fetches.push({path,options});return {ok:true,headers:{get:()=>null},text:async()=>JSON.stringify(path==='/v1/events'?[]:path==='/v1/status'?{counters:{},mode:'fixture',ready:false}:{})};};
  await run(`$('operator').value='operator-private-token';await Promise.all([refresh(),refresh(),refresh()]);`);
  assert.equal(fetches.length,3);
  assert.match(elements.health.textContent,/Execution closed/);
  assert.match(elements.instance.textContent,/Volatile/);
  assert.match(elements.observed.textContent,/not exposed/);
  break;
 case 'clear-credentials':
  await run(`connected=true;sid='session-1';last={};$('operator').value='op';$('agent').value='ag';$('owner').value='ow';`);
  await elements.disconnect.handlers.click();
  assert.ok(['operator','agent','owner'].every(id=>elements[id].value===''));
  assert.equal(elements.chat.disabled,true);assert.equal(elements.retry.disabled,true);
  assert.equal(elements['interaction-retry'].disabled,true);
  assert.match(elements['transfer-result'].textContent,/Cleared/);
  break;
 case 'restart-session':
  await run(`connected=true;sid='old-session';last={approval_ref:'old-approval'};lastInteraction={approval_ref:'old-interaction-approval'};transferApprovable=true;interactionApprovable=true;approvalExpires=123;status={instance_id:'before'};$('operator').value='operator-private-token';$('agent').value='agent-private-token';$('owner').value='owner-private-token';renderStatus({instance_id:'before',ready:true,policy:{max_output_tokens:128}});`);
  assert.equal(await run('return sid;'),'old-session');
  await run(`renderStatus({instance_id:'after',ready:true,policy:{max_output_tokens:128}});`);
  assert.equal(await run('return sid;'),null);
  assert.equal(await run('return last;'),null);
  assert.equal(await run('return lastInteraction;'),null);
  assert.equal(await run('return approvalExpires;'),null);
  assert.equal(elements.chat.disabled,true);assert.equal(elements.retry.disabled,true);
  assert.equal(elements.approve.disabled,true);assert.equal(elements['interaction-retry'].disabled,true);
  assert.equal(fetches.length,0,'restart detection never retries a request');
  assert.match(elements.connection.textContent,/instance changed.*Connect.*no request was retried/);
  assert.match(elements['chat-limits'].textContent,/128 tokens.*3 separately charged/);
  assert.equal(elements.owner.value,'owner-private-token');
  context.fetch=async(path,options)=>{fetches.push({path,options});return {ok:true,headers:{get:()=>null},text:async()=>JSON.stringify(path==='/v1/status'?{instance_id:'after',ready:true,policy:{max_output_tokens:128}}:path==='/v1/sessions'?{session_id:'new-session'}:path==='/v1/events'?[]:{})};};
  await elements.connect.handlers.click();
  assert.equal(await run('return sid;'),'new-session');
  assert.equal(elements.chat.disabled,false);assert.equal(elements.retry.disabled,true);
  assert.equal(fetches.filter(f=>f.path==='/v1/sessions').length,1);
  assert.ok(fetches.every(f=>!['/v1/actions','/v1/models/chat'].includes(f.path)));
  break;
 case 'report-download':
  context.fetch=async()=>({ok:true,headers:{get:()=>null},text:async()=>JSON.stringify({deployment:'single-node',limitations:['Detector accuracy not proved'],approval_ref:'hidden-approval',note:'operator-private-token',tokens:22})});
  await run(`connected=true;$('operator').value='operator-private-token';`);
  await elements.report.handlers.click();
  assert.equal(downloads.length,1);assert.doesNotMatch(downloads[0].parts[0],/hidden-approval|operator-private-token/);
  assert.match(downloads[0].parts[0],/Detector accuracy not proved/);
  break;
 case 'quarantine-attestation':
  await run(`const base={ready:true,counters:{},mode:'fixture',quarantined:true,quarantine_id:'old'};renderStatus(base);$('upstream-stopped').checked=true;renderStatus(base);`);
  assert.equal(elements['upstream-stopped'].checked,true);
  await run(`renderStatus({ready:true,counters:{},quarantined:true,quarantine_id:'new'});`);
  assert.equal(elements['upstream-stopped'].checked,false);
  await elements.recover.handlers.click();
  assert.equal(fetches.length,0);
  assert.match(elements.connection.textContent,/Verify that the upstream job/);
  assert.equal(elements.recovery.hidden,false);
  break;
 default:throw Error('Unknown test');
 }
 process.stdout.write('ok\n');
})().catch(error=>{console.error(error);process.exitCode=1;});
"""


class DashboardTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.html = (ROOT/'dashboard/index.html').read_text()
        cls.js = (ROOT/'dashboard/app.js').read_text()
        cls.markup = Markup()
        cls.markup.feed(cls.html)
        cls.node = shutil.which('node') or os.environ.get('CODEX_PRIMARY_RUNTIME_NODE')

    def test_markup_has_accessible_roles_and_matching_js_controls(self):
        self.assertEqual(len(self.markup.ids),len(set(self.markup.ids)))
        for role in ('operator','agent','owner'):
            tag, attrs = self.markup.attrs[role]
            self.assertEqual(tag,'input')
            self.assertEqual(attrs['type'],'password')
            self.assertEqual(attrs['autocomplete'],'off')
        for element in re.findall(r"\$\('([^']+)'\)",self.js):
            self.assertIn(element,self.markup.ids)
        self.assertEqual(self.markup.scripts,[{'src':'/app.js'}])
        self.assertIn('aria-live="polite"',self.html)
        self.assertIn('scope="col"',self.html)
        self.assertIn('/logo.png',self.html)

    def test_no_script_html_or_credential_persistence_sinks(self):
        for forbidden in ('innerHTML','outerHTML','insertAdjacentHTML','document.write(',
                          'localStorage','sessionStorage','document.cookie','eval(',
                          'console.log(', 'location.search'):
            self.assertNotIn(forbidden,self.js)
        self.assertIn("headers={'Authorization':'Bearer '+token}",self.js)
        self.assertIn("redirect:'error'",self.js)
        self.assertIn('AbortController',self.js)
        self.assertIn('reader.cancel()',self.js)
        self.assertIn('refreshPromise',self.js)
        self.assertIn('Math.min(30000,POLL_MS*2**pollFailures)',self.js)

    def run_js(self, case):
        if not self.node:
            self.skipTest('Node is unavailable; JavaScript DOM behavior not verified')
        result=subprocess.run([self.node,'-e',HARNESS],input=json.dumps({'ids':self.markup.ids,'source':self.js,'case':case}),text=True,capture_output=True,timeout=15)
        self.assertEqual(result.returncode,0,result.stdout+'\n'+result.stderr)
        self.assertEqual(result.stdout,'ok\n')

    def test_dom_renders_untrusted_metadata_as_text_and_correct_headroom(self): self.run_js('safe-render')
    def test_credentials_and_approval_handles_are_redacted_in_outputs(self): self.run_js('redaction')
    def test_role_request_header_deadline_and_no_credential_body(self): self.run_js('role-network')
    def test_error_codes_body_bounds_and_ambiguous_write_timeout(self): self.run_js('request-errors')
    def test_transfer_retry_reuses_exact_body_and_reports_replay(self): self.run_js('exact-retry')
    def test_concurrent_refresh_is_coalesced_with_honest_fallbacks(self): self.run_js('refresh-single-flight')
    def test_clear_credentials_invalidates_session_and_actions(self): self.run_js('clear-credentials')
    def test_restart_clears_session_approvals_without_retry_and_allows_reconnect(self): self.run_js('restart-session')
    def test_management_export_redacts_credentials_preserves_limits(self): self.run_js('report-download')
    def test_new_quarantine_incident_requires_fresh_operator_attestation(self): self.run_js('quarantine-attestation')


if __name__=='__main__':
    unittest.main()
