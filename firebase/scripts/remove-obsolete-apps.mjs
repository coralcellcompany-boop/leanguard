import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

// One-time, explicitly authorized cleanup of this session's obsolete app IDs.
// Default is validation only. --apply always uses recoverable (30-day) removal.
// This script never calls API-key, OAuth-client, database or project deletion.
// https://firebase.google.com/docs/reference/firebase-management/rest/v1beta1/projects.iosApps/remove
// https://firebase.google.com/docs/reference/firebase-management/rest/v1beta1/projects.androidApps/remove
delete process.env.DEBUG;
delete process.env.GOOGLE_APPLICATION_CREDENTIALS;
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../..');
const require = createRequire(import.meta.url);
const cli = name => require(path.join(root, 'firebase/functions/node_modules/firebase-tools/lib', name));
const project = 'leanguard-a58ff';
const options = { project, projectId: project, projectRoot: root, nonInteractive: true };
const auth = cli('auth.js');
const account = auth.selectAccount(undefined, root);
if (account) auth.setActiveAccount(options, account);
await cli('requireAuth.js').requireAuth(options);
const { Client } = cli('apiv2.js');
const client = new Client({ urlPrefix: 'https://firebase.googleapis.com', apiVersion: 'v1beta1' });
const pairs = [
  { collection: 'iosApps', field: 'bundleId', old: '1:124240474112:ios:6e2137845c00fb6b4d68e5', current: '1:124240474112:ios:f9e9950c31bfd2c44d68e5' },
  { collection: 'androidApps', field: 'packageName', old: '1:124240474112:android:373a4e2056feda884d68e5', current: '1:124240474112:android:1495e65e745cbc5d4d68e5' },
];
// The CLI client mutates request options, so every call must receive a fresh object.
const requestOptions = () => ({ skipLog: { reqBody: true, resBody: true } });
const get = async resource => (await client.get(resource, requestOptions())).body;
const resource = (pair, id) => `projects/${project}/${pair.collection}/${id}`;
const describe = app => ({ app_id: app.appId, package: app.bundleId ?? app.packageName, state: app.state, expire_time: app.expireTime ?? null });
const verified = [];
// Verify BOTH replacements before validating or mutating either obsolete app.
for (const pair of pairs) {
  const old = await get(resource(pair, pair.old));
  const current = await get(resource(pair, pair.current));
  if (old.appId !== pair.old || old[pair.field] !== 'com.leanguard.app') throw new Error('Obsolete registration does not match the exact authorized ID/package.');
  if (current.appId !== pair.current || current[pair.field] !== 'com.coralcell.leanguard' || current.state !== 'ACTIVE') throw new Error('Replacement app is not active with the required package.');
  if (!['ACTIVE', 'DELETED'].includes(old.state)) throw new Error('Unexpected obsolete registration state.');
  if (old.state === 'ACTIVE' && !old.etag) throw new Error('Missing app ETag; refusing unguarded removal.');
  verified.push({ pair, old, current });
}
for (const item of verified) {
  if (item.old.state === 'DELETED') continue;
  await client.post(`${resource(item.pair, item.pair.old)}:remove`, {
    allowMissing: false, validateOnly: true, immediate: false, etag: item.old.etag,
  }, requestOptions());
}
console.log(JSON.stringify({ project, validated: verified.map(({ old, current }) => ({ obsolete: describe(old), replacement: describe(current) })) }, null, 2));
if (!process.argv.includes('--apply')) process.exit(0);
for (const item of verified) {
  if (item.old.state === 'DELETED') continue;
  let operation = (await client.post(`${resource(item.pair, item.pair.old)}:remove`, {
    allowMissing: false, validateOnly: false, immediate: false, etag: item.old.etag,
  }, requestOptions())).body;
  for (let attempt = 0; !operation.done && attempt < 30; attempt++) {
    if (!operation.name?.startsWith('operations/')) throw new Error('Unexpected operation resource. Verify Firebase app state manually.');
    await new Promise(resolve => setTimeout(resolve, 1000));
    operation = await get(operation.name);
  }
  if (!operation.done || operation.error) throw new Error(`Removal operation incomplete or failed for ${item.pair.collection}. Verify app state manually.`);
}
const result = [];
for (const item of verified) {
  const old = await get(resource(item.pair, item.pair.old));
  const current = await get(resource(item.pair, item.pair.current));
  if (old.state !== 'DELETED' || Date.parse(old.expireTime) <= Date.now()) throw new Error('Expected recoverable deleted state and future expiration.');
  if (current.state !== 'ACTIVE' || current.apiKeyId !== item.current.apiKeyId) throw new Error('Replacement app state or shared API-key ID unexpectedly changed.');
  result.push({ removed: describe(old), replacement: describe(current), replacement_api_key_id_unchanged: true });
}
console.log(JSON.stringify({ project, recoverable_removal_verified: result }, null, 2));
