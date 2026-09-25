import test from 'node:test';
import assert from 'node:assert/strict';
import {validateClientWrite, pagination, canonicalDocumentId} from '../lib/validation.js';

const base = {id:'record_1',user_id:'owner',created_at:'2026-09-25T10:00:00.000Z'};
const context = {uid:'owner',pro:false,parentExists:async()=>true,hasExistingPlan:async()=>false};
const save = (table,row,options={},id=canonicalDocumentId(table,row)) => validateClientWrite(table,id,row,{...context,...options});
const weight = {...base,recorded_at:base.created_at,weight_kg:80,source:'manual'};

test('manual records pass and foreign ownership, unknown fields, invalid numbers fail',async()=>{
  assert.equal((await save('weight_entries',weight)).weight_kg,80);
  for(const row of [{...weight,user_id:'other'},{...weight,admin:true},{...weight,weight_kg:NaN},{...weight,weight_kg:19},{...weight,weight_kg:Infinity}]) await assert.rejects(save('weight_entries',row),{code:'invalid_record'});
});
test('identity, creation time, and canonical path are immutable',async()=>{
  await assert.rejects(save('weight_entries',{...weight,id:'changed'},{existing:weight}),{code:'invalid_record'});
  await assert.rejects(save('weight_entries',{...weight,created_at:'2026-09-24T00:00:00Z'},{existing:weight}),{code:'invalid_record'});
  await assert.rejects(save('weight_entries',weight,{},'other'),{code:'invalid_record'});
  assert.equal(canonicalDocumentId('user_profiles',base),'owner');
  assert.equal(canonicalDocumentId('daily_activities',{...base,date:'2026-09-25'}),'2026-09-25');
});
test('clients cannot write AI, entitlement, consent, reminder, or private records',async()=>{
  for(const table of ['weekly_insights','coach_messages','subscription_entitlements','consent_records','reminder_preferences','ai_quota','device_tokens']) await assert.rejects(save(table,base),{code:'server_owned'});
});
test('workout children require every referenced parent in this owner account',async()=>{
  const set={...base,workout_exercise_id:'exercise_row',set_number:1,reps:8,weight_kg:20,completed:true};
  assert.equal(canonicalDocumentId('workout_sets',set),'exercise_row_1');
  assert.equal((await save('workout_sets',set)).reps,8);
  await assert.rejects(save('workout_sets',set,{parentExists:async()=>false}),{code:'invalid_record'});
  await assert.rejects(save('workout_sets',{...set,reps:2.5}),{code:'invalid_record'});
});
test('health import provenance cannot be forged by ordinary CRUD',async()=>{
  await assert.rejects(save('weight_entries',{...weight,source:'health',external_id:'native_1'}),{code:'invalid_record'});
  const activity={...base,date:'2026-09-25',steps:1200,source:'manual'};
  await save('daily_activities',activity);
  await assert.rejects(save('daily_activities',{...activity,source:'health'}),{code:'invalid_record'});
  await assert.rejects(save('daily_activities',{...activity,date:'2026-02-30'}),{code:'invalid_record'});
});
test('expired users preserve and read advanced measurements but cannot add Pro measurements',async()=>{
  const row={...base,recorded_at:base.created_at,waist_cm:90,chest_cm:100};
  await save('body_measurements',row,{pro:true});
  await save('body_measurements',{...row,waist_cm:89},{existing:row});
  await assert.rejects(save('body_measurements',row),{code:'pro_required'});
  await assert.rejects(save('body_measurements',{...row,chest_cm:99},{existing:row}),{code:'pro_required'});
});
test('starter schedule accepts actual mobile day/name entries; manual changes require Pro',async()=>{
  const row={...base,name:'Muscle retention foundation',description:'A starter 3-day plan. Start with a comfortable load and controlled repetitions.',source:'starter',is_active:true,version:1,schedule:[{day:1,name:'Lower body'},{day:4,name:'Upper body'},{day:6,name:'Full body'}]};
  await save('strength_plans',row);
  await assert.rejects(save('strength_plans',{...row,schedule:[{day:8,name:'No'}]}),{code:'invalid_record'});
  const manual={...row,source:'manual'};
  await assert.rejects(save('strength_plans',manual),{code:'pro_required'});
  await save('strength_plans',{...manual,is_active:false},{existing:manual});
  await save('strength_plans',{...row,version:2,schedule:[{day:1},{day:4},{day:6}]},{existing:row});
  await assert.rejects(save('strength_plans',row,{hasExistingPlan:async()=>true}),{code:'pro_required'});
  await assert.rejects(save('strength_plans',{...row,name:'Unlimited personalized plan'}),{code:'pro_required'});
  await assert.rejects(save('strength_plans',{...row,version:4},{existing:row}),{code:'invalid_record'});
});
test('GLP support requires explicit clinician-supervised preference',async()=>{
  const row={...base,enabled:true,clinician_supervised:true,appetite_level:'normal'};
  await save('medication_support_preferences',row);
  await assert.rejects(save('medication_support_preferences',{...row,clinician_supervised:false}),{code:'invalid_record'});
});
test('pagination is bounded and rejects ambiguous or injected query values',()=>{
  assert.deepEqual(pagination({}),{offset:0,limit:500});
  assert.deepEqual(pagination({offset:'500',limit:'50'}),{offset:500,limit:50});
  for(const query of [{limit:'0'},{limit:'501'},{offset:'-1'},{offset:'1000001'},{limit:['1','2']},{offset:'1;DROP TABLE'}]) assert.throws(()=>pagination(query),{code:'invalid_record'});
});
