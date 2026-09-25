# LeanGuard

**Lose weight. Keep your muscle.** Native Flutter/Dart application for iOS and Android, rebuilt from all screens in the supplied interactive prototype. No WebView.

## Run

Requires Flutter 3.38.9 / Dart 3.10.8 or a compatible Flutter 3.x release, Xcode for iOS, and Android SDK/JDK 17. The standalone backend uses Node 22 and PostgreSQL 17.

```sh
flutter pub get
flutter run
```

An unconfigured build opens Welcome. **Explore a sample plan** starts a labeled local preview with manual logging, validation and encrypted persistence. It never simulates successful sign-in, coaching, health access or purchases.

For connected operation, preserve existing real SDK files and configure public settings:

```sh
cp -n dart_defines.example.json dart_defines.json
# Fill BACKEND_BASE_URL, Firebase public app config and RevenueCat public SDK keys.
python3 tool/configure_firebase_native.py dart_defines.json
flutter run --dart-define-from-file=dart_defines.json
```

Both application identifiers are **com.coralcell.leanguard**. Firebase project **leanguard-a58ff** provides **Authentication and FCM only**. The active application backend is **Node/Express + PostgreSQL on a Linux VPS**, with Docker Compose, private export storage, a separate worker and Caddy HTTPS. Follow [BACKEND_VPS.md](docs/BACKEND_VPS.md), [POSTGRES_SCHEMA.md](docs/POSTGRES_SCHEMA.md), [FIREBASE_SETUP.md](docs/FIREBASE_SETUP.md) and [MOBILE_SETUP.md](docs/MOBILE_SETUP.md). No VPS/domain was supplied or deployed. OpenAI, RevenueCat secret keys, database credentials and Firebase Admin credentials belong only in protected server secret files.

The landing page source is in `landing/`, with a [private preview](https://leanguard-coralcell.mhamoudabaplus.chatgpt.site). To prepare the allowlisted server/landing/docs package without credentials, run `python3 tool/package_server.py`; it creates `build/leanguard-server.tar.gz`.

## Implementation

- All 14 native prototype screens plus authentication/recovery, permissions, validated logging forms, exercise details, workout completion, reports, personalization and account privacy flows.
- Riverpod state, GoRouter navigation, feature presentation/domain modules, injectable repositories/services and an encrypted per-account Keychain/Keystore cache with offline write replay.
- Verified Firebase ID tokens, PostgreSQL RLS, owner-bound references, strict client field validation, transactional quotas and server-owned consent/AI/entitlement records.
- RevenueCat offerings, trial eligibility, purchase, restoration, billing-state handling and subscription management. RevenueCat verification remains the entitlement authority.
- Server-only OpenAI Responses API with structured output, prompt versioning, data-snapshot caching, timeouts, safety rules, deterministic fallbacks and explicit approval of bounded plan adjustments.
- HealthKit/Health Connect with partial permission denial, original-timestamp imports, optional Pro background refresh and deliberate workout export.
- Native local reminders plus a standalone scheduled FCM worker; privacy-safe content, quiet hours, opt-in telemetry, raw export and recent-auth account deletion.

[FEATURE_MATRIX.md](FEATURE_MATRIX.md) defines the exact product tiers. Existing records and raw account export remain accessible after Pro expires. Logged trends and readiness are product heuristics, not diagnoses or direct muscle-mass measurements.

## Verification

```sh
flutter analyze
flutter test
npm ci --prefix backend
npm --prefix backend test
# Provision an isolated *_test database and set TEST_DATABASE_URL / TEST_ADMIN_DATABASE_URL.
npm --prefix backend run test:database
npm --prefix backend run test:http
flutter test integration_test/app_flow_test.dart -d <device-id>
flutter build apk --debug
flutter build ios --simulator
```

Backend unit tests cover policy, provider failures, exports, worker behavior, HTTP boundaries and validation. Database tests use a real restricted PostgreSQL login and test RLS, constraints and concurrent transactions. HTTP integration tests use real Express requests, PostgreSQL and Firebase Auth emulator under isolated project demo-leanguard. No live paid AI or store provider is called. CI runs these checks and builds/smoke-tests the non-root Docker runtime.

[DESIGN_AUDIT.md](docs/DESIGN_AUDIT.md) records native visual review and commands to regenerate 18 screen captures. [VALIDATION.md](docs/VALIDATION.md) distinguishes executed tests from remaining release work. The previous firebase/functions and supabase implementations are archived migration references, not active deployment or default CI targets.

## Release boundary

The native app and backend are implemented and locally verified; a live production service still needs your VPS/domain, server credentials, real authentication-provider setup, APNs/FCM configuration, RevenueCat/store products and signed release builds. Simulator/tests do not verify store billing, real health sharing, physical push delivery or store approval. Replace policy URLs and complete staging, backup/recovery, privacy/legal and medical-content review before release. Optional same-VPS landing hosting uses the shared Caddy overlay described in BACKEND_VPS.md, avoiding a second listener on ports 80/443.
