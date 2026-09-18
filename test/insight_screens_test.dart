import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:leanguard/core/state.dart';
import 'package:leanguard/features/insights/presentation/insight_screens.dart';
import 'package:leanguard/features/subscription/presentation/paywall_screen.dart';

import 'screens_test.dart' show ScreenTestController;

class InsightTestController extends ScreenTestController {
  InsightTestController({super.pro, bool adaptiveReady = false}) {
    final records = {
      ...state.records,
      if (adaptiveReady)
        'daily_activities': List.generate(
          7,
          (i) => {
            'id': 'adaptive-$i',
            'date': DateTime.now()
                .subtract(Duration(days: i + 1))
                .toIso8601String()
                .substring(0, 10),
            'steps': 9000,
            'source': 'manual',
          },
        ),
      'medication_support_preferences': [
        {
          'id': 'glp',
          'enabled': true,
          'clinician_supervised': true,
          'appetite_level': 'normal',
          'hydration_reminders': false,
        },
      ],
      'weekly_insights': [
        {
          'id': 'old-review',
          'week_start': '2025-01-06',
          'content': {
            'summary': 'Your saved review remains yours after expiration.',
          },
        },
      ],
      'workouts': [
        {
          'id': 'future',
          'status': 'planned',
          'name': 'Next upper body',
          'plan_id': 'plan',
        },
      ],
      'workout_exercises': [
        {
          'id': 'planned',
          'exercise_id': 'chest-press',
          'workout_id': 'future',
          'status': 'planned',
          'target_sets': 3,
          'target_reps': 10,
        },
      ],
      'exercises': [
        ...state.rows('exercises'),
        {
          'id': 'band-press',
          'name': 'Resistance band chest press',
          'equipment': 'bands',
          'muscle_group': 'chest',
        },
      ],
    };
    repository.records = records;
    state = state.copy(records: records);
  }
  Map<String, dynamic>? exported, checkIn;
  List<String>? savedEquipment;
  Map<String, dynamic>? personalization;
  List<String>? substituted;
  Map<String, int?>? appliedTarget;
  @override
  Future<void> exportReport({
    String format = 'csv',
    int days = 30,
    bool clinician = false,
  }) async {
    exported = {'format': format, 'days': days, 'clinician': clinician};
  }

  @override
  Future<void> saveGlpCheckIn(
    String appetite,
    int energy,
    bool hydration,
  ) async {
    checkIn = {'appetite': appetite, 'energy': energy, 'hydration': hydration};
  }

  @override
  Future<void> saveEquipment(List<String> equipment) async {
    savedEquipment = equipment;
  }

  @override
  Future<void> savePersonalization({
    required int minutes,
    required List<int> days,
    required List<String> limitations,
    required List<String> preferences,
    required String tone,
  }) async {
    personalization = {
      'minutes': minutes,
      'days': days,
      'limitations': limitations,
      'preferences': preferences,
      'tone': tone,
    };
  }

  @override
  Future<void> substituteExercise(
    String workoutExerciseId,
    String exerciseId,
  ) async {
    substituted = [workoutExerciseId, exerciseId];
  }

  @override
  Future<void> applyAdaptiveTarget({int? steps, int? protein}) async {
    appliedTarget = {'steps': steps, 'protein': protein};
  }
}

const _screens = <String, Widget>{
  '/reports': ReportsScreen(),
  '/glp-support': GlpSupportScreen(),
  '/personalization': PersonalizationScreen(),
  '/adaptive-insights': AdaptiveInsightsScreen(),
};

Future<InsightTestController> _pump(
  WidgetTester tester,
  String route, {
  bool pro = true,
  Size size = const Size(390, 844),
  double scale = 1,
  bool adaptiveReady = false,
}) async {
  final controller = InsightTestController(
    pro: pro,
    adaptiveReady: adaptiveReady,
  );
  final router = GoRouter(
    initialLocation: route,
    routes: [
      for (final entry in _screens.entries)
        GoRoute(path: entry.key, builder: (_, _) => entry.value),
      GoRoute(path: '/paywall', builder: (_, _) => const PaywallScreen()),
    ],
  );
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appProvider.overrideWith((ref) => controller)],
      child: RepaintBoundary(
        key: const ValueKey('insight-audit'),
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
  return controller;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    if (const bool.fromEnvironment('CAPTURE_UI')) {
      await (FontLoader(
        'MaterialIcons',
      )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
      final file = File(
        Platform.environment['AUDIT_FONT_PATH'] ??
            '/System/Library/Fonts/Supplemental/Arial.ttf',
      );
      if (await file.exists()) {
        await (FontLoader('AuditSans')..addFont(
              file.readAsBytes().then((bytes) => ByteData.sublistView(bytes)),
            ))
            .load();
      }
    }
  });

  for (final route in _screens.keys) {
    for (final pro in [false, true]) {
      for (final compact in [false, true]) {
        testWidgets(
          '$route ${pro ? 'Pro' : 'Free'} ${compact ? 'compact enlarged text' : 'standard layout'}',
          (tester) async {
            await _pump(
              tester,
              route,
              pro: pro,
              size: compact ? const Size(320, 568) : const Size(390, 844),
              scale: compact ? 1.3 : 1,
            );
            expect(tester.takeException(), isNull);
            if (const bool.fromEnvironment('CAPTURE_UI') && !compact && pro) {
              final boundary = tester.renderObject<RenderRepaintBoundary>(
                find.byKey(const ValueKey('insight-audit')),
              );
              await tester.runAsync(() async {
                final image = await boundary.toImage();
                final bytes = await image.toByteData(
                  format: ui.ImageByteFormat.png,
                );
                await Directory('build/ui-audit').create(recursive: true);
                await File(
                  'build/ui-audit/${route.substring(1)}.png',
                ).writeAsBytes(bytes!.buffer.asUint8List());
                image.dispose();
              });
            }
            await tester.pumpWidget(const SizedBox.shrink());
          },
        );
      }
    }
  }

  testWidgets('Free report period upgrade preserves old saved weekly reviews', (
    tester,
  ) async {
    await _pump(tester, '/reports', pro: false);
    await tester.ensureVisible(find.text('Week of 2025-01-06'));
    await tester.tap(find.text('Week of 2025-01-06'));
    await tester.pumpAndSettle();
    expect(
      find.text('Your saved review remains yours after expiration.'),
      findsOneWidget,
    );
    await tester.ensureVisible(find.text('This month'));
    await tester.tap(find.text('This month'));
    await tester.pumpAndSettle();
    expect(find.byType(PaywallScreen), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Pro PDF export passes selected reporting period', (
    tester,
  ) async {
    final controller = await _pump(tester, '/reports');
    await tester.tap(find.text('This month'));
    await tester.pump();
    await tester.ensureVisible(find.text('PDF report'));
    await tester.tap(find.text('PDF report'));
    await tester.pumpAndSettle();
    expect(controller.exported, {
      'format': 'pdf',
      'days': DateTime.now().day,
      'clinician': false,
    });
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('Free equipment preferences save without Pro', (tester) async {
    final controller = await _pump(tester, '/personalization', pro: false);
    await tester.tap(find.text('Dumbbells'));
    await tester.ensureVisible(find.text('Save equipment'));
    await tester.tap(find.text('Save equipment'));
    await tester.pumpAndSettle();
    expect(controller.savedEquipment, contains('dumbbells'));
    expect(find.byType(PaywallScreen), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'Pro GLP check-in passes appetite and energy without medication advice',
    (tester) async {
      final controller = await _pump(tester, '/glp-support');
      await tester.ensureVisible(find.text('Lower'));
      await tester.tap(find.text('Lower'));
      await tester.ensureVisible(find.text('Save check-in'));
      await tester.tap(find.text('Save check-in'));
      await tester.pumpAndSettle();
      expect(controller.checkIn, {
        'appetite': 'low',
        'energy': 3,
        'hydration': false,
      });
      expect(find.text('Your check-in is saved.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('planned exercise substitution requires confirmation', (
    tester,
  ) async {
    final controller = await _pump(tester, '/personalization');
    await tester.ensureVisible(find.text('Dumbbell chest press'));
    await tester.tap(find.text('Dumbbell chest press'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resistance band chest press'));
    await tester.pumpAndSettle();
    expect(controller.substituted, isNull);
    expect(find.text('Confirm exercise swap'), findsOneWidget);
    await tester.tap(find.text('Confirm swap'));
    await tester.pumpAndSettle();
    expect(controller.substituted, ['planned', 'band-press']);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('adaptive target remains unchanged until explicit approval', (
    tester,
  ) async {
    final controller = await _pump(
      tester,
      '/adaptive-insights',
      adaptiveReady: true,
    );
    await tester.ensureVisible(find.text('Review walking target'));
    await tester.tap(find.text('Review walking target'));
    await tester.pumpAndSettle();
    expect(controller.appliedTarget, isNull);
    expect(find.text('Update your walking target?'), findsOneWidget);
    await tester.tap(find.text('Approve target'));
    await tester.pumpAndSettle();
    expect(controller.appliedTarget, {'steps': 8250, 'protein': null});
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
