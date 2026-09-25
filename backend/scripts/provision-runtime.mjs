import pg from 'pg';
import {readFile} from 'node:fs/promises';
const secret=async name=>process.env[`${name}_FILE`]?(await readFile(process.env[`${name}_FILE`],'utf8')).trim():process.env[name];
const connectionString=await secret('MIGRATION_DATABASE_URL');
const password=await secret('DATABASE_RUNTIME_PASSWORD');
if(!connectionString||!password||password.length<24)throw new Error('Provide migration URL and a runtime password of at least 24 characters using protected env/files.');
const client=new pg.Client({connectionString});await client.connect();
try{
  await client.query("DO $$ BEGIN IF NOT EXISTS(SELECT FROM pg_roles WHERE rolname='leanguard_runtime') THEN CREATE ROLE leanguard_runtime LOGIN NOINHERIT NOBYPASSRLS NOSUPERUSER NOCREATEDB NOCREATEROLE; END IF; END $$");
  const formatted=await client.query("SELECT format('ALTER ROLE leanguard_runtime WITH PASSWORD %L', $1::text) AS sql",[password]);
  await client.query(formatted.rows[0].sql);
  await client.query('GRANT leanguard_service,leanguard_user TO leanguard_runtime');
  console.log('Provisioned restricted leanguard_runtime login. No password printed.');
}finally{await client.end();}
