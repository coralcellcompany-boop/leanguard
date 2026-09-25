import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, stat, utimes, readFile, symlink, mkdir } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { ExportFiles, exportLifetimeMs } from '../lib/shared/export-files.js';

async function fixture(run) {
  const directory = await mkdtemp(path.join(os.tmpdir(), 'leanguard-export-test-'));
  const files = new ExportFiles({ directory, publicBaseUrl:'https://api.example.test', signingSecret:'test-only-'.repeat(8) });
  try { await run(files, directory); } finally { await rm(directory, { recursive:true, force:true }); }
}
test('export writes preserve order, private mode and signed URL binds owner, file and expiry', async () => fixture(async (files,directory) => {
  const output = await files.create('alice'); await output.write('{"a":'); await output.write('1}'); await output.finish();
  const target = path.join(directory,'alice',output.name);
  assert.equal(await readFile(target,'utf8'),'{"a":1}'); assert.equal((await stat(target)).mode & 0o777,0o600);
  const now=Date.now(), url = new URL(files.signedUrl('alice',output.name,now));
  const expires=url.searchParams.get('expires'), signature=url.searchParams.get('signature');
  assert.equal(files.verify('alice',output.name,expires,signature,now),true);
  assert.equal(files.verify('bob',output.name,expires,signature,now),false);
  assert.equal(files.verify('alice',output.name,expires,'a'.repeat(64),now),false);
  assert.equal(files.verify('alice',output.name,expires,signature,now+600000),false);
  assert.equal(files.verify('../alice',output.name,expires,signature,now),false);
  assert.equal(files.verify('alice','../../secret.json',expires,signature,now),false);
}));
test('failed exports are discarded and cleanup expires files without deleting fresh owners', async () => fixture(async(files,directory)=>{
  const failed=await files.create('alice');await failed.write('partial');await failed.discard();
  await assert.rejects(stat(path.join(directory,'alice',failed.name)));
  const stale=await files.create('alice');await stale.write('{}');await stale.finish();
  const fresh=await files.create('bob');await fresh.write('{}');await fresh.finish();
  const old=new Date(Date.now()-exportLifetimeMs-10000);await utimes(path.join(directory,'alice',stale.name),old,old);
  assert.equal(await files.prune(),1);
  const read=await files.read('bob',fresh.name);assert.equal(read.bytes,2);read.stream.destroy();
  await files.removeOwner('bob');await assert.rejects(stat(path.join(directory,'bob',fresh.name)));
}));
test('export service refuses weak secrets and symlink owner directories',async()=>fixture(async(files,directory)=>{
  assert.throws(()=>new ExportFiles({directory,publicBaseUrl:'https://api.example.test',signingSecret:'short'}));
  await mkdir(path.join(directory,'actual'));await symlink(path.join(directory,'actual'),path.join(directory,'alice'));
  await assert.rejects(files.create('alice'),/Invalid export directory/);
}));
