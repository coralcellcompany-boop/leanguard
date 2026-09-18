import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:leanguard/core/data/repository.dart';
import 'package:leanguard/core/services/health_service.dart';
import 'package:leanguard/core/services/notification_service.dart';
import 'package:leanguard/core/services/subscription_service.dart';
import 'package:leanguard/core/state.dart';
import 'package:leanguard/features/coach/presentation/coach_screen.dart';
import 'package:leanguard/features/dashboard/presentation/main_screens.dart';
import 'package:leanguard/features/onboarding/presentation/onboarding_screens.dart';
import 'package:leanguard/features/subscription/presentation/paywall_screen.dart';
import 'package:leanguard/features/workout/presentation/workout_screen.dart';

class ScreenTestController extends AppController {
  ScreenTestController({
    bool pro = true,
    bool empty = false,
    bool authenticated = true,
    int coachUsed = 0,
  }) : super(
         LeanRepository(store: MemoryLocalStore()),
         SubscriptionService(),
         HealthService(),
         NotificationService(),
       ) {
    final today = DateTime.now().toIso8601String();
    final records = <String, List<Json>>{
      'user_profiles': [
        {
          'id': 'profile',
          'display_name': 'Maya Johnson',
          'units': 'imperial',
          'onboarding_completed': true,
        },
      ],
      'goal_profiles': [
        {
          'id': 'goals',
          'goals': ['Keep my muscle', 'Get stronger'],
          'step_target': 8000,
          'protein_target_g': 116,
        },
      ],
      'exercises': [
        {
          'id': 'chest-press',
          'name': 'Dumbbell chest press',
          'equipment': 'Dumbbell',
          'instructions': 'Lower slowly, then press with control.',
        },
      ],
      if (!empty) ...{
        'strength_plans': [
          {
            'id': 'plan',
            'name': 'Muscle retention foundation',
            'description': 'Build a repeatable strength routine.',
            'is_active': true,
          },
        ],
        'workouts': [
          for (var i = 0; i < 3; i++)
            {
              'id': 'planned-$i',
              'plan_id': 'plan',
              'name': ['Upper body', 'Lower body', 'Full body'][i],
              'status': 'planned',
              'scheduled_date': DateTime.now()
                  .add(Duration(days: i * 2))
                  .toIso8601String()
                  .substring(0, 10),
            },
        ],
        'consent_records': [
          {
            'id': 'consent',
            'purpose': 'ai_processing',
            'granted': true,
            'recorded_at': today,
          },
        ],
        'daily_activities': List.generate(
          7,
          (i) => {
            'id': 'day-$i',
            'date': DateTime.now()
                .subtract(Duration(days: i))
                .toIso8601String()
                .substring(0, 10),
            'steps': 6218 - i * 400,
          },
        ),
        'protein_entries': [
          {
            'id': 'meal',
            'name': 'Greek yogurt and berries',
            'protein_g': 28,
            'recorded_at': today,
          },
        ],
        'weight_entries': [
          {
            'id': 'weight-a',
            'weight_kg': 86.0,
            'recorded_at': DateTime.now()
                .subtract(const Duration(days: 14))
                .toIso8601String(),
          },
          {'id': 'weight-b', 'weight_kg': 84.5, 'recorded_at': today},
        ],
        'body_measurements': [
          {
            'id': 'measure',
            'waist_cm': 93.5,
            'chest_cm': 105.4,
            'hips_cm': 102.1,
            'recorded_at': today,
          },
        ],
        'coach_messages': [
          {
            'id': 'message',
            'role': 'assistant',
            'content':
                'Your recent logs help you choose the next comfortable step.',
            'evidence': ['Protein logged today: 28 g.'],
            'actions': ['Keep your next session comfortable.'],
          },
        ],
        'reminder_preferences': [
          {
            'id': 'reminder',
            'kind': 'workout',
            'enabled': true,
            'time_of_day': '18:00:00',
          },
        ],
      },
    };
    repository.records = records;
    repository.userId = 'preview';
    state = AppState(
      initialized: true,
      authenticated: authenticated,
      coachUsed: coachUsed,
      records: records,
      subscription: SubscriptionStatus(isPro: pro, willRenew: pro),
      activeWorkout: {
        'id': 'active',
        'name': 'Upper body',
        'started_at': today,
        'exercise_index': 0,
        'set_number': 1,
        'sets': <Json>[],
      },
    );
  }
  @override
  Future<void> loadOfferings() async {}
}

const screens = <String, Widget>{
  '/welcome': WelcomeScreen(),
  '/goals': GoalsScreen(),
  '/glp': GlpScreen(),
  '/today': TodayScreen(),
  '/plan': PlanScreen(),
  '/workout': WorkoutScreen(),
  '/walking': WalkingScreen(),
  '/protein': ProteinScreen(),
  '/progress': ProgressScreen(),
  '/measurements': MeasurementsScreen(),
  '/coach': CoachScreen(),
  '/reminders': RemindersScreen(),
  '/settings': SettingsScreen(),
  '/paywall': PaywallScreen(),
};

Future<GoRouter> pumpScreen(
  WidgetTester tester,
  String route, {
  Size size = const Size(390, 844),
  double scale = 1,
  bool pro = true,
  bool empty = false,
  int coachUsed = 0,
}) async {
  final errorHandler = FlutterError.onError;
  FlutterError.onError = (details) {
    FlutterError.dumpErrorToConsole(details, forceReport: true);
    errorHandler?.call(details);
  };
  addTearDown(() => FlutterError.onError = errorHandler);
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  final router = GoRouter(
    initialLocation: route,
    routes: [
      for (final entry in screens.entries)
        GoRoute(path: entry.key, builder: (_, _) => entry.value),
    ],
  );
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appProvider.overrideWith(
          (ref) => ScreenTestController(
            pro: pro,
            empty: empty,
            coachUsed: coachUsed,
          ),
        ),
      ],
      child: RepaintBoundary(
        key: const ValueKey('ui-audit'),
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
            useMaterial3: true,
            fontFamily: const bool.fromEnvironment('CAPTURE_UI')
                ? 'AuditSans'
                : null,
          ),
          routerConfig: router,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  addTearDown(() {
    router.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  return router;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (const bool.fromEnvironment('CAPTURE_UI')) {
      final icons = FontLoader('MaterialIcons')
        ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'));
      await icons.load();
      final file = File(
        Platform.environment['AUDIT_FONT_PATH'] ??
            '/System/Library/Fonts/Supplemental/Arial.ttf',
      );
      if (await file.exists()) {
        final loader = FontLoader('AuditSans')
          ..addFont(
            file.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
          );
        await loader.load();
      }
    }
  });
  for (final route in screens.keys) {
    testWidgets('$route renders at prototype size', (tester) async {
      await pumpScreen(tester, route, pro: route != '/paywall');
      expect(tester.takeException(), isNull);
      expect(find.byType(Scaffold), findsOneWidget);
      if (const bool.fromEnvironment('CAPTURE_UI')) {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('ui-audit')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 1);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory('build/ui-audit').create(recursive: true);
          await File(
            'build/ui-audit/${route.substring(1)}.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.pumpWidget(const SizedBox.shrink());
    });
    testWidgets('$route supports compact device and enlarged text', (
      tester,
    ) async {
      await pumpScreen(
        tester,
        route,
        size: const Size(320, 568),
        scale: 1.3,
        pro: false,
        empty: true,
      );
      expect(tester.takeException(), isNull);
      expect(find.byType(Scaffold), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('Free progress keeps all saved weight entries accessible', (
    tester,
  ) async {
    await pumpScreen(tester, '/progress', pro: false);
    await tester.ensureVisible(find.text('All your entries'));
    await tester.tap(find.text('All your entries'));
    await tester.pumpAndSettle();
    expect(find.text('Your weight entries'), findsOneWidget);
    expect(find.text('186.3 lb'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('plan renders the saved upcoming workout schedule', (
    tester,
  ) async {
    await pumpScreen(tester, '/plan');
    expect(find.text('Muscle retention foundation'), findsOneWidget);
    expect(find.text('Build a repeatable strength routine.'), findsOneWidget);
    expect(find.text('Upper body'), findsOneWidget);
    expect(find.text('Lower body'), findsOneWidget);
    expect(find.text('Full body'), findsOneWidget);
    expect(find.text('Your next session starts here.'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Free long-term chart navigates to explicit paywall', (
    tester,
  ) async {
    await pumpScreen(tester, '/progress', pro: false);
    await tester.tap(find.text('3M'));
    await tester.pumpAndSettle();
    expect(find.byType(PaywallScreen), findsOneWidget);
    expect(find.text('Restore purchases'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Unavailable store offers never promise a free trial', (
    tester,
  ) async {
    await pumpScreen(tester, '/paywall', pro: false);
    expect(find.text('Start 7-day free trial'), findsNothing);
    expect(find.text('Continue with annual'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('Continue with annual'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'walk entry validates and adds steps without replacing daily total',
    (tester) async {
      await pumpScreen(tester, '/walking');
      await tester.ensureVisible(find.text('Movement break'));
      await tester.tap(find.text('Movement break'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Log walk'));
      await tester.pump();
      expect(find.text('Enter 1–100,000 steps.'), findsOneWidget);
      await tester.enterText(find.byType(TextFormField), '1100');
      await tester.tap(find.text('Log walk'));
      await tester.pumpAndSettle();
      expect(find.text('7318'), findsNWidgets(2));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('coach asks for consent before personalized processing', (
    tester,
  ) async {
    await pumpScreen(tester, '/coach', empty: true, pro: false);
    await tester.enterText(
      find.byType(TextField),
      'How is my protein consistency?',
    );
    await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
    await tester.pumpAndSettle();
    expect(find.text('Enable personalized AI coaching?'), findsOneWidget);
    await tester.tap(find.text('Not now'));
    await tester.pumpAndSettle();
    expect(find.text('Enable personalized AI coaching?'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'urgent local safety response is not blocked by quota or AI consent',
    (tester) async {
      await pumpScreen(tester, '/coach', empty: true, pro: false, coachUsed: 3);
      await tester.enterText(find.byType(TextField), 'I have chest pain');
      await tester.tap(find.byIcon(Icons.arrow_forward_rounded));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('Stop exercising and seek medical care promptly.'),
        findsOneWidget,
      );
      expect(find.text('Enable personalized AI coaching?'), findsNothing);
      expect(find.byType(PaywallScreen), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );
}
