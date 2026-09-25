import {randomBytes} from 'node:crypto';
import {mkdir,writeFile,chmod,stat} from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
// Nothing is printed or overwritten. The parent is private (0700), while files
// are readable by each container's distinct non-root identity after mounting.
const directory=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../secrets');
try {await stat(directory);throw new Error('Secrets directory already exists. Use the documented rotation procedure; nothing was changed.');}
catch(error){if(error.code!=='ENOENT')throw error;}
await mkdir(directory,{mode:0o700});await chmod(directory,0o700);
const admin=randomBytes(32).toString('hex'),runtime=randomBytes(32).toString('hex');
const secrets={postgres_password:admin,database_runtime_password:runtime,migration_database_url:`postgresql://postgres:${admin}@db:5432/leanguard`,database_url:`postgresql://leanguard_runtime:${runtime}@db:5432/leanguard`,export_signing_secret:randomBytes(32).toString('hex'),revenuecat_webhook_secret:randomBytes(32).toString('hex'),openai_api_key:'',revenuecat_secret_key:''};
for(const [name,value]of Object.entries(secrets))await writeFile(path.join(directory,name),value+'\n',{flag:'wx',mode:0o444});
console.log('Created private secrets directory. Supply firebase_admin.json and provider keys before deployment. No secrets printed.');
