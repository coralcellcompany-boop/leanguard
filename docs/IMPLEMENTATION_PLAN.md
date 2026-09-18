# LeanGuard implementation plan

Source of truth: the 14 screens in Downloads/LeanGuard-complete-design-and-implementation/app/page.tsx and globals.css. Product access rules are copied unchanged into FEATURE_MATRIX.md. Native Flutter widgets only.

The selected backend is Firebase project `leanguard-a58ff`, with `europe-west1` as the Functions region and intended Firestore location. The earlier Supabase implementation remains an optional migration reference; it is not the mobile app's active runtime.

1. Establish tokens, accessible shared controls, Riverpod application state, domain calculations and an encrypted per-account cache with a retryable write queue.
2. Rebuild welcome, authentication, goals, optional GLP-1 mode and permission education; persist onboarding and consent.
3. Connect Today, strength plans, live sets/reps/load/rest, skipping, exercise details and session summaries to persisted data.
4. Connect walking, protein, weight and measurements to validated forms and real progress calculations.
5. Add guarded coaching with server-owned usage/entitlements, structured insights and explicitly approved plan proposals.
6. Connect reminders, health permissions, profile/preferences, privacy/export/deletion and RevenueCat paywall/restoration.
7. Configure Firebase Authentication, Firestore and Storage. Enforce ownership, parent references, field validation and server-only writes through Security Rules and authenticated HTTPS Functions; use App Check, transactional quotas, append-only consent and server-verified RevenueCat entitlements. Keep OpenAI and RevenueCat secrets in Secret Manager.
8. Run analyzer, unit/widget/integration checks; audit routes, empty/error/denied/offline states and mobile configuration. Record physical-device/store/deployment checks separately from executed checks.
9. Verify the backend with compiled TypeScript policy tests, isolated Auth/Firestore/Storage emulators and actual Functions-emulator HTTP requests. CI uses project `demo-leanguard` and requires no production secrets.
10. Provision the owned Firebase project and register both native apps, configure provider/store products and billing, deploy rules/functions, and perform live device/vendor acceptance before release. Track results in `VALIDATION.md` without treating local tests as production validation.

## Release acceptance

- No secrets in Flutter. Production requires Firebase billing/services, Auth providers, App Check, RevenueCat, OpenAI, APNs/FCM and store configuration. Public Firebase app IDs and public RevenueCat SDK keys are client configuration; server secrets are not.
- No health data or free-text coaching in analytics/crash reports.
- Never paywall an active workout or access to previously recorded data.
- Free and Pro capabilities follow FEATURE_MATRIX.md; cached entitlements cannot authorize server AI usage.
- No medical diagnosis, prescribing or dosage advice. Warning signs use deterministic escalation and AI failure keeps manual features usable.
- Prototype example metrics are illustrative only. Empty accounts do not display invented health measurements or readiness claims.
- Permission denial is recoverable and manual logging remains available.
- Sensitive account actions require verification of the current Firebase user; cancellation must not be reported as successful verification.
- Follow `FIREBASE_SETUP.md` for the active backend and `MOBILE_SETUP.md` for native setup. Supabase reference migrations are not a deployment prerequisite.
