# PostgreSQL persistence and migration

The VPS backend uses PostgreSQL 16 or 17. Firebase is retained for Authentication and FCM delivery only. The running API and worker never load a Firestore, Firebase Storage or Cloud Functions SDK. Existing Firebase data and deployed Firestore rules remain untouched until an operator completes and verifies any required migration.

## Records and ownership

`backend/migrations/001_records.sql` stores typed records in `app_records`. Its primary key is `(collection, owner, id)`, where `owner` is the unchanged Firebase Authentication UID and `id` is the canonical record key. The `data` JSONB value preserves the Flutter entity fields and the original row UUID. These are distinct for natural keys: a daily record is addressed by its date while its payload `id` remains its original UUID.

The twenty entity collections are:

| Entity | Collection | Canonical key |
| --- | --- | --- |
| UserProfile | user_profiles | UID |
| GoalProfile | goal_profiles | UID |
| HealthConnection | health_connections | apple_health or health_connect |
| MedicationSupportPreferences | medication_support_preferences | UID |
| StrengthPlan | strength_plans | Row UUID |
| Workout | workouts | Row UUID |
| Exercise | exercises | Row UUID |
| WorkoutExercise | workout_exercises | Row UUID |
| WorkoutSet | workout_sets | workout_exercise_id + `_` + set_number |
| DailyTarget | daily_targets | YYYY-MM-DD |
| DailyActivity | daily_activities | YYYY-MM-DD |
| ProteinEntry | protein_entries | Row UUID |
| WeightEntry | weight_entries | UUID for manual; SHA-256(source:external_id) for health imports |
| BodyMeasurement | body_measurements | Row UUID |
| WeeklyInsight | weekly_insights | Deterministic insight hash |
| CoachConversation | coach_conversations | Row UUID |
| CoachMessage | coach_messages | Row UUID |
| ReminderPreference | reminder_preferences | Row UUID |
| SubscriptionEntitlement | subscription_entitlements | pro |
| ConsentRecord | consent_records | Immutable choice UUID |

Supporting owner collections contain proposals, AI request/cache/usage state, current consent, sync state, device tokens and notification deliveries. Global collections have an empty owner and are restricted to deletion tombstones, RevenueCat event deduplication and scheduler state. Unknown collection names are rejected by a SQL constraint.

Composite foreign keys include the owner for workout → plan, workout exercise → workout/exercise, set → workout exercise and coach message → conversation. Cross-account parent references therefore fail even when a parent ID exists for another account. Deleting these parent records cascades to their dependent child records. Deferred foreign keys allow an atomic import to load related records in any order. Unique indexes protect payload IDs, daily dates, set numbers and imported health samples. Query indexes cover owner, collection, time, conversation and scheduler filters.

## Database roles and transactions

Migration credentials own the schema and remain separate from runtime credentials. Run `npm --prefix backend run migrate` with `MIGRATION_DATABASE_URL` or `MIGRATION_DATABASE_URL_FILE`. Then run `npm --prefix backend run provision:runtime` with that migration credential and `DATABASE_RUNTIME_PASSWORD` or its `_FILE` equivalent. The password must be at least 24 characters and is never printed. This creates the `leanguard_runtime` login with `NOINHERIT`, `NOSUPERUSER`, `NOCREATEROLE`, `NOCREATEDB` and `NOBYPASSRLS`.

Only the API and worker receive `DATABASE_URL[_FILE]` for the runtime login. Each transaction selects one fixed non-login role:

- `leanguard_user` is used by generic client CRUD. `SET LOCAL app.uid` binds policies to the verified identity. RLS filters all other owners, private internal collections, and deleted accounts. SQL triggers enforce field allowlists, immutable identities, canonical keys, manual-source writes and Pro gates for advanced measurements/manual plans. HTTP validation adds required fields, types and numeric limits.
- `leanguard_service` is used only by trusted server handlers after authentication, ownership selection and operation-specific validation. It can update protected entitlements, consent, AI counters, reminders and device tokens. A webhook must pass its own secret check before reaching this role.

The public client never gets SQL credentials, chooses a database role, supplies `app.uid`, or calls the adapter directly. In production the startup check rejects a runtime connection that is a superuser, bypasses RLS or owns the records table. The only security-definer helpers answer whether the current UID has an active entitlement or deletion marker; callers cannot pass another UID.

`backend/src/database/postgres.ts` provides the existing record-handler contract using parameterized SQL, with no Firestore connection. Reads, merges, creates, updates, deletes and owner CRUD run in serializable transactions. Serialization/deadlock retries have a bounded backoff. Transaction writes are queued and committed together. `userTransaction` also reads the deletion marker, which prevents an overlapping account deletion and write from silently recreating records. A held PostgreSQL advisory lock permits only one scheduler cycle across workers; per-delivery leases protect retries. Runtime `DATABASE_POOL_SIZE` must be an integer from 2 to 50, leaving a query connection available while the scheduler holds its session lock. `withOwnerLifecycleLock` provides an exclusive per-account export/deletion lock through a separate pool of four sessions, so lifecycle locks cannot exhaust query connections. Contended account operations return a retryable conflict; dropped lock sessions abort the callback signal. Export/deletion callers must honor that signal and clean up partially written files.

## Move existing records without deleting the source

Before production cutover, pause writes to the old backend, retain a private backup of Firestore and Storage, and inventory account counts. Authentication users stay in the same Firebase project with the same UIDs. Do not remove Firestore, its rules, its database, old exports, or Storage objects as part of this code migration.

A trusted operator can convert an authoritative Admin export into UTF-8 NDJSON, one complete record envelope per line:

```json
{"collection":"weight_entries","owner":"existing-firebase-uid","id":"existing-row-uuid","data":{"id":"existing-row-uuid","user_id":"existing-firebase-uid","created_at":"2026-09-18T00:00:00.000Z","recorded_at":"2026-09-18T00:00:00.000Z","weight_kg":80,"source":"manual"}}
```

Use canonical document IDs from the source, not inferred replacement IDs. Convert Firestore Timestamp values to ISO strings. Export server-managed entitlement, consent-state, quota and deletion records too; a user-facing data export alone omits private state and is insufficient for a complete cutover. Never accept migration input uploaded by an ordinary app user.

```sh
# MIGRATION_DATABASE_URL_FILE points to an operator-owned, mode-0600 secret.
node backend/scripts/import-records.mjs /private/path/records.ndjson
# The default validates every row and FK, then rolls back.
node backend/scripts/import-records.mjs /private/path/records.ndjson --apply
```

The importer makes one atomic transaction, accepts identical existing rows on a retry, rejects conflicting records without overwriting them, refuses records for a deleted account, and does not print row content or secrets. It limits input to 512 MiB; larger exports should be split by complete accounts so related records remain together. It does not fetch Firestore automatically or modify the source. Run only against the intended destination and verify per-owner counts, consent state, entitlement reconciliation, sampled logs, and exports before pointing released clients at the VPS. Restore the pre-import PostgreSQL backup to undo a completed import.

Local export files are server-owned and expire; they are not long-term Storage replacements for unrelated legacy objects. Inventory any old avatar/object paths and migrate required objects separately before deleting their source. No source-object deletion has been performed.

## Verification

The integration suite uses a real PostgreSQL instance and a restricted runtime login. It refuses to run unless both test URLs use a database name ending `_test`. It truncates only that dedicated test database between tests.

```sh
# TEST_DATABASE_URL: restricted runtime connection to an isolated *_test DB
# TEST_ADMIN_DATABASE_URL: migration owner connection to the same test DB
npm --prefix backend run test:database
```

Coverage includes all twenty entities' ownership, protected server records, same-owner foreign keys, canonical keys and immutable fields, expired subscription access, concurrent quotas and reminders, consent revocation, health imports, proposal approval, AI fallbacks, export isolation, verified email and revoked-token verification, query pagination, and scheduler advisory locks. Use `pg_dump`/`pg_restore` for full PostgreSQL backup and recovery; include private export volumes only if their short-lived artifacts need preserving.
