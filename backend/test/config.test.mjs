import {test} from 'node:test';
import assert from 'node:assert/strict';
import {validateConfig} from '../lib/shared/config.js';
const names=['DATABASE_URL','DATABASE_URL_FILE','DATABASE_POOL_SIZE','NODE_ENV','PUBLIC_BASE_URL','PUBLIC_API_URL','EXPORT_SIGNING_SECRET','EXPORT_SIGNING_SECRET_FILE','FIREBASE_AUTH_EMULATOR_HOST','FUNCTIONS_EMULATOR','ALLOWED_ORIGINS'];
function configured(run){
 const before=Object.fromEntries(names.map(name=>[name,process.env[name]]));
 for(const name of names)delete process.env[name];
 Object.assign(process.env,{DATABASE_URL:'postgresql://test@localhost/leanguard_test',NODE_ENV:'production',PUBLIC_BASE_URL:'https://api.example.test',EXPORT_SIGNING_SECRET:'test-only-long-export-secret-123456789'});
 try{run();}finally{for(const name of names){if(before[name]===undefined)delete process.env[name];else process.env[name]=before[name];}}
}
test('startup accepts exact HTTPS origins and requires room for scheduler query connections',()=>configured(()=>{
 for(const size of ['2','10','50']){process.env.DATABASE_POOL_SIZE=size;assert.doesNotThrow(validateConfig);}
 for(const size of ['0','1','51','NaN','2.5','']){process.env.DATABASE_POOL_SIZE=size;assert.throws(validateConfig,/DATABASE_POOL_SIZE/);}
}));
test('startup rejects malformed, credential-bearing, non-origin and insecure production URLs',()=>configured(()=>{
 for(const url of ['https://','http://api.example.test','https://user:pass@api.example.test','https://api.example.test/path','https://api.example.test?token=secret','https://api.example.test/#fragment','ftp://api.example.test']){process.env.PUBLIC_BASE_URL=url;assert.throws(validateConfig,/PUBLIC_BASE_URL/);}
 process.env.NODE_ENV='test';process.env.PUBLIC_BASE_URL='http://127.0.0.1:8080';assert.doesNotThrow(validateConfig);
}));
test('production rejects emulator auth and weak export signing secrets',()=>configured(()=>{
 process.env.FIREBASE_AUTH_EMULATOR_HOST='127.0.0.1:9099';assert.throws(validateConfig,/emulators/);delete process.env.FIREBASE_AUTH_EMULATOR_HOST;
 process.env.EXPORT_SIGNING_SECRET='short';assert.throws(validateConfig,/EXPORT_SIGNING_SECRET/);
}));
