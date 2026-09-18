import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const allowed=['PATH','HOME','USER','LOGNAME','TMPDIR','TEMP','LANG','LC_ALL','JAVA_HOME','SystemRoot','APPDATA'];
const env=Object.fromEntries(allowed.filter(key=>process.env[key]).map(key=>[key,process.env[key]]));
const cli=path.join(root,'firebase/functions/node_modules/firebase-tools/lib/bin/firebase.js');
const result=spawnSync(process.execPath,[cli,...process.argv.slice(2)],{cwd:root,env,stdio:'inherit'});
process.exit(result.status??1);
