import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/state.dart';
import 'core/theme.dart';
import 'features/onboarding/presentation/onboarding_screens.dart';
import 'features/dashboard/presentation/main_screens.dart';
import 'features/workout/presentation/workout_screen.dart';
import 'features/coach/presentation/coach_screen.dart';
import 'features/subscription/presentation/paywall_screen.dart';
import 'features/support/presentation/support_screens.dart';
import 'features/insights/presentation/insight_screens.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final changes = ValueNotifier<int>(0);
  ref.listen(appProvider, (old, next) {
    if (old?.initialized != next.initialized ||
        old?.authenticated != next.authenticated ||
        old?.demo != next.demo ||
        old?.onboardingComplete != next.onboardingComplete ||
        old?.passwordRecovery != next.passwordRecovery) {
      changes.value++;
    }
  });
  final router = GoRouter(
    initialLocation: '/welcome',
    refreshListenable: changes,
    redirect: (context, route) {
      final s = ref.read(appProvider), path = route.uri.path;
      if (!s.initialized) return path == '/loading' ? null : '/loading';
      if (s.passwordRecovery && path != '/reset-password') {
        return '/reset-password';
      }
      final signedIn = s.authenticated || s.demo;
      const public = [
        '/welcome',
        '/auth',
        '/forgot-password',
        '/privacy',
        '/terms',
        '/auth-callback',
        '/reset-password',
      ];
      if (!signedIn && !public.contains(path)) return '/welcome';
      if (signedIn &&
          (path == '/welcome' ||
              path == '/auth' ||
              path == '/loading' ||
              path == '/auth-callback')) {
        return s.onboardingComplete ? '/today' : '/goals';
      }
      return null;
    },
    errorBuilder: (context, state) => Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('This page is unavailable.'),
            TextButton(
              onPressed: () => context.go('/today'),
              child: const Text('Return to Today'),
            ),
          ],
        ),
      ),
    ),
    routes: [
      GoRoute(
        path: '/loading',
        builder: (_, _) =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
      ),
      GoRoute(path: '/welcome', builder: (_, _) => const WelcomeScreen()),
      GoRoute(path: '/auth', builder: (_, _) => const AuthScreen()),
      GoRoute(path: '/auth-callback', builder: (_, _) => const AuthScreen()),
      GoRoute(
        path: '/reauth',
        builder: (_, _) => const AuthScreen(reauthenticate: true),
      ),
      GoRoute(
        path: '/forgot-password',
        builder: (_, _) => const AuthScreen(forgot: true),
      ),
      GoRoute(
        path: '/reset-password',
        builder: (_, _) => const AuthScreen(recovery: true),
      ),
      GoRoute(path: '/goals', builder: (_, _) => const GoalsScreen()),
      GoRoute(path: '/glp', builder: (_, _) => const GlpScreen()),
      GoRoute(
        path: '/health-permission',
        builder: (_, _) => const HealthPermissionScreen(),
      ),
      GoRoute(
        path: '/notification-permission',
        builder: (_, _) => const NotificationPermissionScreen(),
      ),
      GoRoute(path: '/today', builder: (_, _) => const TodayScreen()),
      GoRoute(path: '/plan', builder: (_, _) => const PlanScreen()),
      GoRoute(path: '/workout', builder: (_, _) => const WorkoutScreen()),
      GoRoute(
        path: '/workout-summary',
        builder: (_, _) => const WorkoutSummaryScreen(),
      ),
      GoRoute(
        path: '/exercise/:id',
        builder: (_, s) => ExerciseDetailsScreen(id: s.pathParameters['id']!),
      ),
      GoRoute(path: '/walking', builder: (_, _) => const WalkingScreen()),
      GoRoute(path: '/protein', builder: (_, _) => const ProteinScreen()),
      GoRoute(path: '/progress', builder: (_, _) => const ProgressScreen()),
      GoRoute(
        path: '/measurements',
        builder: (_, _) => const MeasurementsScreen(),
      ),
      GoRoute(path: '/coach', builder: (_, _) => const CoachScreen()),
      GoRoute(path: '/reminders', builder: (_, _) => const RemindersScreen()),
      GoRoute(path: '/settings', builder: (_, _) => const SettingsScreen()),
      GoRoute(path: '/paywall', builder: (_, _) => const PaywallScreen()),
      GoRoute(
        path: '/add-weight',
        builder: (_, _) => const EntryScreen(kind: 'weight'),
      ),
      GoRoute(
        path: '/add-measurement',
        builder: (_, _) => const EntryScreen(kind: 'measurement'),
      ),
      GoRoute(
        path: '/add-meal',
        builder: (_, _) => const EntryScreen(kind: 'meal'),
      ),
      GoRoute(
        path: '/add-steps',
        builder: (_, _) => const EntryScreen(kind: 'steps'),
      ),
      GoRoute(
        path: '/edit-profile',
        builder: (_, _) => const ProfileEditScreen(),
      ),
      GoRoute(
        path: '/targets',
        builder: (_, _) => const ProfileEditScreen(targets: true),
      ),
      GoRoute(path: '/privacy', builder: (_, _) => const PrivacyScreen()),
      GoRoute(
        path: '/terms',
        builder: (_, _) => const PrivacyScreen(terms: true),
      ),
      GoRoute(
        path: '/adaptive-insights',
        builder: (_, _) => const AdaptiveInsightsScreen(),
      ),
      GoRoute(path: '/reports', builder: (_, _) => const ReportsScreen()),
      GoRoute(
        path: '/glp-support',
        builder: (_, _) => const GlpSupportScreen(),
      ),
      GoRoute(
        path: '/personalization',
        builder: (_, _) => const PersonalizationScreen(),
      ),
      GoRoute(
        path: '/reminder-edit',
        builder: (_, s) => ReminderEditScreen(id: s.uri.queryParameters['id']),
      ),
      GoRoute(
        path: '/quiet-hours',
        builder: (_, _) => const QuietHoursScreen(),
      ),
    ],
  );
  final appController=ref.read(appProvider.notifier);
  appController.onNotificationTap = (route) =>
      router.go(route == '/strength' ? '/plan' : route);
  ref.onDispose(() {
    appController.onNotificationTap = null;
    router.dispose();
    changes.dispose();
  });
  return router;
});

class LeanGuardApp extends ConsumerStatefulWidget {
  const LeanGuardApp({super.key});
  @override
  ConsumerState<LeanGuardApp> createState() => _LeanGuardAppState();
}

class _LeanGuardAppState extends ConsumerState<LeanGuardApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Future.microtask(() => ref.read(appProvider.notifier).initialize());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      ref.read(appProvider.notifier).onResume();
    }
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'LeanGuard',
    debugShowCheckedModeBanner: false,
    theme: LG.theme(),
    routerConfig: ref.watch(routerProvider),
  );
}
