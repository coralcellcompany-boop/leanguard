# Validation and release status

The active backend targets Firebase project **`leanguard-a58ff`**, Functions region **`europe-west1`**, and a Firestore database in that European region. Public project/app configuration, emulator verification, service deployment and live-vendor acceptance are separate milestones. Use [FIREBASE_SETUP.md](FIREBASE_SETUP.md) for provisioning/deployment and [MOBILE_SETUP.md](MOBILE_SETUP.md) for platform setup.

## Confirmed hosted setup

Observed on **2026-09-18** in `leanguard-a58ff`:

- Enabled the Firestore API and created the default Native/Standard Firestore database in **`europe-west1`**. The reviewed Firestore Security Rules and indexes deployed successfully.
- Enabled Firebase email/password authentication with an enforced minimum password length of 12 characters and email enumeration protection. No live test accounts or verification emails were created during these setup checks.
- Registered the iOS and Android apps as **`com.coralcell.leanguard`** and refreshed matching native SDK files and Dart client configuration. Configured Android debug and iOS simulator rebuilds both passed. The APK package, iOS bundle identifier and embedded Firebase app/project identifiers were checked against the private Dart configuration. This does not validate Google/Apple sign-in or store purchases.
- At this checkpoint, billing remained disabled, no Storage bucket or Functions deployment existed, and Google/Apple authentication providers were not configured. RevenueCat/store products, server provider secrets, App Check and physical-device acceptance remain separate requirements below.

This confirms the stated Firestore and password-auth configuration only. It does not establish working paid subscriptions, AI requests, native provider sign-in, health sharing or push delivery.

## Executed implementation checks

The final full Flutter suite completed **215 tests**, and `flutter analyze` reported **no issues**. Individual focused counts below overlap with that suite and must not be summed.

- Inspected all 14 primary prototype screens in source, recreated them as native Flutter widgets, rendered them to PNG and reviewed their UI. Reports, GLP-1 routine support, training preferences and adaptive insights add four matching native screens. Captures and reproduction steps are described in [DESIGN_AUDIT.md](DESIGN_AUDIT.md).
- Native widget suites cover standard/compact phone sizes, enlarged text, navigation, empty/denied states, logging validation, consent, paywall behavior and historical-data access. The primary/insight/domain regression run completed **67 tests**. Captures use fixture records; they do not imply real account activity.
- Domain/repository/controller suites exercise all 20 entities, account-isolated encrypted-cache behavior, offline mutation retry, onboarding, workout persistence, conservative suggestions, safety fallbacks, Free/Pro gates and subscription restoration.
- Added **nine Firebase repository helper tests** for document IDs, source-aware imported-weight hashes, nested timestamp normalization and HTTPS endpoint mapping. **Four reauthentication widget tests** verify that sensitive actions use the current account, reject incorrect credentials, prevent account creation from the verification form, and distinguish successful verification from cancellation. Together with the eight existing supporting-screen tests, the targeted run completed **21 tests**. The corresponding analyzer check passed.
- The workout-health sharing regression run completed **22 tests**: ten export checks, three summary-screen checks and nine existing controller checks. It verifies exact summary-workout identity, persisted duplicate prevention, native write failure, denied permissions and account/entitlement changes during asynchronous work.
- The final lifecycle run completed **10 tests**, including two added regressions: a late account-deletion response cannot sign out or erase a newly selected account; expiration cancels old schedules and retains at most three enabled fixed local reminders while disabling Pro quiet hours. Weight logs and all saved reminder preferences remain intact. The lifecycle test analyzer check passed.
- The Firebase TypeScript build passed, followed by **14 policy/provider tests**, **20 Auth/Firestore/Storage emulator tests**, and **one actual Functions-emulator HTTP test**. Coverage includes concurrent quotas, consent revocation, trusted entitlements, reminders, health import safeguards, plan approval and authenticated requests. Emulator tests use `demo-leanguard` and placeholder secrets; no real OpenAI or store credentials are used. `npm audit --omit=dev` reported no production dependency vulnerabilities at this verification point.
- **After the Firebase migration**, Android debug and iOS simulator builds succeeded. The native integration flow passed on an iPhone 17 Pro Max / iOS 26.2 simulator using the real router, controller and a temporary native Keychain round trip. It covers onboarding, manual permission fallback, invalid/valid weight input, protein, workout logging/skipping/completion, notification unavailability, unavailable preview checkout and serialized preview persistence. This flow uses isolated local records, not a connected production account. After migrating to `com.coralcell.leanguard`, both platforms were rebuilt successfully with `--dart-define-from-file=dart_defines.json`; artifact identifiers and embedded Firebase configuration match. The device integration run preceded this identifier-only migration. The Android artifact is `build/app/outputs/flutter-apk/app-debug.apk`; the iOS simulator artifact is `build/ios/iphonesimulator/Runner.app`. These are debug/simulator builds, not signed store releases.

The earlier Supabase migrations/RLS and Edge Functions were also checked during the original implementation. They remain **legacy reference validation only** and do not establish Firebase behavior. Default CI now runs Flutter analysis/tests/Android debug build plus Firebase function compilation, policy tests, Security Rules emulator tests and Functions HTTP smoke tests.

## Reproduce current checks

Use Flutter 3.38.9, Node 22, Java 17 for Android builds, and Java 21 for the Firebase emulators. Firebase CLI is pinned in `firebase/functions/package-lock.json`; the scripts invoke that local version rather than an unrelated global CLI.

```sh
flutter pub get
flutter analyze
flutter test
npm ci --prefix firebase/functions
npm --prefix firebase/functions test
npm --prefix firebase/functions run test:emulator
npm --prefix firebase/functions run test:http
flutter build apk --debug
flutter build ios --simulator
flutter test integration_test/app_flow_test.dart -d <simulator-or-device-id>
```

The Firebase runners select the isolated `demo-leanguard` project and strip unrelated credentials from the emulator environment. CI does not deploy services or use production credentials. Run native commands only on the appropriate configured host. Report the final aggregate test/build results for the exact revision being delivered; counts in individual verification runs are not additive across overlapping suites.

## Connected-service and release acceptance

1. Confirm project access, Blaze billing and enabled Firebase services. Verify the default Firestore database and Storage bucket locations, register `com.coralcell.leanguard` on both platforms, enable email/Google/Apple providers, configure OAuth fingerprints/return schemes and App Check, and deploy the reviewed Security Rules, indexes and Functions. Exercise owner isolation, token revocation, export and deletion with two disposable accounts against staging. Local emulator success does not verify this hosted configuration.
2. Configure RevenueCat entitlement `pro`, offerings and both stores' products at **$19.99 monthly / $119.99 annually**, with an optional eligible **seven-day annual trial**. Add public platform SDK keys to the client and restricted server/webhook secrets to Secret Manager. Verify actual purchase, pending/canceled checkout, restoration, renewal, grace/billing issues, expiration and webhook reconciliation in both stores. Existing data must remain accessible after expiration.
3. Set the server-only OpenAI secret and intended model parameters. Run live structured-output/safety evaluations, provider-refusal and timeout handling, and cost monitoring. The inexpensive normal-coaching model and stronger reasoning model are configuration choices; local mocked responses do not prove live model behavior. No provider API key belongs in Flutter.
4. Verify HealthKit and Health Connect partial denial, separate read/write consent, duplicate avoidance, original sample timestamps, real sensor data and OS-scheduled background refresh on physical devices. Workout export tracks the exact completed workout and persists an exported marker after native success; simultaneous and repeated exports are guarded. Native Health and the local cache cannot share a transaction, so a crash after the native write but before the marker is saved can leave an unconfirmed export. No automatic workout-export retry is performed. OS background timing is best effort.
5. Configure APNs and FCM for the registered apps, deploy the authenticated Cloud Scheduler trigger, and verify local/push permissions, timezone/quiet hours, token rotation and delivery on real devices. No public scheduler endpoint or client-held scheduler secret is required. Notification payloads must remain free of health values.
6. Fill production privacy/terms/support URLs; review vendor retention and processing regions, store privacy declarations, Security Rules/App Check enforcement, accessibility with VoiceOver/TalkBack, and clinical wording. Selecting a European Functions/Firestore region alone does not establish every external provider's processing location.
7. Supply signing identities, complete store agreements/health declarations and upload signed artifacts through the owner's Apple/Google accounts. Emulator tests, debug builds, public Firebase app registration and a source-code review do not certify store approval or production purchase/health/push flows.

Track actual hosted provisioning and deployment outcomes separately from these acceptance requirements. Do not describe credentials, paid products, Functions deployment or physical-device validation as complete without their corresponding live evidence.
