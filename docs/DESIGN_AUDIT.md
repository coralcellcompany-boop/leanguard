# LeanGuard prototype audit

Source reviewed: `/Users/mohamedhamouda/Downloads/LeanGuard-complete-design-and-implementation/app/page.tsx`, the complete `app/globals.css`, and `FEATURE_MATRIX.md`. The prototype defines **14** interactive screen components. Each has a native Flutter implementation; none uses a WebView, HTML, CSS injection, or embedded browser.

## Visual language

- Dark canvas `#121513`, paper `#F3F4EF`, primary lime `#B9F34A`, protein orange `#FF9F54`, walking blue `#65D9FF`.
- Compact uppercase labels; bold, tightly spaced headlines; muted explanatory text; rounded cards; circular habit progress; line icons.
- Dark welcome, Today, strength plan, live workout hero, progress, coach, and subscription screens. Light onboarding, habits, measurements, reminders and profile. Live workout transitions from its dark illustration area to a rounded paper logging panel.
- The prototype's five destinations are preserved: Today, Plan, Progress, Coach, You. Native app bars, safe areas, permission dialogs, keyboard handling and navigation replace its web phone frame and simulated status bar.
- Content uses scrollable layouts and flexible text. Small text from the scaled prototype has been increased to readable native sizes. Controls have tooltips/semantic labels and selection states.

## All 14 screens

| Prototype component | Native screen | Preserved composition and working interactions |
|---|---|---|
| Welcome | `WelcomeScreen` | Orbit illustration, lime strength mark, two-line promise, primary setup action, account entry. Setup enters native authentication before personal onboarding. A clearly marked local preview is available. |
| Goals | `GoalsScreen` | Paper background, onboarding progress, multi-select icon cards, selected checkmarks, validation requiring at least one goal, saved Continue action. |
| GLP | `GlpScreen` | Optional clinician-supervised toggle, progressive disclosure, explicit medication boundary, Continue / Not now actions. Advanced coaching is labeled Pro. |
| Today | `TodayScreen` | Personalized greeting, readiness/foundation card, real weekly completion indicators, three habit rings, coach insight, upcoming workout card. The account's logged data drives the values. |
| Plan | `PlanScreen` | Green gradient plan hero, progress bar, saved upcoming-session timeline, progression card, focus rows and exercise library. Free uses the starter schedule; Pro displays selected days and session length. Sessions open the persistent live workout; exercise rows open instructions/history. |
| Workout | `WorkoutScreen` | Dark exercise illustration, elapsed time, paper lower panel, set indicators, weight/repetition controls, complete/skip actions, finishing flow. Pro automatic rest countdown supports early dismissal. No upgrade interruption inside an active workout. |
| Walking | `WalkingScreen` | Large step statistic, blue progress track, seven-day activity bars, adaptive-coaching callout and 10/20-minute walk cards. Walk cards log actual user-entered steps. Health connection action is explicit. |
| Protein | `ProteinScreen` | Orange completion ring, remaining target card, meals list, manual add action and protein planner entry. Empty states do not fabricate meals or totals. |
| Progress | `ProgressScreen` | Period selector, native weight chart, measurement/strength cards, check-in and weekly coach entry. Four-week chart is Free; longer chart periods route to an explicit upgrade. All raw historical entries remain readable. |
| Measurements | `MeasurementsScreen` | Date strip, native body illustration with labels, measurement rows, add action and full saved-record access. Free can add waist; all historical measurements remain visible after expiration. |
| Coach | `CoachScreen` | Intro mark, conversational bubbles, suggested prompts and fixed composer. Renders structured evidence and up to three actions, opt-in data-processing consent, monthly allowance, non-AI fallback, weekly review and explicit plan-change approval. |
| Reminders | `RemindersScreen` | Quiet green intro card, icon/toggle list, quiet-hours card and device permission entry. Free fixed-reminder limit and Pro smart reminders/quiet hours are enforced by the controller as well as presented in the UI. |
| Settings | `SettingsScreen` | Profile header, connections, goals, medication-support toggle, reminders, subscription and privacy sections. Every row opens a native destination or updates persisted preferences. |
| Paywall | `PaywallScreen` | Lime Pro mark, product promise, checkmark benefit list and selectable annual/monthly cards. Uses localized RevenueCat prices, eligible trial state, restoration, subscription management, billing/cancellation states and unavailable-store handling. |

## Deliberate corrections to prototype-only behavior

1. The product promise is **“Lose weight. Keep your muscle.”** The prototype's alternate “Keep your strength” headline is replaced with the requested promise.
2. Hardcoded example identity, dates, 82 readiness, 6,218 steps, meals and progress claims are replaced with the signed-in account's records. Empty states invite logging. Local preview is explicitly labeled.
3. The prototype's “SAVE 38%” does not match $119.99 annually versus $19.99 monthly. The native paywall uses “BEST VALUE” and actual store prices rather than an incorrect savings figure. Purchase never grants Pro locally or simulates success.
4. The prototype grants several Pro features unconditionally and presents base health import as a Pro benefit. The native UI follows `FEATURE_MATRIX.md`: basic health import is Free, advanced health trends/workout sync are Pro, and consent remains separate from subscription.
5. An annual free trial is displayed only when the store confirms eligibility. Store-unavailable and preview states disable purchase while retaining Free access. App-store settings remain the cancellation mechanism.
6. Raw health records and chat history remain accessible after subscription expiration. The higher-tier gates apply to creating advanced analysis or adjustments, not reading existing personal records.
7. Clicking Add no longer increments fictional totals. Native validated forms create real protein, weight, measurement, step and workout records. Workout skips and completion persist.
8. Medical claims such as “healthy range” or “muscle protected” are not inferred from a decorative chart. Coaching explains the actual facts used; warning signs lead to professional care information. No medication dosage controls exist.

## Reproducible native UI checks

`test/screens_test.dart` renders all 14 primary screens at **390 × 844** and **320 × 568 with 1.3× text scaling**, checking for Flutter rendering exceptions. It exercises explicit Free-to-Pro gating, historical data access, unavailable-store trial behavior, additive walking logs, AI consent and urgent local responses after allowance exhaustion. `test/screens_navigation_test.dart` checks authentication navigation through the production router.

Run:

```sh
flutter test test/screens_test.dart test/screens_navigation_test.dart
flutter test test/screens_test.dart --dart-define=CAPTURE_UI=true
```

The optional capture writes native PNG renders to `build/ui-audit/<screen>.png`. All 14 captured screens were visually reviewed; the workout's nested theme retains the application's font, and compact layout issues found in the habit rings, plan metadata and measurements date row were corrected. These are diagnostic renders using fixture records apart from the current date; they are not pixel-perfect golden baselines. Capture loads Material icons and an available macOS Arial font for readable review; `AUDIT_FONT_PATH` can provide another local font. Simulator/device tests are still required for native permissions, actual platform fonts, keyboards, accessibility services, billing sheets, and platform-specific safe areas.

## Supporting insight screens

Four additional screens extend the same native design language:

| Screen | Working behavior |
|---|---|
| Reports | Free current-week statistics and saved reviews; Pro calendar periods and PDF/CSV export. Existing historical records and privacy export stay available after expiration. |
| GLP-1 routine support | Optional clinician-supervised mode and safety information; Pro appetite/energy check-ins, hydration reminders, consent-aware protein coaching and clinician-summary export. No medication dose controls. |
| Training preferences | Equipment selection for all plans; Pro schedule, session length, limitations, exercise preferences and coaching style. Planned exercise substitutions show a confirmation before saving. |
| Adaptive insights | Evidence from actual completed activity days, meal logs, weight history and paired wearable activity records. Sparse inputs show baseline states. Any suggested walking or user-requested protein target requires explicit approval before it changes. |

`test/insight_screens_test.dart` checks all four screens on both Free and Pro at **390 × 844** and **320 × 568 with 1.3× text scaling**, plus report export, historical-review access, equipment saving, GLP check-in, exercise substitution and target-approval flows. `test/adaptive_insights_test.dart` covers sparse logs, conservative target changes, recovery patterns, explicit protein requests, allergy filtering, descriptive weight plateaus and wearable correlation eligibility. The UI depends on the application controller, so the backend migration does not change navigation or entitlement rules.

```sh
flutter test test/insight_screens_test.dart test/adaptive_insights_test.dart
flutter test test/insight_screens_test.dart --dart-define=CAPTURE_UI=true
```

The four additional captures use the same `build/ui-audit` directory and were visually reviewed. Review corrected dark-chip contrast while retaining the application font. Updated Today and Plan captures verify data-driven upcoming sessions rather than prototype example schedules.
