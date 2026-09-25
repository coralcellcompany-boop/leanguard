import pg from 'pg';
import { createReadStream } from 'node:fs';
import { readFile, stat } from 'node:fs/promises';
import { createInterface } from 'node:readline';

// Operator-only migration of an authoritative, privately exported NDJSON file.
// No Firestore SDK is loaded; no source data or auth users are deleted/changed.
// Each line: {"collection":"weight_entries","owner":"firebase-uid","id":"canonical-key","data":{...}}
const secret = async name => process.env[`${name}_FILE`] ? (await readFile(process.env[`${name}_FILE`], 'utf8')).trim() : process.env[name];
const filename=process.argv[2];
const connectionString=await secret('MIGRATION_DATABASE_URL');
if(!filename||!connectionString)throw new Error('Usage: MIGRATION_DATABASE_URL_FILE=... node scripts/import-records.mjs trusted-records.ndjson [--apply]');
if((await stat(filename)).size>512*1024*1024)throw new Error('Import exceeds 512 MiB. Split the authoritative export by complete user accounts.');
const apply=process.argv.includes('--apply');
const client=new pg.Client({connectionString});
let line=0, records=0, identical=0;
try {
  await client.connect();
  await client.query('BEGIN ISOLATION LEVEL SERIALIZABLE');
  await client.query('SET LOCAL ROLE leanguard_service');
  await client.query('SELECT pg_advisory_xact_lock(410179202)');
  const input=createInterface({input:createReadStream(filename),crlfDelay:Infinity});
  for await(const value of input){
    line++;if(!value.trim())continue;
    if(Buffer.byteLength(value)>600000)throw new Error('Record exceeds limit');
    const row=JSON.parse(value);
    if(!row||typeof row!=='object'||Object.keys(row).sort().join(',')!=='collection,data,id,owner'||typeof row.collection!=='string'||typeof row.owner!=='string'||typeof row.id!=='string'||!row.data||typeof row.data!=='object'||Array.isArray(row.data))throw new Error('Invalid record envelope');
    const existing=await client.query('SELECT data=$4::jsonb AS identical FROM app_records WHERE collection=$1 AND owner=$2 AND id=$3',[row.collection,row.owner,row.id,JSON.stringify(row.data)]);
    if(existing.rowCount){if(!existing.rows[0].identical)throw new Error('Existing record differs; refusing to overwrite');identical++;continue;}
    await client.query('INSERT INTO app_records(collection,owner,id,data) VALUES($1,$2,$3,$4::jsonb)',[row.collection,row.owner,row.id,JSON.stringify(row.data)]);
    records++;
  }
  await client.query('SET CONSTRAINTS ALL IMMEDIATE');
  const orphaned=await client.query("SELECT 1 FROM app_records owned JOIN app_records marker ON marker.collection='account_deletions' AND marker.owner='' AND marker.id=owned.owner WHERE owned.owner<>'' LIMIT 1");
  if(orphaned.rowCount)throw new Error('Import conflicts with an account deletion marker');
  await client.query(apply?'COMMIT':'ROLLBACK');
  console.log(JSON.stringify({mode:apply?'applied':'validated_rolled_back',new_records:records,identical_records:identical}));
}catch(error){
  await client.query('ROLLBACK').catch(()=>{});
  // SQL constraint details may include private health records. Never print them.
  console.error(JSON.stringify({event:'import_failed',line,code:typeof error.code==='string'?error.code:'invalid_import',message:'No import committed. Check the private source file, canonical IDs, ownership, existing conflicts and parent references.'}));
  process.exitCode=1;
}finally{await client.end();}
