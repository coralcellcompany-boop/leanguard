# Firebase Authentication and FCM

Firebase project **leanguard-a58ff** now supplies only **Authentication and Firebase Cloud Messaging**. All application records, AI requests, subscriptions, scheduled jobs and private exports run on the standalone Node/PostgreSQL backend. Follow [BACKEND_VPS.md](BACKEND_VPS.md) for deployment. There are no active Functions, Firestore, Storage or App Check targets in `firebase.json`.

Both native application identifiers are **com.coralcell.leanguard**. Registered iOS app ID: `1:124240474112:ios:f9e9950c31bfd2c44d68e5`; Android app ID: `1:124240474112:android:1495e65e745cbc5d4d68e5`. Matching SDK files are configured locally and ignored by Git. Preserve real configuration when reopening the workspace; example templates are not credentials.

## Authentication setup

Email/password sign-in is enabled with a 12-character minimum password and email enumeration protection. Google and Apple providers still require owner configuration. Add the correct Android signing SHA fingerprints, iOS reversed OAuth client ID, Apple service/key details and authorized domains. Set password-reset action links and public privacy/support URLs. See [MOBILE_SETUP.md](MOBILE_SETUP.md) for platform-specific steps.

The mobile app persists native Firebase sessions and sends a fresh Firebase ID token to `BACKEND_BASE_URL`. The backend verifies token signatures, revocation and email verification before accessing PostgreSQL. Account deletion requires authentication within the last ten minutes. App Check is not an application dependency or API requirement.

Use a dedicated Firebase Admin service identity on the VPS with permissions for Auth verification/revocation/deletion and FCM delivery. The Docker template mounts its JSON at `/run/secrets/firebase_admin`; plain Node supports Application Default Credentials or `GOOGLE_APPLICATION_CREDENTIALS`. Never place an Admin credential in Flutter, Git, public hosting or a Docker image. Server OpenAI/RevenueCat keys and PostgreSQL credentials use protected VPS secret files, not Firebase Secret Manager.

## Push setup

Enable the FCM HTTP v1 API and upload the real APNs authentication key/certificate for the iOS app. Configure Apple push entitlement, signing and physical-device permission testing. Android requires its matching Firebase SDK configuration and notification permission on applicable versions.

The app registers an FCM token through authenticated `PUT /v1/device-tokens`. The API hashes the token into a stable owned identifier and supports owner-only removal. The standalone Node worker sends generic, privacy-safe notifications after checking consent, timezone, quiet hours, tier and relevant activity. No Cloud Scheduler or public scheduler endpoint is used. Permission denial leaves manual app use and native local-reminder settings available.

Validate delivery on signed physical iOS/Android devices. Simulator, emulator and transport tests cannot establish real APNs/FCM deliverability.

## Local verification

`firebase.json` defines only the Auth emulator. `npm --prefix backend run test:http` starts an isolated Auth emulator under project `demo-leanguard` and exercises the real Express API against an isolated PostgreSQL test database. It uses pinned Firebase CLI 15.30.2 and does not call real paid providers. See [BACKEND_VPS.md](BACKEND_VPS.md) for database prerequisites and CI commands.

## Preserved history

The previous Firestore database and rules were provisioned in europe-west1 on 2026-09-18. No cloud data was deleted during the Node migration. They are no longer read or written by the app. Billing was disabled at the last provisioning check; no Functions or Storage deployment was completed. Keeping Firebase Auth/FCM does not require deploying the former application backend.

The previous Functions/Firestore/Storage instructions are preserved in [FIREBASE_LEGACY.md](FIREBASE_LEGACY.md) strictly as a migration reference. Do not run those deployment instructions for the current application. The two temporary com.leanguard.app Firebase registrations were removed using Firebase's recoverable operation; current com.coralcell.leanguard registrations remain active. No live Auth account, email, provider key or paid purchase was created for the automated test suites.
