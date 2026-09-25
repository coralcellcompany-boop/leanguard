import test from 'node:test';
import assert from 'node:assert/strict';
import {createServer} from 'node:http';
import {Router} from 'express';
import {createApp,ingressLimit,limitConcurrent} from '../lib/app.js';

async function server(t, dependencies={}) {
  const app=createApp({records:Router(),ready:async()=>{},actions:{echo:async(req,res)=>{res.json({value:req.body?.value??null});}},...dependencies});
  const instance=createServer(app);await new Promise(resolve=>instance.listen(0,'127.0.0.1',resolve));
  t.after(()=>new Promise(resolve=>{instance.close(resolve);instance.closeAllConnections();}));
  return `http://127.0.0.1:${instance.address().port}`;
}
const post=(url,body,headers={})=>fetch(url,{method:'POST',headers:{'Content-Type':'application/json',...headers},body:JSON.stringify(body)});

test('HTTP health and origin policy return no-store without implementation headers',async t=>{
  const url=await server(t,{origins:['https://app.example.com']});
  const live=await fetch(`${url}/health/live`);
  assert.equal(live.status,200);assert.equal(live.headers.get('cache-control'),'no-store');assert.equal(live.headers.get('x-powered-by'),null);
  assert.deepEqual(await (await fetch(`${url}/health/ready`)).json(),{status:'ready'});
  assert.equal((await post(`${url}/v1/echo`,{}, {Origin:'https://attacker.example'})).status,403);
  const allowed=await post(`${url}/v1/echo`,{value:1},{Origin:'https://app.example.com'});
  assert.equal(allowed.headers.get('access-control-allow-origin'),'https://app.example.com');
  assert.deepEqual(await allowed.json(),{value:1});
});
test('readiness fails closed, method restrictions and unknown endpoints are explicit',async t=>{
  const url=await server(t,{ready:async()=>{throw new Error('private db credential');}});
  const ready=await fetch(`${url}/health/ready`);assert.equal(ready.status,503);assert.deepEqual(await ready.json(),{status:'unavailable'});
  assert.equal((await fetch(`${url}/v1/echo`)).status,405);
  assert.equal((await fetch(`${url}/v1/unknown`)).status,404);
});
test('malformed, oversized and compressed bodies are rejected before execution',async t=>{
  const url=await server(t);
  assert.equal((await fetch(`${url}/v1/echo`,{method:'POST',headers:{'Content-Type':'application/json'},body:'{invalid'})).status,400);
  assert.equal((await post(`${url}/v1/echo`,{value:'x'.repeat(33000)})).status,413);
  assert.equal((await fetch(`${url}/v1/echo`,{method:'POST',headers:{'Content-Type':'application/json','Content-Encoding':'gzip'},body:'{}'})).status,400);
});
test('exports can return data over the request limit and admit only one outstanding operation',async t=>{
  let release;const gate=new Promise(resolve=>{release=resolve;});let entered;const started=new Promise(resolve=>{entered=resolve;});
  const url=await server(t,{actions:{dataExport:async(_req,res)=>{entered();await gate;res.json({data:'x'.repeat(64000)});}}});
  const first=post(`${url}/v1/dataExport`,{});await started;
  const blocked=await post(`${url}/v1/dataExport`,{});assert.equal(blocked.status,503);assert.equal(blocked.headers.get('retry-after'),'5');
  release();const response=await first;assert.equal(response.status,200);assert.equal((await response.json()).data.length,64000);
  assert.equal((await post(`${url}/v1/dataExport`,{})).status,200);
});
test('real protected routes reject missing credentials and do not require App Check',async t=>{
  const instance=createServer(createApp({ready:async()=>{}}));await new Promise(resolve=>instance.listen(0,'127.0.0.1',resolve));
  t.after(()=>new Promise(resolve=>{instance.close(resolve);instance.closeAllConnections();}));const url=`http://127.0.0.1:${instance.address().port}`;
  for(const path of ['/v1/records/weight_entries','/v1/records/subscription_entitlements']) {
    const response=await fetch(url+path);assert.equal(response.status,401);assert.equal((await response.json()).error,'unauthenticated');
  }
  assert.equal((await post(`${url}/v1/coach`,{})).status,401);
});
test('per-process ingress returns a bounded retry delay',()=>{
  const limiter=ingressLimit(1,1000);let status;const headers={};const response={set:(key,value)=>{headers[key]=value;return response;},status:value=>{status=value;return response;},json:()=>response};let calls=0;
  const req={ip:'127.0.0.1',socket:{}};limiter(req,response,()=>calls++);limiter(req,response,()=>calls++);
  assert.equal(calls,1);assert.equal(status,429);assert.equal(headers['Retry-After'],'1');
});
test('a disconnected request does not release export capacity before work settles',async()=>{
  let release;const gate=new Promise(resolve=>{release=resolve;});
  const handler=limitConcurrent(async()=>{await gate;},1);let status;const res={set:()=>res,status:value=>{status=value;return res;},json:()=>res};
  handler({},res,()=>{});handler({},res,()=>{});assert.equal(status,503);release();await gate;await new Promise(resolve=>setImmediate(resolve));
  status=undefined;handler({},res,()=>{});assert.equal(status,undefined);
});
