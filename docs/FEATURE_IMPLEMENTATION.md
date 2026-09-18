# Feature matrix implementation map

The source requirement is [`FEATURE_MATRIX.md`](../FEATURE_MATRIX.md). The visual source is the supplied interactive prototype; Flutter screens are native widgets. Existing logged records and account privacy exports remain accessible when Pro expires. `SubscriptionStatus` is derived from RevenueCat; server AI and premium database writes use a RevenueCat-verified entitlement mirror.

This map distinguishes an implemented flow from an unconfigured external service or a remaining algorithm. A link to Coach alone does not implement adaptive target changes, and a premium badge alone does not implement the associated analytics.

| Matrix area | Free implementation | Pro implementation and enforcement | Main code / server contract |
| --- | --- | --- | --- |
| Today dashboard | Daily strength, protein, steps and weight drawn from persisted logs | Readiness, priorities and risk presentation gated by active entitlement | `TodayScreen`, `AppState.readiness`, `riskFlag`; `daily_activities`, `workouts`, `workout_sets`, `protein_entries`, `weight_entries` |
| Strength plan | One starter three-day template and per-user exercise library; future sessions are persisted before starting | Saved equipment, time, training days, limitations and exercise preferences; approved substitutions and conservative load/reps/sets proposals | `StrengthScreen`, training preferences in `insight_screens.dart`, `AppController.savePersonalization`, `substituteExercise`, `coach` kind `adaptation`, `approvePlan` |
| Workout logging | Unlimited manual workout/set/rep/load entry, completion, skipping, resumable active session | Pro rest timer, comparisons and progression entry points | `WorkoutScreen`, `startWorkout`, `logSet`, `skipExercise`, `finishWorkout`; `workouts`, `workout_exercises`, `workout_sets` |
| Progressive overload | Exercise detail screen and all personal exercise history | AI proposals validate repeated completed targets, one dimension of increase, <=5% load increase, <=2 reps and <=1 set; explicit approval transaction | `AppController.history`, `coach`, `plan_proposals`, `approvePlan` transaction |
| Walking | Fixed configurable daily target, manual steps, weekly bars, health imports | Smart missed-target push and logged-data walking suggestions through Coach | `WalkingScreen`, `logWalk`, `addWalkSteps`, `saveTargets`; `daily_activities`, `dispatchReminders` |
| Protein | Configurable target and unlimited validated meal/protein logging | Allergy/preference/appetite-aware meal suggestions through Coach; low-appetite support screen | `ProteinScreen`, `addMeal`, `saveTargets`, GLP support screen; `protein_entries`, `goal_profiles`, `coach` |
| Weight tracking | Unlimited manual entries and four-week chart | Extended chart periods, weight-loss pace and strength-change review | `ProgressScreen`, `AppState.weights`, `ProgressMath.weeklyLossPercent`, server `metrics.ts`; `weight_entries` |
| Body measurements | Weight plus waist entry | Chest, hips, arm and thigh entry; history and comparison presentation | Measurements screen, `addMeasurement`; database Firestore Rules checks new premium measurement writes |
| Weekly review | Current week numbers and one AI summary each UTC calendar week | Detailed structured review with logged evidence and up to three next actions | Reports screen, `weekly_insights`, `coach` kind `weekly`, `reserve()` Firestore transaction |
| AI Lean Coach | Three questions per UTC calendar month plus one weekly summary | Up to 100 requests/month, twenty/day fair use, six reservations/minute, plan proposal requests | `CoachScreen`, `askCoach`; server `coach`, versioned JSON schema, consent check, timeouts, snapshot cache and non-AI fallbacks |
| GLP-1 support | Optional manual mode, clinician-supervision acknowledgement and safety information | Appetite/energy check-in, hydration reminder, protein-first coaching and clinician PDF/CSV export | GLP setup/support screens, `setGlp`, `saveGlpCheckIn`, `exportReport(clinician:true)`; medication preferences, daily energy, reminders |
| Health integration | Permission education and steps/weight imports; denial retains manual logging | Separate workout-write permission, active energy/workout reads and opt-in background refresh | `HealthService`, `BackgroundHealthService`; `health_connections`, `consent_records`, `syncHealthActivity` preserves manual rows and rechecks Pro/consent |
| Reminders | Up to 3 enabled fixed local reminders | Smart push suppression after a goal is met, quiet hours and more reminders | `NotificationService`, `PushService`, `toggleReminder`, `setQuietHours`; `dispatchReminders`, cron, owner-protected device tokens |
| Reports | Current week statistics | Monthly/all-time report selection and native PDF/CSV sharing | Reports screen, `ReportService`, `exportReport`; free `dataExport` remains independent of report presentation |
| Personalization | Goals, units and basic equipment | Schedule, session duration, limitations, exercise preferences, dietary context and coaching tone | Profile/goal/training preference screens; `goal_profiles`, `user_profiles`, coaching snapshot |
| Subscription | Free indefinitely, data remains readable after expiry | USD 19.99 monthly / USD 119.99 annual configured in stores; optional annual seven-day trial determined by actual store eligibility | `PaywallScreen`, `SubscriptionService`, `purchase`, `restorePurchases`, `manageSubscription`; `syncEntitlement`, RevenueCat webhook |

## Supporting flows

| Flow | Implementation |
| --- | --- |
| Email, Apple, Google sign-in and email recovery | `AuthService` and authentication/recovery screens use Firebase Authentication; redirect allowlist and native provider setup are required |
| Onboarding | Welcome → authentication → goals → optional GLP support → permission education → Today; profile completion is persisted |
| Add weight, measurements and protein | Validated forms persist canonical kg/cm/g values through the encrypted offline queue |
| Exercise details and workout summary | Exercise instructions/history; sets, skipped exercises, duration and logged volume summary |
| Health and notification denial | Dedicated education/state copy; declining access preserves all manual logging |
| Data export | `dataExport` returns owner-only JSON, internally paginated, regardless of subscription; native share sheet follows explicit user action |
| Delete account | Typed DELETE, recent sign-in, server recursive storage removal, RevenueCat customer deletion if configured, recursive Firestore cleanup and Auth deletion; store billing managed separately |
| Loading, empty, offline and failure states | Native loaders, no-data copy, encrypted persisted queue and retry state; AI failures cannot change a plan |
| Privacy | Separate health/AI/analytics/crash/notification consent, private Storage, per-user Firestore Rules and account-scoped local snapshots |

## Adaptive algorithms and explicit limits

`lib/features/insights/domain/adaptive_insights.dart` supplies dated logged-data walking adjustments/streak recovery, protein distribution and user-controlled conservative target changes, smoothed weight/plateau signals, wearable-informed habit readiness and descriptive step/energy correlation. Sparse data returns no recommendation; missing dates are not fabricated. `AdaptiveInsightsScreen` explains evidence and requires approval before saved targets change. These heuristics are not clinically validated or medical assessments. `test/adaptive_insights_test.dart` covers these boundaries.

`PlanBuilder` constructs starter/personalized sessions from equipment, selected days, duration and exercise preferences, with tests in `test/core/plan_builder_test.dart`. AI changes are proposed and approved separately. Current reminder automation suppresses missed-goal nudges when a goal is met and respects user-selected times/quiet hours; it does not predict an optimal delivery time from behavioral history. Proactive weekly insights run on a consented Pro app resume via `AppController.maybeProactiveInsight`, using the same server quotas and snapshot cache; the reminder scheduler does not silently transmit health logs to AI.

## Verification boundaries

`test/core/repository_test.dart` exercises account isolation, in-flight edits, offline retry, natural-key conflicts and immutable consent. `controller_test.dart` exercises onboarding, logging/skipping/completion, validation, Free gating, safety escalation, denial, restoration and AI failure. `entities_test.dart` round-trips all 20 domain models. Service and widget suites cover native boundaries and screens. The active Firebase backend is type-checked and tested against Firestore/Auth/Storage emulators, with mocked Responses transport tests. The retained Supabase migration reference has separate embedded PostgreSQL tests; it is not the deployed runtime. See [FIREBASE_SETUP.md](FIREBASE_SETUP.md).

Real Apple/Google authentication, HealthKit/Health Connect, store purchase/trial/grace/restore behavior, push transport and OpenAI responses need configured vendor accounts and physical-device/sandbox validation. Backend tests are not a claim of completed production deployment, medical validation or store review.
