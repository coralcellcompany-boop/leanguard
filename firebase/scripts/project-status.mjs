import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

// Read-only project inspection using the Firebase CLI's existing signed-in
// account. Never print credentials, account metadata, raw API responses or keys.
delete process.env.DEBUG;
delete process.env.GOOGLE_APPLICATION_CREDENTIALS;
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../..');
const require=createRequire(import.meta.url);
const cli=name=>require(path.join(root,'firebase/functions/node_modules/firebase-tools/lib',name));
const project='leanguard-a58ff';
const options={project,projectId:project,projectRoot:root,nonInteractive:true};
const auth=cli('auth.js');
const account=auth.selectAccount(undefined,root);
if(account)auth.setActiveAccount(options,account);
await cli('requireAuth.js').requireAuth(options);
const status={project};
const failure=error=>({available:false,status:error.status??error.context?.response?.statusCode??null,message:String(error.message??'Unavailable').slice(0,300)});
try{
  const {Client}=cli('apiv2.js');
  const client=new Client({urlPrefix:'https://cloudbilling.googleapis.com',apiVersion:'v1'});
  const result=await client.get(`projects/${project}/billingInfo`,{skipLog:{resBody:true}});
  status.billing={enabled:result.body.billingEnabled===true};
}catch(error){status.billing=failure(error);}
try{
  const buckets=await cli('gcp/storage.js').listBuckets(project);
  status.storage={buckets:buckets.map(bucket=>({name:bucket.name,location:bucket.location}))};
}catch(error){status.storage=failure(error);}
try{
  const config=await cli('gcp/identityPlatform.js').getConfig(project);
  status.auth={configured:true,email_enabled:config.signIn?.email?.enabled===true,password_required:config.signIn?.email?.passwordRequired===true,anonymous_enabled:config.signIn?.anonymous?.enabled===true,min_password_length:config.passwordPolicyConfig?.passwordPolicyVersions?.[0]?.customStrengthOptions?.minPasswordLength??null,password_policy_enforcement:config.passwordPolicyConfig?.passwordPolicyEnforcementState??null,email_enumeration_protection:config.emailPrivacyConfig?.enableImprovedEmailPrivacy===true};
  const {Client}=cli('apiv2.js');
  const idps=new Client({urlPrefix:'https://identitytoolkit.googleapis.com/admin',apiVersion:'v2'});
  const providers=await idps.get(`projects/${project}/defaultSupportedIdpConfigs`,{skipLog:{resBody:true}});
  status.auth.providers=(providers.body.defaultSupportedIdpConfigs??[]).map(provider=>({provider:provider.name?.split('/').at(-1),enabled:provider.enabled===true}));
}catch(error){status.auth=failure(error);}
console.log(JSON.stringify(status,null,2));
