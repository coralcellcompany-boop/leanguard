import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

// Explicit project-scoped setup. Uses the signed-in Firebase CLI account and
// a narrow update mask; no passwords, API keys, OAuth clients or billing writes.
delete process.env.DEBUG;
delete process.env.GOOGLE_APPLICATION_CREDENTIALS;
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const require=createRequire(import.meta.url);
const cli=name=>require(path.join(root,'firebase/functions/node_modules/firebase-tools/lib',name));
const project='leanguard-a58ff';
const options={project,projectId:project,projectRoot:root,nonInteractive:true};
const account=cli('auth.js').selectAccount(undefined,root);
if(account)cli('auth.js').setActiveAccount(options,account);
await cli('requireAuth.js').requireAuth(options);
const api=cli('gcp/identityPlatform.js');
const before=await api.getConfig(project);
const previous=before.passwordPolicyConfig?.passwordPolicyVersions?.[0]?.customStrengthOptions??{};
const strength={...previous,minPasswordLength:Math.max(12,previous.minPasswordLength??0)};
const patch={
  signIn:{email:{enabled:true,passwordRequired:true}},
  passwordPolicyConfig:{passwordPolicyEnforcementState:'ENFORCE',passwordPolicyVersions:[{customStrengthOptions:strength}]},
  emailPrivacyConfig:{enableImprovedEmailPrivacy:true},
};
const mask=['signIn.email.enabled','signIn.email.passwordRequired','passwordPolicyConfig.passwordPolicyEnforcementState','passwordPolicyConfig.passwordPolicyVersions','emailPrivacyConfig.enableImprovedEmailPrivacy'].join(',');
await api.updateConfig(project,patch,mask);
const after=await api.getConfig(project);
const minLength=after.passwordPolicyConfig?.passwordPolicyVersions?.[0]?.customStrengthOptions?.minPasswordLength;
const verified=after.signIn?.email?.enabled===true&&after.signIn?.email?.passwordRequired===true&&minLength>=12&&after.passwordPolicyConfig?.passwordPolicyEnforcementState==='ENFORCE'&&after.emailPrivacyConfig?.enableImprovedEmailPrivacy===true;
if(!verified)throw new Error('Authentication settings did not match the requested policy after update.');
console.log(JSON.stringify({project,email_enabled:true,password_required:true,min_password_length:minLength,password_policy_enforcement:after.passwordPolicyConfig.passwordPolicyEnforcementState,email_enumeration_protection:true,verified:true},null,2));
