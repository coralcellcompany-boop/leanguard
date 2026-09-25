import assert from 'node:assert/strict';
import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import {mkdtemp,readFile,writeFile,mkdir,chmod,rm} from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const exec=promisify(execFile);
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const image=process.env.CADDY_IMAGE??'leanguard-caddy:verification';
const directory=await mkdtemp(path.join(os.tmpdir(),'leanguard-caddy-logs-'));
const name=`leanguard-caddy-logs-${process.pid}-${Date.now()}`;
const docker=(args)=>exec('docker',args,{timeout:30000,maxBuffer:2*1024*1024});
const mount=(source,target)=>['-v',`${source}:${target}:ro`];
try{
  await chmod(directory,0o755);
  const emptySites=path.join(directory,'empty-sites'),sites=path.join(directory,'sites');
  await mkdir(emptySites,{mode:0o755});await mkdir(sites,{mode:0o755});
  await writeFile(path.join(sites,'landing.caddy'),await readFile(path.join(root,'deploy/landing.caddy')));
  const active=path.join(root,'deploy/Caddyfile');
  // Validate the real base and optional landing configurations, with no live DNS.
  for(const siteDirectory of[emptySites,sites]){
    await docker(['run','--rm','-e','API_DOMAIN=api.example.test','-e','LANDING_DOMAIN=www.example.test','-e','ACME_EMAIL=operator@example.test',...mount(active,'/etc/caddy/Caddyfile'),...mount(siteDirectory,'/etc/caddy/sites'),'--entrypoint','caddy',image,'validate','--config','/etc/caddy/Caddyfile','--adapter','caddyfile']);
  }
  // Only replace the upstream with a deliberately closed loopback port. The
  // logging policy is read from the production file unchanged.
  const source=await readFile(active,'utf8');
  assert.equal(source.split('reverse_proxy api:8080').length,2,'Expected one API upstream in the active Caddyfile');
  const fixture=path.join(directory,'Caddyfile');
  await writeFile(fixture,source.replace('reverse_proxy api:8080','reverse_proxy 127.0.0.1:59998'));
  await docker(['run','-d','--rm','--name',name,'-p','127.0.0.1::8080','-e','API_DOMAIN=http://:8080','-e','ACME_EMAIL=operator@example.test',...mount(fixture,'/etc/caddy/Caddyfile'),...mount(emptySites,'/etc/caddy/sites'),image]);
  const port=(await docker(['port',name,'8080/tcp'])).stdout.trim().split(':').at(-1);
  assert.match(port,/^\d+$/);
  const marker='CADDY_PRIVACY_TEST_ONLY_7823';
  const url=`http://127.0.0.1:${port}/v1/exports/${marker}_UID/00000000-0000-0000-0000-000000000000.json?signature=${marker}_SIGNATURE&expires=9999999999999`;
  let response;
  for(let i=0;i<20;i++){
    try{response=await fetch(url,{headers:{Authorization:`Bearer ${marker}_AUTH`,Cookie:`session=${marker}_COOKIE`,'X-Account-Id':`${marker}_IDENTITY`,Referer:`https://example.test/?secret=${marker}_REFERER`},signal:AbortSignal.timeout(1000)});break;}
    catch{await new Promise(resolve=>setTimeout(resolve,100));}
  }
  assert.equal(response?.status,502,'The fixture must exercise a real upstream failure');
  await response.text();
  const output=await docker(['logs',name]);
  const logs=output.stdout+output.stderr;
  assert.ok(!logs.includes(marker),'Proxy logs must not retain request URLs, credentials, custom identity headers or referrers');
  const events=logs.split('\n').flatMap(line=>{try{return[JSON.parse(line)];}catch{return[];}});
  const error=events.find(event=>event.level==='error'&&event.status===502);
  assert.ok(error,'Operational error events must remain enabled');
  assert.equal(typeof error.duration,'number');assert.equal(typeof error.err_id,'string');
  assert.equal(error.request,undefined);assert.match(error.msg,/connection refused/);
  console.log('Caddy base + landing validation passed; proxy error retains status/duration/error ID with no request identity or bearer URL markers.');
}finally{
  await docker(['rm','-f',name]).catch(()=>undefined);
  await rm(directory,{recursive:true,force:true});
}
