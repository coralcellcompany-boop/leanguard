import {execFile} from 'node:child_process';
import {promisify} from 'node:util';
import assert from 'node:assert/strict';
const execute=promisify(execFile);
const connection=new URL(process.env.TEST_DATABASE_URL??'');
if(!connection.pathname.endsWith('_test'))throw new Error('Use an isolated *_test database.');
connection.hostname='host.docker.internal';
const name=`leanguard-api-smoke-${process.pid}`;
try{
  await execute('docker',['run','-d','--rm','--name',name,'--read-only','--tmpfs','/tmp:rw,noexec,nosuid,size=64m','--cap-drop','ALL','--security-opt','no-new-privileges','--add-host','host.docker.internal:host-gateway','-e','NODE_ENV=production','-e','HOST=0.0.0.0','-e',`DATABASE_URL=${connection}`,'-e','FIREBASE_PROJECT_ID=demo-leanguard','-e','PUBLIC_BASE_URL=https://api.example.test','-e','EXPORT_SIGNING_SECRET=isolated-container-key-at-least-thirty-two-characters','leanguard-api:verification']);
  let ready=false;
  for(let attempt=0;attempt<30;attempt++){
    try{await execute('docker',['exec',name,'node','-e',"fetch('http://127.0.0.1:8080/health/ready',{signal:AbortSignal.timeout(2000)}).then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"]);ready=true;break;}
    catch{await new Promise(resolve=>setTimeout(resolve,1000));}
  }
  assert.equal(ready,true,'Container must become ready using restricted database credentials.');
  const inspected=JSON.parse((await execute('docker',['inspect',name])).stdout)[0];
  assert.equal(inspected.Config.User,'10001:10001');assert.equal(inspected.HostConfig.ReadonlyRootfs,true);
  await execute('docker',['exec',name,'node','-e',"fetch('http://127.0.0.1:8080/v1/records/weight_entries').then(r=>process.exit(r.status===401?0:1)).catch(()=>process.exit(1))"]);
  console.log('Docker API smoke passed: non-root, read-only, ready PostgreSQL, authentication required.');
}finally{await execute('docker',['stop','--time','35',name]).catch(()=>{});}
