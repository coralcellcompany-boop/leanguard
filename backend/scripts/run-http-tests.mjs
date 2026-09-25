import {mkdtemp,writeFile,rm} from 'node:fs/promises';
import {spawn} from 'node:child_process';
import os from 'node:os';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
if(!process.env.TEST_DATABASE_URL||!new URL(process.env.TEST_DATABASE_URL).pathname.endsWith('_test'))throw new Error('Supply restricted TEST_DATABASE_URL for an isolated *_test database.');
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'..');
const directory=await mkdtemp(path.join(os.tmpdir(),'leanguard-auth-http-'));
try{
  const configuration=path.join(directory,'firebase.json');
  await writeFile(configuration,JSON.stringify({emulators:{auth:{host:'127.0.0.1',port:9549},ui:{enabled:false},singleProjectMode:true}}));
  const env={};for(const name of['PATH','HOME','TMPDIR','JAVA_HOME','SystemRoot'])if(process.env[name])env[name]=process.env[name];
  Object.assign(env,{NODE_ENV:'test',CI:'true',FIREBASE_PROJECT_ID:'demo-leanguard',GCLOUD_PROJECT:'demo-leanguard',TEST_DATABASE_URL:process.env.TEST_DATABASE_URL,FIREBASE_CLI_DISABLE_TELEMETRY:'1'});
  const cli=process.env.FIREBASE_CLI_PATH;
  const binary=cli?process.execPath:'npx';
  const args=[...(cli?[cli]:['--yes','--package=firebase-tools@15.30.2','firebase']),'emulators:exec','--only','auth','--project','demo-leanguard','--config',configuration,'node --test test/api.integration.test.mjs'];
  const child=spawn(binary,args,{cwd:root,env,stdio:'inherit'});
  const stop=()=>child.kill('SIGTERM');process.once('SIGINT',stop);process.once('SIGTERM',stop);
  const code=await new Promise((resolve,reject)=>{child.once('error',reject);child.once('exit',value=>resolve(value??1));});
  process.removeListener('SIGINT',stop);process.removeListener('SIGTERM',stop);process.exitCode=code;
}finally{await rm(directory,{recursive:true,force:true});}
