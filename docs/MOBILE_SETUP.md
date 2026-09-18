# LeanGuard mobile setup

The Flutter application is native Flutter on iOS and Android. Browser UI is only a preview/testing target. Authentication uses Firebase Auth: native Google Sign-In and Apple provider flows. No product screen uses a WebView. The active backend is Firebase in `europe-west1`; the earlier Supabase implementation is retained only as migration/reference material.

## Toolchain and local run

- Use the repository Flutter version (3.38.9 / Dart 3.10.8 at implementation time), Xcode with iOS SDK, CocoaPods, Java 17, and Android SDK tooling. `flutter doctor -v` must pass the platform you intend to build.
- iOS deployment target is 15.0. Android minimum SDK is 26; Health Connect must be available on the device. Use a physical device for health and store acceptance tests.
- Run `flutter pub get`. Copy `dart_defines.example.json` to ignored `dart_defines.json` and fill your public client configuration. Never put OpenAI, RevenueCat secret API, APNs signing, or Firebase service-account keys in Dart, assets or `--dart-define`.
- Run `python3 tool/configure_firebase_native.py dart_defines.json` after configuring Google OAuth, then `flutter run --dart-define-from-file=dart_defines.json`. Use a separate private JSON for staging if needed.
- Run `flutter analyze`, `flutter test`, and `flutter test integration_test -d <device-id>` before release. Native service tests include RevenueCat restoration/error behavior, cancellation/grace periods, permission denial and DST/quiet-hour scheduling.

For configured device builds, download the SDK files matching `com.coralcell.leanguard` into ignored `ios/Runner/GoogleService-Info.plist` and `android/app/google-services.json`, and keep their project/app IDs consistent with `dart_defines.json`. An iOS build phase verifies the bundle ID and copies the optional plist into the app; absent configuration is removed from a reused build directory. Follow the [Firebase Apple setup](https://firebase.google.com/docs/ios/setup) and [Android setup](https://firebase.google.com/docs/android/setup).

Client configuration uses `FIREBASE_PROJECT_ID`, `FIREBASE_REGION`, `FIREBASE_MESSAGING_SENDER_ID`, `FIREBASE_STORAGE_BUCKET`, platform-specific `FIREBASE_IOS_APP_ID` / `FIREBASE_ANDROID_APP_ID` and API keys, `GOOGLE_IOS_CLIENT_ID`, `GOOGLE_WEB_CLIENT_ID`, `REVENUECAT_IOS_KEY`, `REVENUECAT_ANDROID_KEY`, `SENTRY_DSN`, `PRIVACY_URL`, and `TERMS_URL`. Firebase public client identifiers are not server secrets. Auth, Firestore/Storage Security Rules, App Check, and authenticated HTTPS Functions enforce protection. Native Firebase Auth owns credential persistence; health logs use the application's encrypted Keychain/Keystore cache, with Firestore disk persistence disabled.

## Firebase authentication and backend

1. Use the owned Firebase project `leanguard-a58ff` (project number `124240474112`) with region `europe-west1`, or separate staging/production projects. Register iOS and Android apps with ID `com.coralcell.leanguard`. Configure Firestore's Europe location before creation; region choices are not freely changeable later. Deploy `firebase/firestore.rules`, indexes, Storage rules and HTTPS Functions following the Firebase backend guide.
2. Enable email/password, Google and Apple providers in Authentication. Set the password policy to at least 12 characters. Configure verification/recovery email branding and authorized domains. The app sends verification on signup and rejects unverified password sign-in; recovery completes through Firebase's hosted email action handler before the user signs in again. Do not enable anonymous sign-in for preview mode.
3. Google uses the official native `google_sign_in` plugin, then exchanges the returned ID token with Firebase Auth. Supply the Web OAuth client ID as `GOOGLE_WEB_CLIENT_ID` (including on Android) and the iOS OAuth client ID as `GOOGLE_IOS_CLIENT_ID`. On Android register debug, upload and Play app-signing SHA-1/SHA-256 certificates. Before building iOS, run `python3 tool/configure_firebase_native.py dart_defines.json` with the same private JSON passed to Flutter. It derives the **reversed iOS client ID** into ignored `ios/Flutter/Firebase.generated.xcconfig`; Runner/Info.plist references this setting as its Google callback URL scheme. This URL scheme is required even when using Dart FirebaseOptions. Do not use the Web client ID as the iOS client ID.
4. Enable Sign in with Apple on the Apple app identifier and Runner capability. In Firebase Apple provider configuration set the Services ID, team ID, key ID and private key for Android/web OAuth, with the Firebase displayed return URL. Keep the `.p8` signing key in the provider console, never in the app. Test Apple private relay email. The iOS native flow uses `AppleAuthProvider`; Android uses Firebase's supported OAuth provider flow.
5. Production App Check uses Play Integrity on Android and App Attest with DeviceCheck fallback on iOS. Register apps and enforce App Check on Functions, Firestore and Storage after staging verification. Debug builds use debug providers: register the locally printed debug token only in your development project. Never ship a debug App Check token in a release build. FirebaseRuntime refuses emulator configuration in release mode.
6. Emulator testing is explicit via `FIREBASE_USE_EMULATORS=true` and `FIREBASE_EMULATOR_HOST` (`10.0.2.2` from an Android emulator, `localhost` on iOS simulator). Auth uses 9099, Firestore 8080, Storage 9199 and Functions 5001. Production HTTP Functions require Firebase ID and App Check tokens. Android debug builds allow cleartext only to `10.0.2.2`, `127.0.0.1`, and `localhost`; the resource is excluded from release. For another test host add a debug-only exception rather than weakening release policy.
7. Test verified email sign-in, expired recovery/verification links, Google/Apple return, provider cancellation, recent-login reauthentication for deletion, sign-out and two accounts on one device. RevenueCat identity is the Firebase UID. Late service responses cannot transfer health data or Pro access to another account.

Firebase App Attest setup requires the production entitlement even for a signed development build using the real provider; see the [official App Attest setup](https://firebase.google.com/codelabs/app-attest).

See [Firebase Flutter authentication](https://firebase.google.com/docs/auth/flutter/start), [native provider configuration](https://firebase.google.com/docs/auth/flutter/federated-auth), [Google Sign-In iOS requirements](https://pub.dev/packages/google_sign_in_ios), and [Flutter App Check](https://firebase.google.com/docs/app-check/flutter/default-providers).

## iOS / Apple Health

1. Open `ios/Runner.xcworkspace` in Xcode after `flutter pub get` and `pod install` from `ios/`.
2. Select your paid Apple Developer team for Runner, register `com.coralcell.leanguard` (or update *all* matching native IDs, OAuth redirects, RevenueCat and Firebase apps if using an owned replacement), and enable HealthKit, Sign in with Apple, App Attest, Push Notifications and Keychain access.
3. Runner.entitlements declares HealthKit, Apple sign-in, App Attest (production environment required by Firebase), Keychain and APNs. Debug builds use the separate App Check debug provider; register its development token before accessing protected services. Debug uses the development APNs environment; release/profile use production. Download provisioning profiles matching these capabilities.
4. Read the Health permission education screen before requesting access. Free reads steps and weight. Pro can additionally read active energy and workouts. Exporting a completed strength workout requests separate read/write workout authorization. No routes, location, medication records, heart-rate or clinical records are requested.
5. HealthKit deliberately does not reveal denied read permission. A completed permission sheet is represented as `readAccessUnknown` until data is returned. Empty data must not be presented as a confirmed connection or as zero activity. Changes/revocation are made in Apple Health → profile → Apps → LeanGuard.
6. Weight imports include their source UUID and original observation date. Upsert by external identifier; do not assign today's date to a historical sample. Workout summary sharing records a per-workout `health_exported_at` marker only after the native write succeeds, and requires explicit current-account permission and Pro access. Export is user initiated with no automatic retry: a process crash between the native write and marker persistence can still require checking Health before retrying.
7. Pro offers a separate background-sync opt-in backed by Workmanager/BGTaskScheduler. It schedules opportunistic refresh about every six hours, rechecking server entitlement, consent and health connection before reading. iOS chooses actual execution times and HealthKit data can be unavailable while the device is locked; these attempts retry later and foreground sync remains available. This is periodic app refresh, not immediate HealthKit observer delivery. Test real background execution on physical devices before promising any delivery interval. The permitted task identifier is `com.coralcell.leanguard.health-sync`.
8. Runner/PrivacyInfo.xcprivacy declares collected categories and UserDefaults usage. Review the aggregate Xcode privacy report and App Store privacy labels against the *final* backend, providers and policy; third-party SDK manifests are bundled through CocoaPods.

The Health integration follows the package's [native configuration requirements](https://pub.dev/packages/health). HealthKit cannot be fully validated through a browser or conventional Flutter widget test.

## Android / Health Connect

1. Install Android Studio SDK platforms/build tools matching Flutter's current compile SDK and run `flutter doctor --android-licenses`.
2. The app uses `FlutterFragmentActivity`, which supports Health Connect's activity-result permission flow. The manifest includes only steps, weight, active calories and exercise read permissions plus explicit workout write permission. Permissions are requested incrementally.
3. On Android versions without built-in Health Connect, install/enable Health Connect. The service can open its installation flow. Declining permission must leave manual logging fully usable. Pro background sync separately checks Health Connect background-read support and requests `READ_HEALTH_DATA_IN_BACKGROUND`; unsupported devices continue using foreground refresh. Background reads require both OS permission and live backend entitlement/health consent, and never overwrite a deliberate manual activity entry.
4. Health Connect's permission rationale opens the native `HealthPrivacyActivity`; it works even when Flutter has not started. Keep this text consistent with the full published policy. Complete the Google Play Health apps declaration and request approval for each production permission actually used.
5. Backups and cleartext traffic are disabled. Notification reminders use inexact scheduling and do not request exact-alarm special access. Reboot receivers restore scheduled notifications. Battery restrictions can still defer delivery.
6. Copy `android/key.properties.example` to ignored `android/key.properties` and supply your upload keystore. Keep the keystore/passwords in CI secrets. Release builds have no debug-signing fallback. Check the final app bundle signing certificate before uploading.
7. Build with `flutter build appbundle --release --dart-define-from-file=dart_defines.json`. Supply the ignored matching `android/app/google-services.json` for configured production builds. The Google Services Gradle plugin is applied only when this file exists; it generates native Firebase resources used after a background process restart. Credential-free preview/CI builds continue without it.

## RevenueCat and store products

1. Create matching App Store Connect and Play Console apps for the bundle IDs above. Configure store signing and payout/tax agreements before sandbox purchase tests.
2. Create monthly and annual auto-renewing subscriptions at the requested US base prices: **$19.99/month** and **$119.99/year**. Set your product IDs in both stores and import them into RevenueCat.
3. Create RevenueCat entitlement **`pro`**, attach both products, and create a current offering with standard `$rc_monthly` and `$rc_annual` packages. The paywall must show the store-provided localized price, billing period and any eligibility returned by the store. Displaying a price never creates a subscription.
4. If offering the annual seven-day trial, configure a seven-day introductory offer in App Store Connect and the appropriate Play base-plan/offer. Eligibility is controlled by the store; never promise a trial to an ineligible account. Configure renewals after the trial at the annual price.
5. Put only each platform's RevenueCat **public SDK** key in the client environment. Use the Firebase Auth UID as appUserID. Set RevenueCat restore/transfer behavior deliberately, and test that account switching cannot transfer access unexpectedly.
6. Configure RevenueCat's webhook to the deployed `revenuecatWebhook` HTTPS Function in `europe-west1`. Use a long dedicated authorization secret in RevenueCat and server environment. Backend entitlement checks use this server-verified record; the client SDK drives store checkout/status.
7. Verify purchase, user cancellation, pending/ask-to-buy purchase, restoration on reinstall and second device, renewal, cancellation with remaining access, billing issue/grace, expiration and webhook replay/out-of-order events. Never locally set Pro merely because a purchase button was tapped.
8. Cancellation opens the user's store subscription management. Deleting a LeanGuard account does **not** cancel store billing; account deletion must explain this and offer the store management link. Expiration removes paid operations, while existing data/export/delete remain accessible.

See [RevenueCat Flutter installation](https://www.revenuecat.com/docs/getting-started/installation/flutter) and [entitlement status](https://www.revenuecat.com/docs/customers/customer-info).

## Local and server notifications

Local notifications initialize without prompting. Request OS permission after the education screen. Schedule only enabled reminders with `delivery='local'`; schedule one request per selected weekday using the user's IANA time zone. Quiet hours defer notifications to the end of the quiet window, including the next day when appropriate. Re-schedule after reminder changes, time-zone changes, sign-in and app resume. Cancel on sign-out/deletion. Android OS power management and iOS notification settings may postpone or suppress delivery.

Remote reminders use Firebase Cloud Messaging and the Firebase backend scheduler. If remote push is not configured, display unavailable and continue to offer local reminders.

1. Create Firebase iOS and Android apps with the final bundle IDs. Enable FCM HTTP v1. Do not add Firebase Analytics.
2. Provide these *public client identifiers* through your private Dart-define JSON: `FIREBASE_PROJECT_ID`, `FIREBASE_MESSAGING_SENDER_ID`, `FIREBASE_IOS_APP_ID`, `FIREBASE_IOS_API_KEY`, `FIREBASE_ANDROID_APP_ID`, `FIREBASE_ANDROID_API_KEY`. Keep platform IDs separate. Restrict API keys to the matching apps as supported by your deployment.
3. Upload your APNs `.p8` signing key to Firebase Cloud Messaging settings with its Apple team/key identifiers. Keep Firebase method swizzling enabled. Confirm production APNs provisioning for TestFlight.
4. Use the Cloud Functions runtime service account and Firebase Admin SDK for FCM; do not download service-account keys into the app. Deploy the scheduled Cloud Function with the least privileges required. It applies timezone, quiet hours, smart-reminder eligibility and delivery deduplication before sending.
5. PushService.enable() runs only after the user enables remote reminders and grants OS permission. It upserts the token into `users/{uid}/device_tokens/{sha256(token)}` under owner-only Firestore rules and handles rotation. Call disable() while still authenticated before sign-out or account deletion.
6. The native manifest/plist disable FCM auto initialization until opt-in. Payload copy is generic and contains no weight, medication, protein or coach conversation. Only allowlisted routes are opened. Quiet hours are enforced on the server for remote messages; foreground alerts are suppressed to avoid duplicates.
7. Test remote push on physical devices with the app foregrounded/backgrounded/terminated, token rotation, offline server retries and denied/revoked permission. FCM/APNs delivery is best effort, so reminders must not be treated as critical medical alerts.

See [FCM Flutter setup](https://firebase.google.com/docs/cloud-messaging/flutter/get-started) and [local notification setup](https://pub.dev/packages/flutter_local_notifications/versions/19.4.0).

## Privacy and diagnostics

Diagnostics and analytics are separate opt-ins. Sentry is not initialized until at least one is enabled and a DSN is configured. Analytics accepts only a fixed enum of generic application events. It does not accept arbitrary properties. Diagnostic events are rebuilt before transmission so health values, identifiers, exception text, request bodies, breadcrumbs, screenshots and view hierarchies are not sent. Native automatic crash capture and automatic session/performance tracing are disabled. This reports sanitized Dart failures; native crash diagnosis requires a separately reviewed privacy-safe rollout.

Record consent/version in `consent_records` and apply changes to PrivacyService immediately. Consent withdrawal closes Sentry when both features are disabled. Ensure the privacy policy discloses vendors, regions, retention, deletion behavior and optional AI processing. A user must approve AI data sharing before sending health context to the server coach.

Export uses the authenticated `dataExport` HTTPS Function and opens the native share sheet with the actual JSON file. Large exports stream from a ten-minute signed HTTPS Storage URL into app-private temporary storage; the URL is validated against the configured bucket and account, redirects are rejected, and Firebase tokens are never forwarded. Export/deletion function requests and export downloads allow up to 300 seconds. Account switches abort sharing and failed downloads are removed. Successful temporary export copies remain available for receiving apps, are pruned after 24 hours on the next export, and are cleared on account deletion; the OS may evict them earlier. Account deletion requires typed `DELETE`, a recent Firebase authentication (reauthenticate with the original email/Google/Apple provider when prompted), and calls `deleteAccount`; erase local caches, cancel notifications and unregister push before completing sign-out. Share sheets create temporary OS-managed export copies outside the private account; users choose the destination.

## Native branding

Native launch screens and launcher/app-store icons are generated from the supplied prototype's original `public/favicon.svg`, preserved as `assets/branding/app_icon.svg`. `tool/generate_app_icons.py` converts its polygon paths into opaque PNG app icons (requires Pillow); Android also includes an adaptive vector icon. The supplied vector is used unchanged for its glyph and colors.

## Release acceptance checklist

- Validate Free/Pro behavior against FEATURE_MATRIX.md, especially data access after expiry.
- Exercise the full onboarding, sign-in/recovery, manual logging and workout flow offline and after reconnecting.
- Validate purchase/trial/restore and entitlement webhook flows in both stores' sandboxes using real configured products.
- Validate actual HealthKit and Health Connect denial, partial sharing, stale data, revocation and imports on physical devices.
- Verify APNs/FCM and local delivery across timezone/DST, quiet hours and revoked notifications.
- Check VoiceOver/TalkBack, dynamic text, contrast, keyboard, small devices and layout in both orientations supported by the app.
- Publish the owned privacy/terms/support URLs; complete App Store privacy/Play Data Safety and health permissions declarations.
- Test Firestore/Storage rule isolation and account deletion/export against disposable Firebase emulators and a staging project.
- Sign the release with your own credentials, run store prelaunch checks, and retain symbol files for the exact build.

Provisioning, paid store products, OAuth credentials, Firebase deployment and physical-device validation require the owner's accounts. Source code and mock-backed tests alone do not certify those services or app-store approval.

## Automated native acceptance flow

`integration_test/app_flow_test.dart` runs on a native device/simulator using the production router, controller and serialization. It verifies onboarding, optional GLP-1 skip, health/manual fallback, invalid and valid weight entry, a protein meal, workout sets/reps/skipping/completion, notification unavailability, disabled preview checkout, and re-opening serialized preview records. It also exercises the real Keychain/Keystore plugin with a dedicated temporary test key that is deleted in `finally`.

Run `flutter test integration_test/app_flow_test.dart -d <simulator-or-device-id>`. The sample records use an isolated in-memory backing store; this test does not impersonate a connected Firebase account or perform store purchases. It passed on the available iOS simulator during implementation. `test/support_screens_test.dart` separately covers authentication validation/recovery navigation, logging forms, profile/targets, permission denial, privacy consent, deletion cancellation, exercise details, empty summary and the Free quiet-hours gate. Native integration builds succeeded for Android debug and iOS simulator; live service acceptance still requires the configured accounts described above.
