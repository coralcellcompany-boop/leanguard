import { test } from 'node:test';
import assert from 'node:assert/strict';

const base='http://127.0.0.1:5001/demo-leanguard/europe-west1';
test('actual HTTPS Functions emulator authenticates ID tokens and serves guarded endpoints',async()=>{
  const created=await fetch('http://127.0.0.1:9099/identitytoolkit.googleapis.com/v1/accounts:signUp?key=emulator-only',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:`smoke-${crypto.randomUUID()}@example.test`,password:'Emulator-only-password-123!',returnSecureToken:true})});
  assert.equal(created.status,200); const account=await created.json();
  const post=async(name,body,authenticated=true)=>fetch(`${base}/${name}`,{method:'POST',headers:{'Content-Type':'application/json',...(authenticated?{Authorization:`Bearer ${account.idToken}`}:{})},body:JSON.stringify(body)});
  assert.equal((await fetch(`${base}/coach`)).status,405);
  assert.equal((await post('coach',{kind:'question',message:'Hello'},false)).status,401);
  const safety=await post('coach',{kind:'question',message:'I fainted during exercise'}); assert.equal(safety.status,200); assert.equal((await safety.json()).safety,'urgent');
  const noConsent=await post('coach',{kind:'question',message:'How can I improve consistency?'}); assert.equal(noConsent.status,403); assert.equal((await noConsent.json()).error,'consent_required');
  const consent=await post('recordConsent',{row:{id:crypto.randomUUID(),user_id:account.localId,kind:'health_data',granted:false,policy_version:'http-test'}}); assert.equal(consent.status,200); assert.equal((await consent.json()).granted,false);
  const wrongOwner=await post('recordConsent',{row:{id:crypto.randomUUID(),user_id:'another-account',kind:'health_data',granted:true,policy_version:'http-test'}}); assert.equal(wrongOwner.status,400);
  const exportResponse=await post('dataExport',{}); assert.equal(exportResponse.status,200); const data=await exportResponse.json(); assert.equal(data.user_id,account.localId); assert.equal(data.tables.consent_records.length,1);
});
