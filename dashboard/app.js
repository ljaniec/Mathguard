'use strict';
const $=id=>document.getElementById(id);let sid=null,last=null,status=null,approvalExpires=null;
async function api(path,body,role='operator'){
 const headers={'Authorization':'Bearer '+$(role).value};
 const options={headers};if(body!==undefined){headers['Content-Type']='application/json';options.method='POST';options.body=JSON.stringify(body);}
 const response=await fetch(path,options);const data=await response.json();if(!response.ok)throw Error((data.reason_codes||['HTTP '+response.status]).join(', '));return data;
}
const show=(id,value)=>$(id).textContent=JSON.stringify(value,(key,v)=>key==='approval_ref'&&v?'[ISSUED]':v,2);
async function refresh(){
 status=await api('/v1/status');if(status.policy&&!status.policy.allowed_models.includes($('model').value))$('model').value=status.policy.allowed_models[0];$('health').textContent=(status.ready?'Controls ready':'Controls closed')+' / '+status.mode;
 const counts=status.counters;$('metrics').replaceChildren();
 for(const [label,value] of [['Blocked',counts.BLOCKED||0],['Committed',counts.COMMITTED||0],['p95 request ms',status.latency_ms.p95?.toFixed(1)||'—'],['Observed live calls',status.live_calls]]){
  const div=document.createElement('div');div.className='metric';const strong=document.createElement('strong');strong.textContent=value;const span=document.createElement('span');span.textContent=label;div.append(strong,span);$('metrics').append(div);
 }
 $('warnings').textContent=[...status.config_errors,...(status.quarantined?['Provider quarantined; stop the upstream job, then use operator recovery below.']:[])].join(' · ');
 $('instance').textContent='Volatile ledger '+status.instance_id+' · started '+new Date(status.started_at*1000).toLocaleString()+' · restart returns to the seeded genesis, not the current balances.';$('recovery').hidden=!status.quarantined;
 $('resources').replaceChildren();if(status.state)for(const [i,label] of ['Cost micros','Accounted tokens','Compute budget ms','Call slots'].entries()){
  const row=document.createElement('div');row.className='resource';const name=document.createElement('span');name.textContent=label;const bar=document.createElement('progress');bar.max=status.state.limit[i]||1;bar.value=status.state.spent[i]+status.state.reserved[i];const amount=document.createElement('span');amount.textContent=bar.value+' / '+status.state.limit[i];row.append(name,bar,amount);$('resources').append(row);
 }
 show('policy',{policy:status.policy,feed_version:status.feed_version,ledger:status.state?{revision:status.state.revision,balances:status.state.balances}:null});
 const events=await api('/v1/events');$('events').replaceChildren();for(const event of events.slice(-30).reverse()){
  const tr=document.createElement('tr');for(const v of [event.event_id,event.outcome,event.reason_codes.join(', '),event.policy_epoch,event.latency_ms,event.mode]){const td=document.createElement('td');td.textContent=String(v??'');tr.append(td);}$('events').append(tr);
 }
 show('assurance',await api('/v1/assurance'));
}
function action(id,fn){$(id).addEventListener('click',async()=>{const b=$(id);b.disabled=true;try{await fn();}catch(e){$('connection').textContent=e.message;}finally{b.disabled=false;}});}
action('connect',async()=>{const r=await api('/v1/sessions',{},'agent');if(!r.session_id)throw Error(r.reason_codes?.join(', '));sid=r.session_id;$('connection').textContent='Session connected. Local model must match the configured ID.';await refresh();});
action('refresh',refresh);
action('chat',async()=>{show('chat-result',await api('/v1/models/chat',{session_id:sid,model:$('model').value,prompt:$('prompt').value,source:$('source').value},'agent'));await refresh();});
action('transfer',async()=>{if(!sid)throw Error('Connect a session first');await refresh();if(!status.ready)throw Error('Valid policy/feed and worker required');last={schema_version:'mathguard-action-1',request_id:'ui-'+crypto.randomUUID(),session_id:sid,expected_revision:String(status.state.revision),policy_epoch:String(status.policy.epoch),tool:'ledger.transfer',arguments:{source:'alice-main',destination:$('destination').value,amount_minor:$('amount').value,currency:'PLN'},approval_ref:null};const decision=await api('/v1/actions',last,'agent');show('transfer-result',{proposal:last,decision});explain(decision);$('approve').disabled=decision.outcome!=='PENDING_APPROVAL';await refresh();});
action('retry',async()=>{if(!last)throw Error('Propose a transfer first');const decision=await api('/v1/actions',last,'agent');show('transfer-result',{proposal:last,decision});explain(decision);$('approve').disabled=decision.outcome!=='PENDING_APPROVAL';await refresh();});
action('approve',async()=>{if(!last)throw Error('Propose a transfer first');const r=await api('/v1/approvals',{...last,approval_ref:null},'owner');if(r.approval_ref){last.approval_ref=r.approval_ref;approvalExpires=r.expires;show('transfer-result',{proposal:last,...r,next:'Use Exact retry to submit the approved, unchanged request.'});}else show('transfer-result',r);await refresh();});
action('reload',async()=>{show('policy',await api('/v1/policy/reload',{}));await refresh();});
action('export',async()=>{const r=await fetch('/v1/audit/export',{headers:{Authorization:'Bearer '+$('operator').value}});if(!r.ok)throw Error('Export unauthorized');const blob=await r.blob();const link=document.createElement('a');link.href=URL.createObjectURL(blob);link.download='mathguard-audit.jsonl';link.click();URL.revokeObjectURL(link.href);});
fetch('/health').then(r=>r.json()).then(r=>$('health').textContent=r.mode+' / connect tokens').catch(()=>$('health').textContent='Unavailable');

action('report',async()=>{const r=await api('/v1/report');show('assurance',r);$('assurance').scrollIntoView({behavior:'smooth'});});

function explain(decision){
 const codes=decision.reason_codes||[];let message='';
 if(codes.some(c=>c==='SEMANTIC_DENIED'))message='The AI classifier blocked this proposal. Active threshold: '+status.policy.semantic_threshold+'. Owner approval cannot override this control.';
 else if(codes.some(c=>c==='APPROVAL_EXPIRED'))message='The approval expired before execution, possibly while the guard was running. No transfer was committed. The owner can issue a fresh approval for the unchanged request.';
 else if(decision.outcome==='BLOCKED')message='A deterministic policy or resource gate blocked the proposal: '+codes.join(', ')+'.';
 else if(decision.outcome==='ERROR_CLOSED')message='A required component was unavailable. Execution stayed closed: '+codes.join(', ')+'.';
 else if(decision.outcome==='PENDING_APPROVAL')message='Review the exact proposal below, then approve with the separate owner credential.';
 if(['COMMITTED','REPLAYED'].includes(decision.outcome))approvalExpires=null;
 $('decision-explanation').textContent=message;
}
setInterval(()=>{if(!approvalExpires){$('approval-status').textContent='';return;}const seconds=Math.max(0,approvalExpires-Math.floor(Date.now()/1000));const margin=(status?.policy?.deadline_seconds||15)+5;$('approval-status').textContent='Approval time remaining: '+seconds+' s.'+(seconds<=margin?' Narrow or expired window: renew the owner approval before submitting.':'');},1000);
action('recover',async()=>{if(!$('upstream-stopped').checked)throw Error('Verify that the upstream job has stopped first.');const result=await api('/v1/provider/recover',{quarantine_id:status.quarantine_id,upstream_stopped:true});$('connection').textContent=result.recovered?'Model calls restored. Ledger and charges preserved.':result.reason_codes.join(', ');$('upstream-stopped').checked=false;await refresh();});
