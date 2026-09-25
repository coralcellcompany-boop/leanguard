import pg from 'pg';
import { readFile, readdir } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
const secret = async name => process.env[`${name}_FILE`] ? (await readFile(process.env[`${name}_FILE`], 'utf8')).trim() : process.env[name];
const connectionString = await secret('MIGRATION_DATABASE_URL') ?? await secret('DATABASE_URL');
if (!connectionString) throw new Error('MIGRATION_DATABASE_URL is required. Use the database owner only for migrations.');
const client = new pg.Client({connectionString});
await client.connect();
try {
  await client.query('SELECT pg_advisory_lock(410179201)');
  await client.query('CREATE TABLE IF NOT EXISTS schema_migrations (name text PRIMARY KEY, applied_at timestamptz NOT NULL DEFAULT now())');
  const directory = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../migrations');
  for (const name of (await readdir(directory)).filter(x=>/^\d+.*\.sql$/.test(x)).sort()) {
    if ((await client.query('SELECT 1 FROM schema_migrations WHERE name=$1',[name])).rowCount) continue;
    await client.query('BEGIN');
    try { await client.query(await readFile(path.join(directory,name),'utf8')); await client.query('INSERT INTO schema_migrations(name) VALUES($1)',[name]); await client.query('COMMIT'); console.log(`Applied ${name}`); }
    catch (error) { await client.query('ROLLBACK'); throw error; }
  }
} finally { await client.query('SELECT pg_advisory_unlock(410179201)').catch(()=>{}); await client.end(); }
