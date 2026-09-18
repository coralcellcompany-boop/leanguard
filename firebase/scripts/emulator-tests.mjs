import { spawnSync } from 'node:child_process';
import { existsSync, copyFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const http=process.argv.includes('--http');
// Firebase CLI debug logs can include its child process environment. Give local
// tests only ordinary runtime variables; never inherit unrelated API credentials.
const allowed=['PATH','HOME','USER','LOGNAME','TMPDIR','TEMP','LANG','LC_ALL','JAVA_HOME','SystemRoot','APPDATA'];
const env=Object.fromEntries(allowed.filter(key=>process.env[key]).map(key=>[key,process.env[key]]));
const studioJava='/Applications/Android Studio.app/Contents/jbr/Contents/Home';
if(process.platform==='darwin'&&existsSync(`${studioJava}/bin/java`)){
  env.JAVA_HOME=studioJava;
  env.PATH=`${studioJava}/bin:${env.PATH}`;
}
for(const [example,local] of [['.env.example','.env.demo-leanguard'],['.secret.local.example','.secret.local']]){
  if(http&&!existsSync(path.join(root,'firebase/functions',local)))copyFileSync(path.join(root,'firebase/functions',example),path.join(root,'firebase/functions',local));
}
const build=spawnSync('npm',['--prefix','firebase/functions','run','build'],{cwd:root,env,stdio:'inherit'});
if(build.status!==0)process.exit(build.status??1);
const cli=path.join(root,'firebase/functions/node_modules/firebase-tools/lib/bin/firebase.js');
const command=http?'node --test firebase/functions/test/http.test.mjs':'node --test --test-concurrency=1 firebase/functions/test/emulator.test.mjs';
const result=spawnSync(process.execPath,[cli,'emulators:exec','--non-interactive','--project','demo-leanguard','--only',http?'auth,firestore,storage,functions':'auth,firestore,storage',command,'--config','firebase.json'],{cwd:root,env,stdio:'inherit'});
process.exit(result.status??1);
