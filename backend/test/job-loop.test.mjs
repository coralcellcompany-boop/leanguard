import { test } from 'node:test';
import assert from 'node:assert/strict';
import { setTimeout as delay } from 'node:timers/promises';
import { startJobLoop } from '../lib/shared/job-loop.js';

test('scheduler does not overlap work and shutdown waits for current job',async()=>{
  let release, runs=0, active=0, maximum=0;
  const gate=new Promise(resolve=>release=resolve);
  const loop=startJobLoop({intervalMs:5,run:async()=>{runs++;active++;maximum=Math.max(maximum,active);await gate;active--;}});
  await delay(20);assert.equal(runs,1);assert.equal(maximum,1);
  let stopped=false;const stop=loop.stop().then(()=>stopped=true);
  await delay(5);assert.equal(stopped,false);release();await stop;
  await delay(20);assert.equal(runs,1);
});
test('scheduler records successful cycles and retries a failure without logging details',async()=>{
  let count=0,failures=0;
  const loop=startJobLoop({intervalMs:5,now:()=>1234,onFailure:()=>failures++,run:async()=>{count++;if(count===1)throw new Error('private-details');}});
  await delay(30);await loop.stop();assert.equal(failures,1);assert.ok(count>=2);assert.equal(loop.lastSuccess,1234);
});
