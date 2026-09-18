# LeanGuard backend

> **Legacy Supabase reference.** The user selected Firebase after this implementation. The active runtime, deployment steps, endpoint contracts, Firestore/Storage rules and emulator tests are documented in [FIREBASE_SETUP.md](FIREBASE_SETUP.md). Do not deploy this Supabase stack for the current mobile application. The files remain as a migration/schema reference.

The database and Edge Functions are implemented under `supabase/`. The client uses native Supabase Auth and user-scoped PostgREST reads/writes. OpenAI, RevenueCat secret keys and the Firebase service account never enter the app. The only entitlement is `pro`; the Supabase mirror is written only after RevenueCat verification.

## Local setup

Install the Supabase CLI and Docker Desktop, start Docker, and run from the repository root:

```sh
supabase start
supabase db reset
cp supabase/.env.example supabase/.env
supabase functions serve --env-file supabase/.env
```

Populate `.env` privately. Supabase injects `SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` into functions. The public URL and anon/publishable key belong in the Flutter environment template; service credentials do not. Local email confirmation links appear in the local Supabase mail viewer. `supabase status` displays the local service URLs and public app configuration.

The included auth redirect URLs are `com.coralcell.leanguard://login-callback` and `com.coralcell.leanguard://reset-password`. If the native bundle/package differs, change these URLs in the native setup and Supabase Auth URL configuration together. Enable Apple and Google in the Supabase dashboard using the identifiers and redirect URLs documented in the native setup. Email confirmations are enabled, minimum password length is 12, and password recovery uses Supabase's recovery email flow. Configure production SMTP before launch.

## Deploy to an owned Supabase project

```sh
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase db push
supabase secrets set --env-file supabase/.env
supabase functions deploy coach
supabase functions deploy approve-plan
supabase functions deploy sync-entitlement
supabase functions deploy revenuecat-webhook
supabase functions deploy data-export
supabase functions deploy delete-account
supabase functions deploy dispatch-reminders
```

Set secrets using your secret manager or the dashboard rather than sharing populated files. Generate independent random 32-byte webhook and scheduler secrets. Production should use a separate Supabase project, RevenueCat project/app environment and Firebase project from development. Keep `ALLOW_SANDBOX_ENTITLEMENTS=false` in production. Use `true` only on a development backend to exercise sandbox purchases.

`verify_jwt=false` in `config.toml` is intentional: each user endpoint validates the bearer access token with `supabase.auth.getUser(token)` before doing work, which supports current asymmetric signing keys as well as legacy tokens. RLS-scoped clients handle user reads; admin clients are isolated and only perform explicit, verified operations. Webhook and scheduler endpoints authenticate with separate constant-time-compared secrets. An exact `ALLOWED_WEB_ORIGIN` is optional for browser development; arbitrary origins are rejected and native requests need no CORS.

## Database contract

Every domain row has `id uuid`, `user_id uuid` and `created_at timestamptz`; IDs can be client-generated UUIDs for offline replay. All quantities are canonical metric units, independent of display preference. Timestamps are UTC and daily targets use a local calendar `date`. New records must include `user_id`; RLS validates it against the signed-in user.

| Table | Main fields / uniqueness |
| --- | --- |
| `user_profiles` | Unique `user_id`; display_name, units (`metric`/`imperial`), time_zone (IANA), onboarding_completed, analytics_enabled, crash_reporting_enabled, coaching_tone, avatar_path |
| `goal_profiles` | Unique `user_id`; goal (`lose_weight`/`build_strength`/`stay_consistent`), goals text[], target_weight_kg, workouts_per_week, protein_target_g, step_target, equipment/dietary_preferences/allergies/limitations/exercise_preferences text[], training_days (1=Monday), session_minutes |
| `health_connections` | Unique `(user_id,provider)`; provider `apple_health`/`health_connect`, status `connected`/`disconnected`/`denied`/`unavailable`, permissions text[], last_synced_at |
| `medication_support_preferences` | Unique `user_id`; enabled requires clinician_supervised, appetite_level `normal`/`low`/`very_low`, hydration_reminders, check_ins_enabled. No dosage or prescribing model. |
| `strength_plans` | name, description, is_active, version, source `starter`/`manual`/`coach`, schedule JSON array; only one active plan/user |
| `exercises` | User-owned library; name, muscle_group, equipment, instructions text[], image_url |
| `workouts` | plan_id?, name, status `planned`/`in_progress`/`completed`/`skipped`, scheduled_date, started_at, completed_at, duration_seconds, notes |
| `workout_exercises` | workout_id, exercise_id, position, target_sets/reps/weight_kg, rest_seconds, status; unique workout position |
| `workout_sets` | workout_exercise_id, set_number, reps, weight_kg, completed, completed_at, rpe; unique set number per workout exercise |
| `daily_targets` | Unique `(user_id,date)`; steps, protein_g |
| `daily_activities` | Unique `(user_id,date)`; steps, active_energy_kcal, readiness_score?, energy_level?, source |
| `protein_entries` | name, protein_g, meal_type `breakfast`/`lunch`/`dinner`/`snack`, recorded_at |
| `weight_entries` | weight_kg, recorded_at, source `manual`/`apple_health`/`health_connect`, external_id?; source IDs deduplicate health imports |
| `body_measurements` | recorded_at, waist_cm?, chest_cm?, hips_cm?, arm_cm?, thigh_cm?; at least one value required |
| `weekly_insights` | Server written; week_start, snapshot_hash, prompt_version, content JSON |
| `coach_conversations` | title; owned by user |
| `coach_messages` | Server written; conversation_id, role, content, structured_content, safety_classification, prompt_version |
| `reminder_preferences` | kind, title, time_of_day, days_of_week int[], enabled, smart, quiet_start/end, time_zone, delivery `local`/`push` (default local) |
| `subscription_entitlements` | Server written; entitlement_id `pro`, is_active, status, product_id, expires_at, grace_period_expires_at, will_renew, verified_at, is_sandbox, management_url |
| `consent_records` | Append-only: kind, granted, policy_version. Latest created_at controls current consent. Revocation is a new row. |
| `device_tokens` | User-owned; globally unique token, platform `ios`/`android`, updated_at |
| `plan_proposals` | Server written; plan_id/version, bounded changes, rationale, state, expires_at, approved_at |

`ai_requests`, `ai_cache` and `notification_deliveries` are server-managed supporting tables with owner-only reads. `revenuecat_events` is private operational deduplication data. No user can insert/update entitlement mirrors, AI results, usage counters, proposals or notification delivery records. Composite `(parent_id,user_id)` foreign keys prevent a child record from referring to another user's parent, including when the UUID is known. User data remains readable after Pro expiration; gating limits new premium behavior rather than blocking stored data. The database additionally enforces Free's three enabled fixed reminders and waist-only measurement entry. Other presentation/history access rules live in the Flutter feature policy; premium AI adaptation and messaging limits are server enforced.

Singleton upserts should conflict on `user_id`; health connections on `(user_id,provider)`; daily rows on `(user_id,date)`; ordinary records on `id`. Consent records require `insert`, not upsert, because UPDATE is intentionally denied. A duplicate UUID may be treated as an already-completed replay only after confirming it is the user's existing row.

The native repository serializes encrypted snapshots, protects all async reads/writes with account epochs and merges pending edits over incoming pages. Natural keys deduplicate daily imports and sets. `lib/core/domain/entities.dart` provides all 20 requested typed models and canonical JSON serialization. Background Pro health refresh uses `sync_health_activity(p_date,p_steps,p_active_energy,p_source)`: it rechecks Pro, health consent and the connection, atomically preserves manually entered activity, and preserves prior energy if read permission supplied no energy value.

## Function requests

All user endpoints accept POST with the signed-in Supabase bearer token. JSON errors include `error` and `message`. Never retry purchases automatically based on an HTTP failure; refresh RevenueCat and restore through the native SDK.

| Function | Input | Result |
| --- | --- | --- |
| `coach` | `{message, kind:'question'|'weekly'|'adaptation', conversation_id?}` | `{summary,evidence:string[],actions:string[],safety,proposal?,fallback,prompt_version,conversation_id,cached,remaining}` |
| `approve-plan` | `{proposal_id,approved:true|false}` | `{state,proposal_id,plan_id?,version?}`; 409 if expired/stale/ineligible |
| `sync-entitlement` | `{}` | `{entitlement,cached}`; authenticated user's RevenueCat state only |
| `data-export` | `{}` | Complete JSON export of domain rows, with internal cursor pagination; always available on Free |
| `delete-account` | `{confirmation:'DELETE'}` | `{deleted:true}`; requires sign-in within 10 minutes |
| `revenuecat-webhook` | RevenueCat event | `{received:true}`; protected with webhook secret |
| `dispatch-reminders` | `{}` | `{enqueued,sent}`; protected with scheduler secret |

AI consent kind is `ai_processing`. Other consent kinds: `terms`, `privacy`, `health_data`, `analytics`, `crash_reporting`, `notifications`. No health data goes to the model before consent. The request context excludes email, account ID, push token and freeform identifying profile fields. It includes recent weight/strength trends, completed workouts, protein days, steps, readiness, preferences, allergies, limitations and active unstarted exercise targets. Historical conversation context is limited to eight messages and the message length is capped at 2,000 characters. The 28-day snapshot is bounded to prevent excessive context; very high volume logging may be sampled by the stated query limits, which should be expanded with a scheduled aggregate pipeline for very large accounts.

## AI safety and cost controls

Responses requests use strict JSON Schema, `store:false`, a 1,800-token output cap, an 18-second timeout, server-only API keys and explicit prompt version `leanguard-coach-2026-09-18.1`. Default normal model is `gpt-4.1-mini`; only multi-exercise adaptation uses `gpt-4.1`. Both are overrideable by server secret after safety and schema evaluation. No model receives a tool capable of writing a workout plan.

Symptom and medication boundaries first run deterministically. Urgent symptoms return urgent professional-care guidance without consuming AI quota. The model is also instructed to classify safety; non-routine model output is replaced by fixed reviewed copy. Validation rejects ungrounded evidence, excessive actions, unexpected plan IDs, stale plan versions, duplicate exercise changes and changes outside conservative progression limits. Model summaries remain generated text, so prompt rules and output checks are guardrails rather than a clinical guarantee; maintain adversarial safety evaluations and professional review before release.

Free has three questions per UTC calendar month and one summary per UTC calendar week. Pro has up to 100 successful requests per UTC calendar month, with 20/day fair use and six reservations/minute burst protection. PostgreSQL advisory locks reserve quota atomically; repeated in-flight requests cannot double reserve. Cache keys include prompt version, data snapshot, request kind and relevant conversation/request state. Provider timeouts, invalid JSON and failures return deterministic guidance and release the monthly quota; a short cache prevents repeated failed calls. Proactive insights use the same quota path as weekly review calls. The app must request them when refreshing Pro insights; the reminder worker never silently sends health data to OpenAI.

Rapid weight change plus declining comparable strength triggers a nonclinical review signal and suppresses progression. It requires repeated weight logs in each week and repeated sessions of matching exercises, rather than comparing unrelated lifts. The heuristic (>1% change in weekly average weight plus >5% lower comparable estimated strength) is a conservative product flag, not a medical threshold or diagnosis.

An adaptation returns `proposal:{id,plan_id,plan_version,rationale,changes:[{workout_exercise_id,target_weight_kg,target_reps,target_sets}]}`. Increases require two completed sessions meeting all current set targets; recorded high effort or low recent readiness excludes progression. Approval is a database transaction: user ownership and Pro are rechecked, the plan and proposal are locked, and only unstarted workouts may change. Load increase is at most 5%; reductions at most 20%; rep changes at most two; set changes at most one; only one dimension can increase. Plan version increments once. Repeated approvals are idempotent. Current workouts are never modified or interrupted by a paywall.

## RevenueCat setup

Create entitlement `pro` and an offering containing monthly and annual packages. Configure store products at **USD $19.99/month** and **USD $119.99/year** in App Store Connect and Google Play Console. Optionally configure a seven-day introductory trial on the annual product; eligibility and localized prices come from the store, not from a hardcoded client promise. Sign in RevenueCat using the Supabase Auth UUID before purchasing or restoring; do not use email as its app user ID. Enable store server notifications and configure the RevenueCat restore/transfer policy deliberately for your account behavior.

Register `https://YOUR_PROJECT_REF.supabase.co/functions/v1/revenuecat-webhook` and set its Authorization header to `Bearer YOUR_REVENUECAT_WEBHOOK_SECRET`. Include transfer, purchase, renewal, expiration, cancellation, billing and grace events. The handler re-fetches the subscriber rather than trusting event ordering, reconciles both users on transfer, records idempotency only after success and orders mirror updates using RevenueCat's response timestamp. `sync-entitlement` provides a client-triggered reconciliation after login, purchase and restoration (15-second cooldown).

Cancellation does not remove paid access until the period ends. Grace periods retain access; billing issues, trials, expired and paused states are preserved separately. Refunds revoke access. Client purchase restoration must use RevenueCat's SDK, then refresh the server mirror. Existing data and privacy export never require Pro. Account deletion does not cancel Apple/Google billing: show the store management link on the confirmation screen.

## Notifications and storage

The native client owns fixed local reminders. Server push is opt-in through `delivery:'push'`, a registered FCM token and a granted notifications consent record. This avoids duplicate local/server notifications. Set `FCM_SERVICE_ACCOUNT_JSON` to a single-line JSON service account with only FCM send permission. Add the APNs key to Firebase for iOS and supply the platform Firebase config files through the native setup. The function signs short-lived OAuth credentials and calls FCM HTTP v1; notification text is generic and contains no weight, medication, meal or symptom information. Route data is `/today` only.

Create Vault secrets `leanguard_project_url` and `leanguard_reminder_cron_secret` (matching the Edge secret), then run `supabase/schedule-reminders.sql` as the database owner. It installs a one-minute pg_cron job with pg_net. Do not put secret literals in migrations or source control. The scheduler respects IANA time zones, weekday selections, quiet hours, permission withdrawal and current entitlement. Smart reminders suppress already-met walking/protein targets and completed workouts. Quiet-hour reminders are suppressed, not shifted. Database uniqueness, leases, retries and platform collapse identifiers prevent duplicate routine delivery; transport remains at-least-once and is not a clinical alert service. Unregistered FCM tokens are removed. Stale reminders expire after 30 minutes. For a large installation, shard/enqueue work from a database scheduler rather than scanning every user's preferences each minute.

Storage buckets `avatars` and `exports` are private, with MIME and size limits. Avatar access is restricted to `<user_uuid>/...`; exports are server-write-only and user-readable. Account deletion recursively removes both user directories, removes the RevenueCat customer if configured, then deletes Auth, cascading all owned rows. A failure returns a retryable error instead of falsely reporting deletion. The JSON privacy export remains separate from Pro's presentation/report export and has a 20 MB interactive cap; larger accounts need a support-managed streamed export.

## Verification and release work

```sh
node --test supabase/tests/policy.test.mjs
cd supabase/tests
npm ci
npm test
```

Tests run pure safety, trend, cache, entitlement and timezone logic plus actual migrations/RLS/triggers/transactions in embedded PostgreSQL (PGlite). Test-only Auth/Storage scaffolding substitutes for Supabase-owned schemas; `pgcrypto` installation itself is excluded there because random UUID generation is built in. This verifies SQL behavior but does not replace a full `supabase db reset`, native device tests or vendor sandbox integration tests.

Type-check functions with Deno:

```sh
deno check supabase/functions/coach/index.ts supabase/functions/approve-plan/index.ts supabase/functions/sync-entitlement/index.ts supabase/functions/revenuecat-webhook/index.ts supabase/functions/data-export/index.ts supabase/functions/delete-account/index.ts supabase/functions/dispatch-reminders/index.ts
```

Before launch, run vendor sandbox flows on physical iOS and Android devices: email/Apple/Google and recovery callbacks; health denial and revocation; real store trial eligibility, purchase, restoration, grace/billing and expiration; denied notifications, timezone/DST changes, push delivery; export and reauthenticated deletion; model timeout, quota boundary and adversarial symptom/dose questions. Configure support, public privacy/terms URLs, deletion policy, backups and retention, monitoring and alerts. Do not log health bodies, chat, tokens or user identifiers in monitoring. Audit provider retention and contractual settings for your jurisdiction. No vendor credentials, production deployment, store products or live medical validation are supplied by this repository.

Implementation references: [Supabase authenticated user verification](https://supabase.com/docs/reference/javascript/auth-getuser), [Supabase scheduled functions](https://supabase.com/docs/guides/functions/schedule-functions), [OpenAI Structured Outputs](https://developers.openai.com/api/docs/guides/structured-outputs), [GPT-4.1 mini](https://developers.openai.com/api/docs/models/gpt-4.1-mini), [RevenueCat grace periods](https://www.revenuecat.com/docs/subscription-guidance/how-grace-periods-work), and [FCM HTTP v1](https://firebase.google.com/docs/cloud-messaging/send/v1-api).
