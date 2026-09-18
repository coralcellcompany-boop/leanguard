# LeanGuard

**Lose weight. Keep your muscle.** Native Flutter / Dart app for iOS and Android, rebuilt from the supplied interactive prototype. No WebView.

## Run

Requires Flutter 3.38.9 / Dart 3.10.8 or a compatible Flutter 3.x release, Xcode for iOS, and Android SDK/JDK 17 for Android. Firebase backend development uses Node 22 and Java 21 for local emulators.

```sh
flutter pub get
flutter run
```

An unconfigured build opens Welcome. **Explore a sample plan** starts an explicitly labeled local preview with real manual logging, validation and persistence; it never simulates a successful sign-in, AI request, health connection or purchase.

For connected operation:

```sh
cp -n dart_defines.example.json dart_defines.json
# Fill public client configuration. Never put Admin/OpenAI/server keys here.
python3 tool/configure_firebase_native.py dart_defines.json
flutter run --dart-define-from-file=dart_defines.json
```

Both platforms use **`com.coralcell.leanguard`**. Matching Firebase app registrations and private local SDK/Dart configuration are present. The default Firestore database, rules/indexes and email/password sign-in are configured; live Functions and Storage still require billing and the setup below.

The active backend is **Firebase**, targeting project **`leanguard-a58ff`** and Functions/Firestore region **`europe-west1`**. Configure and deploy it using [FIREBASE_SETUP.md](docs/FIREBASE_SETUP.md), then complete the iOS/Android provider setup in [MOBILE_SETUP.md](docs/MOBILE_SETUP.md). These cover Auth, Firestore/Storage Security Rules, App Check, native Google/Apple sign-in, permissions, background refresh, FCM/APNs, RevenueCat products/webhooks, signing and store testing. Public client settings are in `dart_defines.example.json`; public server parameters are in `firebase/functions/.env.example`. Server secrets belong in Google Secret Manager.

## Implementation

- Native welcome, authentication/recovery, onboarding and all 14 prototype screens, plus validated logging forms, exercise details, workout summary, permissions, reports, preferences and privacy/deletion.
- Riverpod application state, GoRouter navigation, immutable domain entities, pure business policies, feature presentation modules and injected repository/service boundaries.
- Firebase Authentication, Firestore and private Storage, with owner-only Security Rules, same-owner parent references, transactional quotas, append-only consent and server-owned entitlement/AI records.
- Native Firebase Auth credential persistence and an encrypted per-account Keychain/Keystore cache; idempotent queued writes, offline recovery and account-switch isolation.
- Real RevenueCat purchase, eligibility, restoration and subscription management. Pro is never granted by a button or client preference.
- Server-only Responses API through authenticated Firebase HTTPS Functions, structured JSON, prompt versioning, snapshot caching, timeouts, evidence checking, conservative proposal bounds, explicit plan approval and deterministic medical escalation.
- Native HealthKit/Health Connect with partial-denial handling, original-timestamp weight imports, optional Pro background work, and explicit workout sharing.
- Local reminders and Cloud Scheduler/FCM delivery, timezone/quiet-hour rules, privacy-safe notifications, opt-in telemetry, raw data export and recent-auth account deletion.

The exact product policy is [FEATURE_MATRIX.md](FEATURE_MATRIX.md). Existing records remain readable after subscription expiration; raw account export is available to all plans. App metrics are derived from logs and never represent a diagnosis or direct muscle-mass measurement.

## Verification

```sh
flutter analyze
flutter test
npm ci --prefix firebase/functions
npm --prefix firebase/functions test
npm --prefix firebase/functions run test:emulator
npm --prefix firebase/functions run test:http
flutter test integration_test/app_flow_test.dart -d <device-id>
flutter build apk --debug
flutter build ios --simulator
```

Firebase scripts compile the TypeScript functions, run policy/provider unit tests, exercise Auth/Firestore/Storage emulators, and run authenticated HTTPS smoke tests against the Functions emulator. The runner always uses isolated project `demo-leanguard`, strips unrelated credentials from its environment, and uses placeholder provider secrets. These tests do not contact live paid AI or store providers. CI runs Flutter analysis/tests/Android debug build and these Firebase suites without production credentials.

`test/screens_test.dart` and `test/insight_screens_test.dart` can regenerate the 18 native visual-review PNGs under `build/ui-audit` (see [DESIGN_AUDIT.md](docs/DESIGN_AUDIT.md)). The earlier `supabase/` SQL/Edge Function implementation is an **optional migration reference**, not the active runtime or default CI backend; its separate instructions are in [BACKEND.md](docs/BACKEND.md).

See [IMPLEMENTATION_PLAN.md](docs/IMPLEMENTATION_PLAN.md) for the implementation sequence and [VALIDATION.md](docs/VALIDATION.md) for executed checks and release prerequisites.

## Release boundary

This repository supplies application and backend code. A project ID or successful emulator test does not establish a deployed production service. Firebase provisioning/billing, Auth providers, App Check, server secrets and Functions deployment must be completed for connected operation. RevenueCat offerings and both stores' products, APNs/FCM delivery, signed release builds and physical-device acceptance require the owner's accounts. Simulator/mock-backed tests do not verify live billing, real health sharing, push delivery or store approval. Replace policy URLs and complete the final privacy/legal/medical-content review before release. See [VALIDATION.md](docs/VALIDATION.md) for the distinction between executed checks and remaining acceptance work.
