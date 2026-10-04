'use strict';
const $=id=>document.getElementById(id);
const POLL_MS=5000,READ_TIMEOUT_MS=12000,MAX_RESPONSE_BYTES=2*1024*1024;
let sid=null,last=null,lastInteraction=null,status=null,approvalExpires=null;
let connected=false,pollTimer=null,refreshPromise=null,pollFailures=0,writing=false,viewGeneration=0;
let transferApprovable=false,interactionApprovable=false;
const writeControls=['connect','chat','transfer','retry','approve','reload','intercept','interaction-approve','interaction-retry','recover'];
function safeCode(value){return typeof value==='string'&&/^[A-Z0-9_]{1,80}$/.test(value)?value:'REQUEST_FAILED';}
function safeMessage(error){return sanitize(error&&typeof error.message==='string'?error.message.slice(0,300):'Request failed.');}
function notify(message){text('connection',message);}
function sanitize(value){
 const secrets=['operator','agent','owner'].map(id=>$(id).value).filter(v=>v.length>=4);
 return JSON.parse(JSON.stringify(value,(key,v)=>{
  if(/^(authorization|api_key|access_token|password|credential|approval_ref|session_id)$/i.test(key)&&v)return '[REDACTED]';
  if(typeof v==='string')for(const secret of secrets)v=v.split(secret).join('[REDACTED]');
  return v;
 }));
}
function show(id,value){$(id).textContent=JSON.stringify(sanitize(value),null,2);}
function actionTimeout(){return Math.min(100000,Math.max(30000,(Number(status?.policy?.deadline_seconds)||15)*3000+10000));}
async function boundedResponse(response){
 if(Number(response.headers?.get('Content-Length'))>MAX_RESPONSE_BYTES){await response.body?.cancel();throw Error('Response exceeds the dashboard safety limit.');}
 if(!response.body?.getReader){const payload=await response.text();if(new TextEncoder().encode(payload).length>MAX_RESPONSE_BYTES)throw Error('Response exceeds the dashboard safety limit.');return payload;}
 const reader=response.body.getReader(),decoder=new TextDecoder();let total=0,payload='';
 try{for(;;){const {done,value}=await reader.read();if(done)break;total+=value.byteLength;if(total>MAX_RESPONSE_BYTES){await reader.cancel();throw Error('Response exceeds the dashboard safety limit.');}payload+=decoder.decode(value,{stream:true});}return payload+decoder.decode();}
 finally{reader.releaseLock();}
}
async function request(path,{body,role='operator',timeout=READ_TIMEOUT_MS,raw=false}={}){
 const token=$(role).value;if(!token)throw Error('Enter the '+role+' credential first.');
 const controller=new AbortController(),timer=setTimeout(()=>controller.abort(),timeout);
 try{
  const headers={'Authorization':'Bearer '+token};
  const options={headers,signal:controller.signal,credentials:'omit',cache:'no-store',redirect:'error'};
  if(body!==undefined){headers['Content-Type']='application/json';options.method='POST';options.body=JSON.stringify(body);}
  const response=await fetch(path,options);
  const payload=await boundedResponse(response);
  if(!response.ok){let data;try{data=JSON.parse(payload);}catch{data={};}const codes=Array.isArray(data.reason_codes)?data.reason_codes.slice(0,5).map(safeCode):[];throw Error(codes.length?codes.join(', '):'HTTP '+response.status);}
  if(raw)return payload;try{return JSON.parse(payload);}catch{throw Error('Server response was not valid JSON.');}
 }catch(error){if(error.name==='AbortError')throw Error(body!==undefined?'No confirmation before the deadline. The request may still finish; refresh before an exact retry.':'Status request timed out. The gateway may be busy.');throw error;}
 finally{clearTimeout(timer);}
}
function api(path,body,role='operator'){return request(path,{body,role,timeout:body===undefined?READ_TIMEOUT_MS:actionTimeout()});}
function controls(){
 $('disconnect').disabled=writing;
 for(const id of writeControls)$(id).disabled=writing||(id!=='connect'&&!connected);
 $('approve').disabled=writing||!connected||!transferApprovable;$('retry').disabled=writing||!connected||!last;
 $('interaction-approve').disabled=writing||!connected||!interactionApprovable;$('interaction-retry').disabled=writing||!connected||!lastInteraction;
 for(const id of ['refresh','report','export'])$(id).disabled=writing||!connected;
}
function text(id,value){$(id).textContent=sanitize(String(value??'—'));}
function integer(value){return Number.isSafeInteger(value)&&value>=0?value:0;}
function metric(label,value,className){const div=document.createElement('div');div.className='metric '+className;const strong=document.createElement('strong');strong.textContent=String(value);const span=document.createElement('span');span.textContent=label;div.append(strong,span);return div;}
function modeText(mode){return mode==='live'?'Local inference':mode==='fixture'?'TEST FIXTURE · not live AI':String(mode||'Unknown provider');}
function storageText(storage){if(storage?.mode==='sqlite')return 'Single-node durable SQLite · '+(storage.healthy?'healthy':'CLOSED: storage requires attention')+' · restored sessions are invalidated';return 'Volatile single-process demo · restart resets ledger and quotas to the seeded state';}
function renderStatus(data){
 if(!data.quarantined||data.quarantine_id!==status?.quarantine_id)$('upstream-stopped').checked=false;
 status=data;const counts=data.counters||{},posture=data.security_posture||{};
 text('health',(data.ready?'Controls ready':'Execution closed')+(data.quarantined?' · provider quarantined':''));$('health').className='status'+(!data.ready||data.quarantined?' closed':'');
 $('metrics').replaceChildren(metric('Allowed / committed',integer(counts.ALLOWED)+integer(counts.COMMITTED)+integer(counts.REPLAYED),'allow'),metric('Blocked / closed',integer(counts.BLOCKED)+integer(counts.ERROR_CLOSED),'block'),metric('Review required',integer(counts.PENDING_APPROVAL),'review'),metric('Redacted',integer(posture.redacted_interactions),'redact'));
 text('provider',modeText(data.mode));text('provider-detail',(data.policy?.semantic_model||'No active model')+' · '+integer(data.live_calls)+' live provider calls observed');
 text('versions','Policy '+(data.policy?.epoch??'none')+' / feed '+(data.feed_version??'none'));text('strictness',(data.policy?.profile||'No active strictness')+' · '+integer(posture.semantic_fallback_alerts)+' semantic fallback alerts');
 text('latency',[data.latency_ms?.p95,data.control_latency_ms?.p95].map(v=>Number.isFinite(v)?v.toFixed(1)+' ms':'—').join(' / '));
 text('latency-detail','Request '+integer(data.latency_ms?.samples)+' samples · control '+integer(data.control_latency_ms?.samples)+' samples; provider excluded from control timing.');
 const errors=Array.isArray(data.config_errors)?data.config_errors.slice(0,12).map(v=>String(v).slice(0,180)):[];
 if(data.storage&&data.storage.healthy===false)errors.push('Storage is unhealthy. Execution stays closed until safe recovery.');
 $('warnings').hidden=!errors.length;text('warnings',errors.join(' · '));$('recovery').hidden=!data.quarantined;text('quarantine-reason',data.quarantine_reason||'A provider call did not finish within its configured bounds.');
 if(data.policy?.allowed_models?.length&&!data.policy.allowed_models.includes($('model').value))$('model').value=data.policy.allowed_models[0];
 $('resources').replaceChildren();
 if(data.state){
  const labels=['Cost allowance · micros','Token allowance','Compute allowance · ms','Provider call slots'];
  labels.forEach((label,i)=>{
   const limit=integer(data.state.limit?.[i]),spent=integer(data.state.spent?.[i]),reserved=integer(data.state.reserved?.[i]);
   const used=spent+reserved,headroom=Math.max(0,limit-used),row=document.createElement('div');row.className='resource';
   const name=document.createElement('span');name.className='resource-name';name.textContent=label;
   const bar=document.createElement('progress');bar.max=limit||1;bar.value=Math.min(used,limit||1);bar.setAttribute('aria-label',label+' accounted '+used+' of '+limit);
   const values=document.createElement('span');values.className='resource-values';const strong=document.createElement('strong');strong.textContent=headroom.toLocaleString()+' headroom';const detail=document.createElement('small');detail.textContent=spent.toLocaleString()+' charged + '+reserved.toLocaleString()+' reserved / '+limit.toLocaleString();values.append(strong,detail);row.append(name,bar,values);$('resources').append(row);
  });
 }else{const p=document.createElement('p');p.textContent='Worker snapshot unavailable. Execution remains closed.';$('resources').append(p);}
 const observed=data.observed_usage;
 const elapsed=Number.isFinite(observed?.compute_ms)&&observed.compute_ms>=0?observed.compute_ms.toLocaleString(undefined,{maximumFractionDigits:1}):'unreported';
 text('observed',observed?'Observed provider returns: '+integer(observed.tokens).toLocaleString()+' reported tokens across '+integer(observed.reported_token_calls)+' token-reporting calls; '+elapsed+' ms elapsed adapter time across '+integer(observed.calls)+' calls. Unreported usage is not zero; elapsed time is not measured GPU utilization.':'Measured provider tokens and elapsed time are not exposed in this snapshot. The bars show conservative policy accounting, not measurements.');
 text('instance',storageText(data.storage)+' · instance '+String(data.instance_id||'unknown').slice(0,40)+' · started '+(data.started_at?new Date(data.started_at*1000).toLocaleString():'unknown'));
 const total=data.audit?.total_events??data.storage?.audit_events??data.retained_events??0;
 text('audit-scope','Latest 30 records shown. '+total+' '+(data.storage?.mode==='sqlite'?'durable':'in-memory')+' records; downloads are a bounded server window (up to '+(data.audit?.export_max_events||2000)+'). Use the paginated audit API for complete retained history.');
 if(data.policy_path||data.feed_path)text('policy-path-help','Policy: '+(data.policy_path||'launcher path')+' · feed: '+(data.feed_path||'launcher path'));
 show('policy',{policy:data.policy,feed_version:data.feed_version,storage:data.storage,ledger:data.state?{revision:data.state.revision,balances:data.state.balances}:null});
}
function renderEvents(events){
 if(!Array.isArray(events))throw Error('Audit response has an invalid shape.');$('events').replaceChildren();
 for(const event of events.slice(-30).reverse()){
  const tr=document.createElement('tr'),outcome=String(event.outcome||'UNKNOWN');
  const values=[event.audit_id??event.event_id,outcome,Array.isArray(event.reason_codes)?event.reason_codes.join(', '):'—',(event.policy_epoch??'—')+' / '+(event.feed_version??'—'),Number.isFinite(event.latency_ms)?event.latency_ms.toFixed(1)+' ms':'—',modeText(event.mode)];
  values.forEach((v,i)=>{const td=document.createElement('td');td.textContent=sanitize(String(v??'—'));if(i===1)td.className='outcome-'+outcome.toLowerCase().replace(/[^a-z_]/g,'');tr.append(td);});$('events').append(tr);
 }
 if(!events.length){const tr=document.createElement('tr'),td=document.createElement('td');td.colSpan=6;td.textContent='No decision records yet. Submit an interaction to create evidence.';tr.append(td);$('events').append(tr);}
}
function resetView(){
 $('metrics').replaceChildren(metric('Allowed / committed','—','allow'),metric('Blocked / closed','—','block'),metric('Review required','—','review'),metric('Redacted','—','redact'));
 for(const [id,value] of [['provider','Not connected'],['provider-detail','Connect to inspect exact model and inference mode.'],['versions','—'],['strictness','No active configuration in this view.'],['latency','—'],['observed','Provider observations have not been loaded.'],['instance','Storage and restart scope appear after connection.'],['audit-scope','Latest 30 records appear after connection.']])text(id,value);
 $('resources').replaceChildren();const p=document.createElement('p');p.textContent='Connect to view active limits, charges and reservations.';$('resources').append(p);
 renderEvents([]);$('warnings').hidden=true;$('recovery').hidden=true;
}
async function refresh(afterWrite=false){
 if(refreshPromise){if(!afterWrite)return refreshPromise;await refreshPromise.catch(()=>{});}
 const generation=viewGeneration;
 refreshPromise=(async()=>{const data=await api('/v1/status');if(generation!==viewGeneration)return;renderStatus(data);const [events,assurance]=await Promise.all([api('/v1/events'),api('/v1/assurance')]);if(generation!==viewGeneration)return;renderEvents(events);show('assurance',assurance);pollFailures=0;text('poll-state','Updated '+new Date().toLocaleTimeString()+' · refresh every 5 s');})();
 try{return await refreshPromise;}finally{refreshPromise=null;}
}
function stopPolling(){if(pollTimer)clearTimeout(pollTimer);pollTimer=null;}
function schedulePoll(){stopPolling();if(!connected)return;pollTimer=setTimeout(async()=>{if(!document.hidden&&!writing)try{await refresh();}catch(error){pollFailures=Math.min(pollFailures+1,5);text('poll-state','View stale · '+safeMessage(error));}if(connected)schedulePoll();},Math.min(30000,POLL_MS*2**pollFailures));}
function explain(decision){
 const codes=Array.isArray(decision.reason_codes)?decision.reason_codes:[];
 if(codes.includes('SEMANTIC_DENIED'))return 'The semantic classifier denied this request. Owner approval cannot override a denial.';
 if(codes.includes('APPROVAL_EXPIRED'))return 'Approval expired. No transfer was committed. The owner can issue fresh approval for the unchanged request.';
 if(decision.outcome==='ERROR_CLOSED')return 'A required safety component was unavailable. Execution stayed closed: '+codes.join(', ')+'.';
 if(decision.outcome==='BLOCKED')return 'Blocked before release or execution: '+codes.join(', ')+'.';
 if(codes.includes('SEMANTIC_REVIEW')||codes.includes('SEMANTIC_UNAVAILABLE'))return 'Semantic review is unresolved. Owner approval does not bypass this control. Resolve the cause, then inspect again.';
 if(decision.outcome==='PENDING_APPROVAL')return 'Review the exact request, then use the separate owner credential. Approval issuance does not execute the action.';
 if(decision.outcome==='REPLAYED')return 'The committed request was replayed. No second effect or resource charge.';
 if(decision.outcome==='COMMITTED')return 'The verified ledger transition committed once.';
 if(decision.redacted||String(decision.input_disposition).startsWith('REDACTED')||String(decision.output_disposition).startsWith('REDACTED'))return 'Allowed after sensitive content was redacted. Only the filtered content is released.';
 return 'Allowed by the configured deterministic and semantic controls. This is a policy decision, not a universal safety guarantee.';
}
function action(id,fn,{write=true}={}){$(id).addEventListener('click',async()=>{if(write&&writing)return;if(write){writing=true;controls();}else $(id).disabled=true;try{await fn();}catch(error){notify(safeMessage(error));}finally{if(write){writing=false;controls();}else $(id).disabled=!connected;}});}
function requireSession(){if(!sid||!connected)throw Error('Connect a session first.');}
function download(name,textValue,type){const blob=new Blob([textValue],{type}),url=URL.createObjectURL(blob),link=document.createElement('a');link.href=url;link.download=name;document.body.append(link);link.click();link.remove();setTimeout(()=>URL.revokeObjectURL(url),1000);}
action('connect',async()=>{
 if(!$('operator').value||!$('agent').value)throw Error('Enter the operator and agent credentials first.');
 viewGeneration++;
 await api('/v1/status');const result=await api('/v1/sessions',{},'agent');
 if(typeof result.session_id!=='string')throw Error((result.reason_codes||[]).map(safeCode).join(', ')||'Session was not created.');
 sid=result.session_id;connected=true;last=null;lastInteraction=null;approvalExpires=null;transferApprovable=false;interactionApprovable=false;
 notify('Session connected. Credentials are held only in this tab.');await refresh(true);schedulePoll();
});
action('disconnect',async()=>{
 viewGeneration++;
 connected=false;sid=null;last=null;lastInteraction=null;status=null;approvalExpires=null;transferApprovable=false;interactionApprovable=false;stopPolling();
 for(const role of ['operator','agent','owner'])$(role).value='';
 for(const id of ['chat-result','transfer-result','interaction-result','policy','assurance','report-result'])text(id,'Cleared from this tab.');
 resetView();text('health','Not connected');text('poll-state','Live view paused');notify('Credentials and pending requests cleared. Reload the page before using another instance.');
});
action('refresh',async()=>{await refresh(true);schedulePoll();},{write:false});
action('chat',async()=>{requireSession();const result=await api('/v1/models/chat',{session_id:sid,model:$('model').value,prompt:$('prompt').value,source:$('source').value},'agent');show('chat-result',result);text('chat-explanation',explain(result));await refresh(true);});
async function submitTransfer(){
 const result=await api('/v1/actions',last,'agent');show('transfer-result',{proposal:last,decision:result});text('decision-explanation',explain(result));transferApprovable=result.outcome==='PENDING_APPROVAL'&&result.approval_requirements?.includes('high_value');
 if(['COMMITTED','REPLAYED'].includes(result.outcome))approvalExpires=null;await refresh(true);
}
action('transfer',async()=>{
 requireSession();await refresh(true);if(!status.ready)throw Error('A valid policy, feed and healthy worker are required.');
 if(!/^[1-9][0-9]{0,17}$/.test($('amount').value))throw Error('Use a positive integer amount in PLN minor units.');
 last={schema_version:'mathguard-action-1',request_id:'ui-'+crypto.randomUUID(),session_id:sid,expected_revision:String(status.state.revision),policy_epoch:String(status.policy.epoch),tool:'ledger.transfer',arguments:{source:'alice-main',destination:$('destination').value,amount_minor:$('amount').value,currency:'PLN'},approval_ref:null};approvalExpires=null;await submitTransfer();
});
action('retry',async()=>{requireSession();if(!last)throw Error('Propose a transfer first.');await submitTransfer();});
action('approve',async()=>{requireSession();if(!last||!transferApprovable)throw Error('This exact request is not awaiting owner approval.');const result=await api('/v1/approvals',{...last,approval_ref:null},'owner');if(result.approval_ref){last.approval_ref=result.approval_ref;approvalExpires=result.expires;transferApprovable=false;text('decision-explanation','Approval issued. Use Retry unchanged to submit the exact proposal. No money moved during approval.');}show('transfer-result',{proposal:last,approval:result});await refresh(true);});
async function inspectInteraction(){const result=await api('/v1/interactions',lastInteraction,'agent');show('interaction-result',result);text('interaction-explanation',explain(result));interactionApprovable=result.outcome==='PENDING_APPROVAL'&&result.reason_codes?.includes('APPROVAL_REQUIRED');await refresh(true);}
action('intercept',async()=>{requireSession();const kind=$('interaction-kind').value;lastInteraction={schema_version:'mathguard-interaction-1',session_id:sid,kind,target:kind.startsWith('tool_')?$('interaction-target').value:'',content:$('interaction-content').value,approval_ref:null};await inspectInteraction();});
action('interaction-retry',async()=>{requireSession();if(!lastInteraction)throw Error('Inspect an interaction first.');await inspectInteraction();});
action('interaction-approve',async()=>{requireSession();if(!lastInteraction||!interactionApprovable)throw Error('This exact interaction is not awaiting owner approval.');const result=await api('/v1/interactions/approve',{...lastInteraction,approval_ref:null},'owner');if(result.approval_ref){lastInteraction.approval_ref=result.approval_ref;interactionApprovable=false;text('interaction-explanation','Approval issued for the exact content. Retry unchanged to inspect and release it. Tool dispatch remains the SDK integration’s responsibility.');}show('interaction-result',result);await refresh(true);});
action('reload',async()=>{const result=await api('/v1/policy/reload',{});show('policy',result);notify(result.reason_codes?.length?result.reason_codes.map(safeCode).join(', '):'Reload checked. Review active versions and any validation warning above.');await refresh(true);});
action('recover',async()=>{if(!$('upstream-stopped').checked)throw Error('Verify that the upstream job has stopped first.');const result=await api('/v1/provider/recover',{quarantine_id:status.quarantine_id,upstream_stopped:true});notify(result.recovered?'Model calls restored. Ledger and resource charges preserved.':(result.reason_codes||[]).map(safeCode).join(', '));$('upstream-stopped').checked=false;await refresh(true);});
action('report',async()=>{const report=await api('/v1/report'),safe=sanitize(report);show('report-result',safe);download('mathguard-management.json',JSON.stringify(safe,null,2)+'\n','application/json');notify('Sanitized management report downloaded. Its evidence and storage limitations remain included.');},{write:false});
action('export',async()=>{const raw=await request('/v1/audit/export',{raw:true}),lines=raw.split('\n').filter(v=>v.trim());const safe=lines.map(line=>{try{return JSON.stringify(sanitize(JSON.parse(line)));}catch{throw Error('Audit export contains an invalid record. Nothing was downloaded.');}}).join('\n');download('mathguard-audit-window.jsonl',safe+(safe?'\n':''),'application/x-ndjson');notify('Sanitized audit window downloaded. For complete durable history, use the documented paginated audit API.');},{write:false});
setInterval(()=>{if(!approvalExpires){text('approval-status','');return;}const seconds=Math.max(0,approvalExpires-Math.floor(Date.now()/1000)),margin=(status?.policy?.deadline_seconds||15)+5;text('approval-status','Approval expires in '+seconds+' s.'+(seconds<=margin?' Renew before retry if the execution window is too short.':''));},1000);
document.addEventListener('visibilitychange',()=>{if(!document.hidden&&connected)schedulePoll();});
window.addEventListener('pagehide',()=>{viewGeneration++;connected=false;sid=null;last=null;lastInteraction=null;approvalExpires=null;transferApprovable=false;interactionApprovable=false;stopPolling();for(const role of ['operator','agent','owner'])$(role).value='';resetView();controls();});
resetView();controls();
