# Standalone LeanGuard backend

The active backend is `backend/`: Node 22, Express, PostgreSQL 17, and a separate Node worker. Firebase supplies **Authentication and Cloud Messaging only**. App data, AI, subscriptions, jobs and exports do not use Firestore, Cloud Functions, Firebase Storage, App Check or Cloud Scheduler. The archived `firebase/functions/` and `supabase/` directories are migration references; they are not deployed by the current configuration.

No VPS has been supplied or deployed. These instructions prepare a reviewable deployment for a Linux VPS that you control. Use an EU VPS and an EU backup destination if you want to retain the original European hosting preference; the source code does not choose or certify a hosting jurisdiction.

## Credentials and domains

Obtain a domain such as `api.your-domain.com` and point its A/AAAA records to the VPS. Allow inbound TCP 80/443 for Caddy and SSH from your administrator IPs; do not expose PostgreSQL or the API port. An incorrect AAAA record can prevent certificate issuance.

Keep Firebase project `leanguard-a58ff` and native bundle/application ID `com.coralcell.leanguard`. Email/password is already enabled with password policy and enumeration protection. Configure Google and Apple sign-in, APNs credentials and FCM separately as described in [MOBILE_SETUP.md](MOBILE_SETUP.md) and [FIREBASE_SETUP.md](FIREBASE_SETUP.md).

For the VPS, create a dedicated service account with the Firebase Authentication administration and FCM send permissions required for token revocation checks, account deletion and push delivery. Do not grant Owner, Editor, Firestore or Storage roles. Place its downloaded JSON in the secret file below; never put this Admin credential in Flutter, Git, an image or public hosting. A Linux service can instead use an appropriately configured workload identity/ADC environment; adapt the provided file-based deployment before using that option.

Create an OpenAI server API key and a RevenueCat secret API key. Configure RevenueCat entitlement `pro`, offering/package identifiers matching the app, and store products for $19.99/month and $119.99/year; trial eligibility remains store-controlled. Configure the webhook URL `https://api.your-domain.com/v1/revenuecatWebhook` with Authorization header `Bearer <value of revenuecat_webhook_secret>`. Never supply these secret keys through Dart defines. Use a separate staging database/RevenueCat project for sandbox testing.

## Docker Compose deployment

Install Docker Engine with Compose v2 on a maintained Linux distribution. Budget at least 2 GB RAM for this small initial installation; capacity and provider costs depend on traffic. Copy the repository to a private directory on the VPS, then:

```sh
cd backend
cp -n .env.example .env
# Edit .env: real API_DOMAIN, ACME_EMAIL and explicit web origins if needed.
node scripts/prepare-secrets.mjs
```

The generator refuses to overwrite an existing `secrets/` directory. It creates random database passwords, a 32-byte export signing secret and a webhook secret without printing them. Supply `secrets/firebase_admin.json`, `secrets/openai_api_key` and `secrets/revenuecat_secret_key` through your secure deployment process. Keep `secrets/` mode **0700**. Files may be **0444** inside that private directory so distinct non-root containers can read their selected read-only secret mounts; other host users cannot traverse the parent. Do not move those files into a public or searchable parent directory. Empty provider-key files permit non-provider features to run but AI and subscription verification will fall back or fail until real keys are installed.

```sh
docker compose --env-file .env config --quiet
docker compose --env-file .env build --pull
docker compose --env-file .env up -d
docker compose --env-file .env ps
curl --fail https://api.your-domain.com/health/ready
```

Compose starts private PostgreSQL, applies migrations using the database owner in a short-lived container, provisions `leanguard_runtime`, then starts the API, worker and Caddy. The API/worker **never** receive the database owner URL. They connect as a restricted `NOINHERIT`, non-superuser login; each transaction selects a narrowly scoped database role. See [POSTGRES_SCHEMA.md](POSTGRES_SCHEMA.md) for RLS, composite owner references and the mapping of all models.

API, worker and proxy run as UID/GID 10001 with read-only roots, dropped capabilities and resource limits. Caddy listens on unprivileged container ports mapped to host 80/443. PostgreSQL has no published host port and is on an internal network. API/worker use a separate network for outbound Firebase/OpenAI/RevenueCat requests. Certificates and database data persist in named volumes. Private export files use a shared volume readable only by the application; no static web server serves that directory.

Set `BACKEND_BASE_URL` in the public Flutter configuration to the **origin only**, for example `https://api.your-domain.com` (no `/v1`, user info, query or fragment). Rebuild mobile binaries with that configuration. Do not enable `ALLOW_SANDBOX_ENTITLEMENTS` in production. Caddy is the single trusted proxy; the API port must remain private when `TRUST_PROXY_HOPS=1`.

Check `docker compose logs --tail=100 api worker migrate` for generic health events. Application logs intentionally omit identities, health values, credentials and request URLs. Caddy access logging is disabled because export URLs contain short-lived signatures. Its global runtime-log filter also removes request objects, URI/header fields and identity fields from proxy errors while retaining status, duration and error IDs. Access logging alone does not protect error logs; keep this filter when changing proxy configuration and do not enable credential/debug logging. Add infrastructure alerts for unhealthy containers, worker heartbeat older than ten minutes, disk capacity, backup failure, elevated error counts and certificate expiry. Configure your log/metric agent to keep this redaction boundary. A Docker healthcheck reports a problem; Docker Compose does not automatically restart a merely unhealthy running container.

### Optional landing page on the same VPS

Use the existing `../landing/dist` build and point `LANDING_DOMAIN` to this VPS. This does not modify the landing source or its separate Sites deployment. Enable the supplied overlay:

```sh
docker compose --env-file .env -f compose.yml -f compose.landing.yml config --quiet
docker compose --env-file .env -f compose.yml -f compose.landing.yml up -d
```

The same Caddy instance terminates HTTPS for both domains, serves the read-only static landing build, and proxies the API. Do not start the landing project's standalone Caddy container on the same host ports. Use both Compose files for later updates while the overlay is enabled; mount only public `dist/`, never the repository or secrets. This optional example is configuration-validated; public DNS and certificate issuance require real domains.

## Plain Node on Linux

Install Node 22, PostgreSQL 17 and Caddy through maintained distribution/vendor packages. Create an unprivileged `leanguard` system account, an owner-controlled application directory `/opt/leanguard/backend`, `/etc/leanguard/secrets`, and `/var/lib/leanguard/exports` writable by that account. Keep source/dependencies read-only to the service user. Restrict PostgreSQL to a Unix socket or loopback/private address.

```sh
cd /opt/leanguard/backend
npm ci --ignore-scripts
npm run build
# Supply protected MIGRATION_DATABASE_URL_FILE and DATABASE_RUNTIME_PASSWORD_FILE
# for these two one-time administrative commands only.
npm run migrate
npm run provision:runtime
```

Create `/etc/leanguard/backend.env` from `backend/deploy/backend.env.example`. The runtime database URL must authenticate `leanguard_runtime`, never `postgres` or a table owner. Store secret files as root:leanguard 0640 under a root:leanguard 0750 directory. Use localhost in database URLs for a local database. Install the included `leanguard-api.service` and `leanguard-worker.service` in `/etc/systemd/system`, check the Node executable path, then run `systemctl daemon-reload` and enable/start both services. Runtime entry points are `node lib/index.js` and `node lib/worker.js`; no Firebase CLI is needed on the production server.

For the host Caddy service, use a site block for your real API domain with `reverse_proxy 127.0.0.1:8080`, equivalent headers/timeouts to `backend/deploy/Caddyfile`, and no access-log directive. Preserve the global runtime-log filter from that file as well; upstream errors otherwise include request URLs and metadata. The included Docker Caddyfile uses container DNS and high ports, so do not copy it unchanged into the host service. Keep the API bound to `127.0.0.1`; only Caddy should be public.

## HTTP and background contract

Authenticated endpoints use `Authorization: Bearer <Firebase ID token>`. Email verification and revocation are checked server-side. Owner IDs come from that token, never from URL selection or user-supplied claims. The backend rejects malformed fields, cross-owner references and direct writes to entitlement, consent, AI and reminder records. Client CRUD also runs under PostgreSQL RLS.

| Method/path | Purpose |
| --- | --- |
| GET `/v1/records/:table?offset=0&limit=500` | Owned records in deterministic creation-time/ID order; returns `{ "records": [] }` |
| PUT `/v1/records/:table/:id` | Validated row upsert; preserves identity on natural-key offline reconciliation |
| POST `/v1/coach`, `/v1/approvePlan` | Quota-limited coaching and explicit proposal approval |
| POST `/v1/syncEntitlement` | Verify RevenueCat entitlement; clients cannot grant Pro |
| POST `/v1/recordConsent` | Append consent and update current consent transactionally |
| POST `/v1/saveReminder`, `/v1/deleteReminder` | Tier-aware reminder changes |
| POST `/v1/syncHealthActivity` | Consent-aware, idempotent health ingestion |
| PUT `/v1/device-tokens`, DELETE `/v1/device-tokens/:id` | Owned hashed FCM-token registration/removal |
| POST `/v1/dataExport`, `/v1/deleteAccount` | All-plan export; recent-auth account deletion |
| POST `/v1/revenuecatWebhook` | Authenticated RevenueCat event handling |
| GET `/v1/exports/:uid/:file` | Ten-minute HMAC-signed private export download |
| GET `/health/live`, `/health/ready` | Liveness and database-readiness checks |

Requests are limited to 32 KB uncompressed JSON; HTTP headers, ingress rates, SQL waits and provider timeouts are bounded. Only one account export runs per API process, with an additional one-per-minute owner quota. Large exports stream to a private file after a 20 MiB inline threshold. Download URLs are bearer capabilities valid for ten minutes and must never be logged or shared publicly. The worker deletes files after 24 hours and respects account-deletion tombstones.

The worker wakes every five minutes, holds a PostgreSQL advisory lease across instances, prunes expired temporary state/files and sends eligible privacy-safe FCM reminders. Proactive AI reviews are requested by the app on resume when consent, tier and freshness conditions permit; subscription reconciliation uses app requests and RevenueCat webhooks. Local reminders remain native. Delivery depends on OS permissions, device connectivity, APNs/FCM configuration and valid tokens; the app does not guarantee exact-time remote delivery. Shutdown allows in-flight work up to 30 seconds. Missed/cancelled jobs are retried by later worker cycles according to their persisted state.

Export and deletion are serialized per owner using a separate PostgreSQL advisory-lock connection. A conflicting request receives `409 account_busy` and can be retried after the current operation finishes. This prevents deletion from racing an export that creates another private file; an interrupted lock aborts its operation rather than silently continuing without ownership protection.

## Updates, backups and rotation

Back up PostgreSQL before each migration and on a scheduled basis. Use encrypted off-host backups with tested retention and restoration. `pg_dump -Fc` from the private database is suitable for an initial backup procedure; exported data contains sensitive health records. Keep backup files in a private directory, exclude them from Git, and test restoration into a separate database. Export files are temporary and can be omitted from long-term backups; signing keys and service credentials need a separate secured recovery process.

For code updates: run tests, back up, rebuild images, run the one-shot migration service, then recreate API/worker/proxy. Never use `docker compose down -v` on an installation whose data you want to keep. Database migrations are forward changes; rollback may require restoring the matching pre-upgrade database. Preserve former source records during any migration. The dry-run-first NDJSON importer is documented in [POSTGRES_SCHEMA.md](POSTGRES_SCHEMA.md).

Rotate credentials by securely replacing their mounted files, applying the corresponding provider/database rotation, and recreating the affected containers. `_FILE` secrets are cached per process. For database rotation, update the runtime password and both runtime URL/password files together using the administrative provisioning script; the initial PostgreSQL password file alone does not change an existing database role. Export-signing rotation invalidates old download URLs, while users can request new exports. Keep old API instances drained before removing old provider credentials.

## Verification and remaining acceptance

```sh
npm ci --prefix backend
npm --prefix backend test
# Set isolated *_test database URLs; never use a production DB for tests.
npm --prefix backend run test:database
npm --prefix backend run test:http
# After building leanguard-caddy:verification:
node backend/scripts/caddy-log-smoke.mjs
docker build -t leanguard-api:verification backend
docker compose --project-directory backend --env-file backend/.env.example config --quiet
```

The database suite requires `TEST_DATABASE_URL` (restricted runtime login) and `TEST_ADMIN_DATABASE_URL` (owner) and includes destructive cleanup guarded by a `_test` database name. Provision/migrate that isolated database first. HTTP tests start only Firebase **Auth** emulator for project `demo-leanguard` using pinned CLI 15.30.2 and use real Express requests plus PostgreSQL. The runner strips provider/service credentials and never calls live paid providers.

Passing these checks does not establish a live VPS, issued TLS certificate, store subscription product or push-delivery setup. Complete staging tests with real Firebase providers, RevenueCat sandbox restoration/renewal/webhook failure cases, production-origin mobile connectivity, backups/recovery, APNs/FCM on physical devices, and the owner's final privacy/legal/medical-content review before a store release.
