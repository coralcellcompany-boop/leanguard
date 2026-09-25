# Validation and release status

The active architecture is **Flutter → a self-hosted Node.js API → PostgreSQL**. Firebase project `leanguard-a58ff` provides **Authentication and FCM only**. Firebase Functions, Firestore, Storage and App Check are not required by the active mobile/backend runtime. Both native identifiers are `com.coralcell.leanguard`.

Use [BACKEND_VPS.md](BACKEND_VPS.md) for Docker deployment, [POSTGRES_SCHEMA.md](POSTGRES_SCHEMA.md) for ownership/migration details, and [MOBILE_SETUP.md](MOBILE_SETUP.md) for native setup. Choose an EU VPS and backup destination to retain the user's European data-location preference; third-party processing regions require separate review.

## Executed checks — 2026-09-25

- **237 Flutter unit/widget tests passed; final full analyzer clean.** Coverage includes account isolation, encrypted offline replay, onboarding, workout logging, permission denial, entitlement gates, restoration, AI failures and owner-safe API/export handling. Three final regressions cover canonical Free-plan rebuilds after Pro expiry while preserving saved preferences/history. Focused runs overlap this total.
- **Two native iOS integration tests passed.** The app flow uses isolated preview records with the real router/controller and a temporary native Keychain round trip. The second uses a real loopback HTTP server to check Firebase bearer-token transport, JSON records and an account switch during an outstanding request. Neither contacts a live OpenAI/store/production backend. These native integration checks preceded the final downgrade-only change, which has separate regression tests.
- **Configured Android debug and iOS simulator builds passed after the final downgrade fix.** Package/bundle IDs and embedded Firebase configuration match. A final clean iOS rebuild restored `lib/main.dart` after the integration harness replaced generated artifacts. Removed Firebase service frameworks are absent; Auth's required AppCheckInterop shim is not the App Check SDK. These are development artifacts, not signed store releases.
- **38 Node policy/API/validation/export/worker/configuration tests passed** after the final review fixes and TypeScript compilation. Tests include malformed requests, ownership fields, protected records, safety, quotas, signed export links, concurrency, scheduler overlap prevention and startup configuration validation.
- **22 PostgreSQL integration tests passed** against actual disposable PostgreSQL 17: migrations, restricted roles, RLS, cross-owner references, rollback/retry, record imports, server-owned records and cross-instance lifecycle locking without starving database query connections.
- **10 authenticated HTTP integration tests passed** with actual Express/PostgreSQL and isolated Firebase Auth emulator tokens. They cover concurrent Free starter-plan enforcement, protected records, cross-owner isolation, exports and account deletion. Deletion verifies lock contention/retry, actual private-file/SQL removal and emulator Auth deletion; only the RevenueCat response is mocked. No paid provider is called.
- API and non-root Caddy Docker images built successfully; base Compose, optional landing overlay and both Caddy configurations validated. The final hardened API-container smoke test passed readiness, missing-authentication and UID 10001/read-only-root checks. A real Caddy 502 regression also passed: error metadata remains useful while signed export URLs, identity fields and request headers are removed from runtime logs.
- `npm audit --omit=dev` reported **zero production dependency vulnerabilities** at this checkpoint.
- Landing-page links/assets, image descriptions, unique IDs and JavaScript syntax were validated. Exact committed source was packaged and deployed as an owner-private [Sites page](https://leanguard-coralcell.mhamoudabaplus.chatgpt.site). No browser rendering audit was performed in this turn.

Earlier Supabase and Firebase Functions emulator results are historical only; they do not establish behavior of the Node backend. No VPS or live vendor deployment was performed.

## Reproduce checks

Use Flutter 3.38.9 / Dart 3.10.8 and Node 22. Native builds require their platform SDKs. PostgreSQL tests require a disposable database whose name ends in `_test`, with roles/migrations provisioned as described in the backend guide.

```sh
flutter pub get
flutter analyze
flutter test
npm ci --prefix backend
npm --prefix backend test
# Set TEST_DATABASE_URL and TEST_ADMIN_DATABASE_URL privately first:
npm --prefix backend run test:database
npm --prefix backend run test:http
python3 tool/package_server.py
flutter build apk --debug --dart-define-from-file=dart_defines.json
flutter build ios --simulator --dart-define-from-file=dart_defines.json
flutter test integration_test/app_flow_test.dart -d <simulator-or-device-id>
```

The integration entrypoint can replace generated build products; rebuild `lib/main.dart` before distributing a normal development app. CI uses isolated demo authentication/test databases, not production credentials.

## Hosted configuration and release acceptance

Earlier setup registered the native apps and enabled Firebase email/password authentication with a 12-character minimum and email-enumeration protection. Firestore/rules created in `europe-west1` on 2026-09-18 are legacy and have not been destroyed. Existing cloud records need a verified migration before retiring that database. No Functions/Storage deployment is needed for the new backend.

1. Supply VPS/API domains, configure TLS, mount server secrets, provision PostgreSQL roles, run migrations and start API/worker containers. Verify staging isolation, token revocation, export/deletion, backups and restoration. The repository has not been deployed to the user's VPS.
2. Configure Firebase Apple/Google providers and native fingerprints/redirect schemes. Grant the server identity required Auth administration and FCM permissions. Test real sign-in/recovery/revocation; emulator results do not establish hosted-provider setup.
3. Configure RevenueCat entitlement `pro`, offerings and store products at **$19.99/month / $119.99/year**, optionally with an eligible seven-day annual trial. Mount secret API/webhook keys on the VPS; set public SDK keys in Flutter. Verify purchase, restoration, cancellation, renewal, grace, billing issues and expiry in both store sandboxes. Existing data remains readable after expiry.
4. Mount the OpenAI key on the server. Defaults are `gpt-4.1-mini` for ordinary coaching and `gpt-4.1` for complex plan reasoning, configurable server-side. Run live schema/safety/timeout/refusal evaluations and cost monitoring. Mocked transport tests do not prove live model behavior.
5. Exercise HealthKit/Health Connect denial, revocation, timestamps, deduplication and background refresh on physical devices. Native health writes and local export markers cannot share a transaction; no automatic retry follows an unconfirmed workout export.
6. Configure APNs/FCM and verify local/worker push on physical devices: timezone changes, quiet hours, token rotation and denied permissions. The private VPS worker has no public scheduler endpoint. OS delivery/background timing remains best effort.
7. Supply approved privacy/terms/support pages, store disclosures and signing identities. Review accessibility and clinical wording. The landing page says “coming soon”; replace labels with genuine store links after release. Local tests and preview publication do not establish store approval or production vendor acceptance.
