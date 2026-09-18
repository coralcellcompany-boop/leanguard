import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leanguard/core/data/repository.dart';
import 'package:leanguard/core/state.dart';
import 'package:leanguard/features/support/presentation/support_screens.dart';

import '../core/lifecycle_test.dart' show LifecycleAuth, LifecycleUser;
import '../core/workout_health_export_test.dart'
    show ExportController, ExportHealth, seedWorkouts;

Future<ExportHealth> _launch(WidgetTester tester) async {
  final repository = LeanRepository(store: MemoryLocalStore());
  await repository.open('account-a');
  await seedWorkouts(repository);
  final auth = LifecycleAuth()..user = LifecycleUser('account-a');
  final health = ExportHealth();
  final controller = ExportController(repository, health, auth)..showSummary();
  addTearDown(() {
    unawaited(controller.subscriptions.dispose());
  });
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [appProvider.overrideWith((ref) => controller)],
      child: const MaterialApp(home: WorkoutSummaryScreen()),
    ),
  );
  return health;
}

OutlinedButton _button(WidgetTester tester, String label) =>
    tester.widget<OutlinedButton>(
      find.ancestor(
        of: find.text(label),
        matching: find.byType(OutlinedButton),
      ),
    );

void main() {
  testWidgets('saved export has a disabled Shared with Health state', (
    tester,
  ) async {
    final health = await _launch(tester);
    await tester.tap(find.text('Share workout with Health'));
    await tester.pumpAndSettle();
    expect(find.text('Shared with Health'), findsOneWidget);
    expect(_button(tester, 'Shared with Health').onPressed, isNull);
    expect(health.writes, hasLength(1));
    expect(find.text('Workout shared with your health app.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('permission sheet pending disables additional share taps', (
    tester,
  ) async {
    final health = await _launch(tester);
    health.permission = Completer<bool>();
    await tester.tap(find.text('Share workout with Health'));
    await tester.pump();
    expect(_button(tester, 'Sharing workout…').onPressed, isNull);
    expect(health.writes, isEmpty);
    health.permission!.complete(true);
    await tester.pumpAndSettle();
    expect(find.text('Shared with Health'), findsOneWidget);
    expect(health.writes, hasLength(1));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('native failure does not show successful or shared UI', (
    tester,
  ) async {
    final health = await _launch(tester);
    health.succeeds = false;
    await tester.tap(find.text('Share workout with Health'));
    await tester.pumpAndSettle();
    expect(find.text('Shared with Health'), findsNothing);
    expect(find.text('Workout shared with your health app.'), findsNothing);
    expect(
      find.text('Your health app did not save this workout. Try again.'),
      findsOneWidget,
    );
    expect(_button(tester, 'Share workout with Health').onPressed, isNotNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
