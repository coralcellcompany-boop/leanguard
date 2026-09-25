# LeanGuard Firebase backend (archived deployment)

> **Archived as of 2026-09-25.** The active backend now runs on a Linux VPS using Docker, PostgreSQL and private local export files. Firebase remains only for Authentication and FCM. Use [BACKEND_VPS.md](BACKEND_VPS.md) for current deployment and [POSTGRES_SCHEMA.md](POSTGRES_SCHEMA.md) for isolation and migration. The instructions below describe the previous implementation; do not deploy its Functions, Firestore or Storage stack for the current app. Existing cloud data has not been deleted.

Firebase replaces the original Supabase runtime at the user's request. `supabase/` is a migration reference and its SQL tests are separate from the deployed application. The active backend is `firebase/`; no Supabase URL or service key is needed by Flutter.

Project: **leanguard-a58ff**, project number **124240474112**. Functions region and the intended Firestore regional database location: **europe-west1**. The project alias is committed because a Firebase project ID is public configuration. Secret keys are never committed. Firebase Authentication, Firestore, Storage and FCM are used; RevenueCat remains the sole subscription authority, and OpenAI is called only on the server.

The iOS bundle identifier and Android application/package identifier are both **`com.coralcell.leanguard`**. Register and configure these exact app identifiers in Firebase, Apple/Google authentication, RevenueCat and the stores.

Registered Firebase apps for `com.coralcell.leanguard`:

| Platform | Firebase app ID |
|---|---|
| iOS | `1:124240474112:ios:f9e9950c31bfd2c44d68e5` |
| Android | `1:124240474112:android:1495e65e745cbc5d4d68e5` |

Matching private SDK files and `dart_defines.json` are configured locally. Never overwrite them with the example template when reopening this workspace.

Live provisioning verified on **2026-09-18**: the Firestore API is enabled, the `(default)` Native/Standard database exists in **europe-west1**, and `firebase/firestore.rules` plus the configured indexes were successfully deployed. Email/password authentication is enabled with an enforced **12-character minimum password** and **email enumeration protection**. Existing unrelated authentication settings were preserved. Functions and Storage rules have not been deployed by the backend implementation agent. Billing remains disabled, no Storage bucket exists, and Apple/Google authentication still need provider configuration. These remaining settings and provider credentials must be configured before a production release.

The active apps now both use **`com.coralcell.leanguard`**: iOS `1:124240474112:ios:f9e9950c31bfd2c44d68e5` and Android `1:124240474112:android:1495e65e745cbc5d4d68e5`. The two temporary `com.leanguard.app` registrations created during setup were removed with Firebase's recoverable operation; their restoration window ends **2026-10-18 at approximately 12:15 UTC**. Readback confirmed the new apps remain active and their shared API-key IDs are unchanged. The guarded one-time script is `firebase/scripts/remove-obsolete-apps.mjs` (validation only by default). Firebase documents that app removal preserves API keys and OAuth clients; restoration is available through Project settings → Apps pending deletion during the 30-day window. See [Firebase app removal and restoration](https://support.google.com/firebase/answer/7047853).

## Provisioning and deployment

1. Install Node 22, Java 21 (recommended for current emulator tooling), Flutter, Firebase CLI and FlutterFire CLI. Run `npm ci --prefix firebase/functions`. The lockfile pins tested dependencies. The server runtime is Node 22 even if the local machine uses another version.
2. Sign in with `firebase login`, verify access with `firebase projects:list`, and select `leanguard-a58ff`. Enable the Blaze billing plan for deployed Functions, Scheduler and Storage. Add billing alerts; alerts do not cap costs. Create the **default Firestore database in Native mode in europe-west1 before loading records**. Database location is fixed after creation. Enable Firebase Authentication and create a Storage bucket in the intended European region.
3. Email/Password is already enabled in this project, with a 12-character minimum for new passwords and enumeration protection. The project-scoped `firebase/scripts/configure-auth.mjs` can reapply these settings through a narrow Identity Toolkit update mask; it preserves other settings and never prints credentials. See the official [password policy](https://docs.cloud.google.com/identity-platform/docs/password-policy) and [enumeration protection](https://docs.cloud.google.com/identity-platform/docs/admin/email-enumeration-protection) documentation. Enable Apple and Google in Firebase Authentication when their provider credentials are available. Configure provider IDs, Apple signing keys/return URLs, Android SHA-1/SHA-256 fingerprints, iOS reversed client ID and authorized domains as described in `MOBILE_SETUP.md`. Use real registered bundle IDs and package names. Configure password reset action links and your support/privacy URLs.
4. Register iOS/Android apps and run `flutterfire configure --project=leanguard-a58ff` using the package IDs in the native project. Keep generated mobile Firebase config; it contains public app identifiers, not Admin or OpenAI secrets. Do not embed any service account JSON in the application. Production uses Application Default Credentials for Firebase Admin.
5. Register App Check with App Attest/DeviceCheck on Apple and Play Integrity on Android. Enable Firestore/Storage App Check enforcement after testing devices. Every production HTTPS function independently verifies `X-Firebase-AppCheck`; Firebase ID tokens are verified with revocation checking. Only the actual local Functions emulator bypasses App Check. Debug tokens belong only in a development project.
6. From a trusted terminal run `bash firebase/scripts/configure-secrets.sh leanguard-a58ff`. It prompts separately for `OPENAI_API_KEY`, `REVENUECAT_SECRET_KEY`, and `REVENUECAT_WEBHOOK_SECRET`; no secret appears in a command argument. Use restricted project keys and a random webhook secret of at least 24 characters; rotate them using Secret Manager. See [Firebase secret parameters](https://firebase.google.com/docs/functions/config-env).
7. Copy `firebase/functions/.env.example` to `.env.leanguard-a58ff` if changing public server parameters. Defaults are `OPENAI_COACH_MODEL=gpt-4.1-mini`, `OPENAI_REASONING_MODEL=gpt-4.1`, `ALLOW_SANDBOX_ENTITLEMENTS=false`. Test store sandbox in a separate Firebase project with the sandbox flag enabled. A production sandbox purchase does not grant paid access by default.
8. Run tests below. Deploy rules/indexes first with `firebase deploy --only firestore:rules,firestore:indexes,storage --project leanguard-a58ff`. Deploy Functions only after secrets, billing, providers and App Check are configured: `firebase deploy --only functions:leanguard --project leanguard-a58ff`. The scheduled reminder trigger is created during Functions deployment. Do not manually create an unauthenticated scheduler HTTP endpoint.
9. Configure TTL for `account_deletions.expires_at`. It retains a minimal deletion marker for at least 24 hours so a previously issued ID token cannot recreate deleted Firestore data. Grant the Functions service account permission to sign its own export URLs (`iam.serviceAccounts.signBlob`, usually via Service Account Token Creator on that service account). Apply `firebase/storage-lifecycle.json` to the app's bucket through Cloud Storage lifecycle settings: it deletes only the `exports/` prefix after one day, preserving avatars. Signed export URLs expire after ten minutes; account deletion also removes saved export objects.
10. Run real-device store sandbox purchases, restores, cancellation/grace/expiry events, Apple Health/Health Connect permission tests, FCM delivery, and App Check enforcement before release. Local emulators cannot validate store billing, APNs, device attestation, or real health APIs.

## RevenueCat and store products

Create entitlement **`pro`** and attach monthly and annual subscription products. Set the US base prices to **$19.99/month** and **$119.99/year**, with an optional **seven-day introductory annual free trial** and correct store eligibility. App Store / Play localized prices and trial eligibility are read from RevenueCat offerings, never inferred from display text. Configure an offering with monthly and annual packages and add the iOS/Android **public SDK keys** to Flutter build configuration. The secret RevenueCat API key stays in Secret Manager.

Use the Firebase Authentication UID as RevenueCat `app_user_id`. Configure RevenueCat webhook URL:

`https://europe-west1-leanguard-a58ff.cloudfunctions.net/revenuecatWebhook`

Set its Authorization header to `Bearer YOUR_REVENUECAT_WEBHOOK_SECRET` (the same secret stored above). The server verifies the header using a constant-time comparison, deduplicates completed event IDs, and fetches the current subscriber record from RevenueCat for each affected account. Cancellation retains access through the paid period. Grace periods, billing issues, trials, refunds, expiry, and transfer events are represented explicitly. Server verification timestamps prevent delayed reconciliation from overwriting newer state. Restoration calls RevenueCat's mobile restore API and then `syncEntitlement`. Existing user records remain readable after expiration.

## HTTPS contract

All app endpoints use POST JSON at `https://europe-west1-leanguard-a58ff.cloudfunctions.net/FUNCTION_NAME`, with `Authorization: Bearer FIREBASE_ID_TOKEN` and `X-Firebase-AppCheck: APP_CHECK_TOKEN`. Responses are JSON. Errors have `{error,message}` and appropriate 400/401/403/404/409/429/503 status. Responses never log input messages, health records, user IDs or provider credentials. HTTPS functions use no cookie authentication and do not enable cross-origin browser requests.

| Function | Request | Result |
|---|---|---|
| `coach` | `{message,kind:'question'|'weekly'|'adaptation',conversation_id?}` | `{summary,evidence:[],actions:[],safety,proposal?,fallback,prompt_version,conversation_id,cached,remaining}` |
| `approvePlan` | `{proposal_id,approved:true|false}` | `{state,proposal_id,plan_id?,version?}` |
| `syncEntitlement` | `{}` | Authoritative `subscription_entitlements/pro` row; verification limited to once per 15 seconds |
| `recordConsent` | `{row:{id,user_id,kind,granted,policy_version}}` | Append-only audit row with trusted, monotonic server `created_at` |
| `saveReminder` | `{row:ReminderPreference}` | Saved row; transaction enforces Free enabled cap of three and Pro smart/quiet hours |
| `deleteReminder` | `{id}` | `{deleted:true}` |
| `syncHealthActivity` | `{date,steps:null|int,active_energy:null|number,source,background?:bool,weight?:{kg,external_id,recorded_at}}` | `{activity:null|DailyActivity,weight_imported:bool,synced:true}` |
| `dataExport` | `{}` | `{schema_version,exported_at,user_id,tables}`; exports over 20 MiB stream to private Storage and return a ten-minute `download_url`; one export/minute |
| `deleteAccount` | `{confirmation:'DELETE'}` | `{deleted:true,message}`; requires authentication in last ten minutes |

`dispatchReminders` runs every five minutes through Cloud Scheduler, checks consent, local timezone and quiet hours, suppresses smart nudges for completed goals, and sends generic FCM messages. Delivery IDs and leases reduce duplicates; retry of a send whose network response is lost can still result in duplicate OS delivery, so clients use the delivery ID/collapse key. Local notifications are scheduled on the device; a reminder selects either local or push delivery. Notification text never contains a weight, meal, medication or health status. Routes are fixed to `/today`.

Health imports require current server-side health consent and a connected provider (`apple_health` or `health_connect`). Free foreground imports permit steps and weight. Pro is checked for active energy and a declared background refresh. OS background work is Pro-gated in Flutter; a server cannot independently distinguish an authenticated foreground call from a background process on the same device. Null steps skip the activity write; null energy preserves existing energy; a manual activity record takes precedence. Weight imports are idempotent by SHA-256 of `source:external_id`.

## Firestore models and access

All records are below `users/{FirebaseUID}/{snake_case_collection}/{documentId}`. Every client-visible record contains `id`, `user_id`, `created_at`. Timestamps use ISO UTC strings for native compatibility; internal expiry comparisons also use numeric milliseconds. Canonical units are kg, cm, grams, steps, seconds and kcal. Dates are `YYYY-MM-DD`.

The 20 product collections are `user_profiles`, `goal_profiles`, `health_connections`, `medication_support_preferences`, `strength_plans`, `workouts`, `exercises`, `workout_exercises`, `workout_sets`, `daily_targets`, `daily_activities`, `protein_entries`, `weight_entries`, `body_measurements`, `weekly_insights`, `coach_conversations`, `coach_messages`, `reminder_preferences`, `subscription_entitlements`, and `consent_records`. Typed mobile models are in `lib/core/domain/entities.dart`; field allowlists and numeric limits are in `firebase/firestore.rules`.

Singleton profile/preference document IDs are the UID. Health connections use the provider ID; daily rows use the date; workout sets use `workout_exercise_id_setNumber`; imported weights use the source/external ID hash. Other rows use their `id`. Stored row IDs are preserved across retries, including singleton original UUIDs. Entitlement document ID is `pro`.

Rules deny anonymous access, cross-user reads/writes, ownership reassignment, unknown fields, invalid numeric ranges, and workout child references outside the user's namespace. Existing advanced measurements remain readable and can retain unchanged advanced fields after expiry. Consent, reminders, AI results, proposals, quotas and entitlements are server-written. Private server collections include `consent_state`, `ai_usage`, `ai_cache`, `server_state`, and global `revenuecat_events`. `consent_state` is updated in the same transaction as the append-only audit record so retries and simultaneous consent changes cannot undo revocation. No client can grant itself an entitlement or reset its allowance.

Storage permits owners to read/write bounded image uploads under `users/{uid}/avatars/`. Exports at `exports/{uid}/` are server-created and owner-readable. Both Storage and Firestore deny access during account deletion. Deletion removes RevenueCat's subscriber record, private Storage objects, Firestore descendants and Firebase Auth, while a minimal expiring marker prevents stale token writes. An active store subscription must still be cancelled in Apple/Google settings; deleting an app account cannot cancel billing in the store.

## AI policy and reliability

The Responses API uses a strict JSON Schema, `store:false`, a versioned prompt, and an 18-second provider timeout. See [OpenAI structured outputs](https://developers.openai.com/api/docs/guides/structured-outputs). The inexpensive model handles ordinary questions and summaries; the stronger model is selected only for complex plan reasoning with at least four candidate exercises. No model has database write tools. Untrusted messages/logs cannot select another account or plan. Evidence must match supplied in-app facts exactly.

Free permits one summary per UTC week plus three questions per UTC calendar month. Pro permits 100 total messages per UTC calendar month, at most 20 in a rolling day and six reservation attempts per minute. A Firestore transaction reserves quota, checks entitlements and de-duplicates the same in-flight snapshot. Failed provider calls are refunded; a five-minute fallback cache prevents retry storms. Successful repeated snapshots are cached for 24 hours (weekly reviews seven days, keyed to the UTC week). Warning signs return deterministic medical referral text before consuming AI quota. This safety classification is a conservative English-language rule layer plus model policy, not a validated medical triage system.

Rapid weight loss plus declining comparable strength raises a review flag only with repeated observations in both seven-day windows. Internal thresholds (>1% weight change and >5% estimated strength decline) are nonclinical heuristics, not a diagnosis or promise of muscle measurement. The app escalates pain, fainting, dehydration, severe weakness and similar warnings, never diagnoses, prescribes or changes GLP-1 dosage.

Suggested plan changes affect only unstarted exercises and require explicit approval. The approval transaction rechecks ownership, entitlement, expiration, plan version and workout state. Bounds allow a load increase up to 5%, decrease up to 20%, reps ±2 (1–30), sets ±1 (1–6), with only one dimension increasing. Increases additionally require two completed comparable sessions meeting current targets with comfortable logged effort. Sparse data yields no proposal. This is a conservative product heuristic, not a medical training prescription.

## Validation commands

```sh
npm ci --prefix firebase/functions
npm --prefix firebase/functions test
npm --prefix firebase/functions run test:emulator
npm --prefix firebase/functions run test:http
```

Use a **demo-** project for tests so missing emulated services cannot fall through to a live project. Tests exercise Firestore and Storage Rules, tenant ownership, parent references, protected entitlements, grace/expiry and restoration normalization, transactional concurrent quota limits, caching/refunds, consent revocation, reminder caps, manual/health merge behavior, approved/stale proposals, safety escalation and provider failure fallbacks. No real OpenAI, RevenueCat, APNs, Play purchase or health-provider credentials are used by these tests. For a full Functions emulator run, copy `.secret.local.example` to `.secret.local` and include `functions` in the emulator list. Placeholder secrets deliberately cannot make real paid provider calls.

The HTTP smoke test is `node --test firebase/functions/test/http.test.mjs` inside an isolated Functions emulator session. The supplied runner copies example local parameters if absent, uses a `demo-` project, and removes unrelated credentials/debug variables from the emulator environment. It uses Android Studio's bundled Java21 on macOS when available, otherwise your `JAVA_HOME`. It signs up an emulator account, verifies actual ID-token authentication, exercises safety/consent/ownership errors and exports only that account's records. It does not send a routine request to a provider. Use the pinned Firebase CLI15 from the package: older CLI14 invokes the removed `functions.config()` API and cannot run FunctionsSDK7. Production dependencies are security-audited separately from local CLI tooling; a patched UUID override is used for the Storage transport.
