import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:leanguard/app.dart';
import 'package:leanguard/core/data/repository.dart';
import 'package:leanguard/core/state.dart';

/// Native navigation, validation and persistence acceptance without credentials.
/// Real store checkout, OAuth and health APIs have separate sandbox/device checks.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'native preview onboarding, logs, workout and permission/paywall fallbacks',
    (tester) async {
      // Exercise the actual platform Keychain/Keystore plugin under a dedicated
      // non-user key; the preview's sample records stay isolated in memory.
      const nativeStore = SecureLocalStore();
      final storageKey =
          'leanguard.integration.${DateTime.now().microsecondsSinceEpoch}';
      try {
        await nativeStore.write(storageKey, 'native-storage-round-trip');
        expect(await nativeStore.read(storageKey), 'native-storage-round-trip');
      } finally {
        await nativeStore.delete(storageKey);
      }
      final store = MemoryLocalStore();
      final repository = LeanRepository(store: store);
      final container = ProviderContainer(
        overrides: [repositoryProvider.overrideWithValue(repository)],
      );
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const LeanGuardApp(),
        ),
      );
      await tester.pumpAndSettle();
      Future<void> tap(String label) async {
        final target = find.text(label).last;
        await tester.ensureVisible(target);
        await tester.tap(target);
        await tester.pumpAndSettle();
      }

      Future<void> route(String path) async {
        container.read(routerProvider).push(path);
        await tester.pumpAndSettle();
      }

      Finder input(String label) => find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == label,
      );

      expect(find.text('Lose weight.'), findsOneWidget);
      await tap('Build my plan');
      await tap('Explore local preview');
      expect(find.text('Keep my muscle'), findsOneWidget);
      await tap('Continue');
      await tap('Not now');
      await tap('Choose what to share');
      expect(
        find.textContaining('Health integration is unavailable'),
        findsOneWidget,
      );
      await tap('Continue with manual logging');
      expect(container.read(appProvider).onboardingComplete, isTrue);

      await route('/add-weight');
      await tester.enterText(input('kg'), '0');
      await tap('Save entry');
      expect(repository.rows('weight_entries'), isEmpty);
      await tester.enterText(input('kg'), '84.2');
      await tap('Save entry');
      expect(repository.rows('weight_entries').single['weight_kg'], 84.2);

      await route('/add-meal');
      await tester.enterText(input('Meal or food'), 'Yogurt and berries');
      await tester.enterText(input('g protein'), '28');
      await tap('Save entry');
      expect(container.read(appProvider).proteinToday, 28);

      await route('/workout');
      await tap('Start workout');
      final workoutId = container.read(appProvider).activeWorkout!['id'];
      await tester.ensureVisible(find.byTooltip('Increase REPS'));
      await tester.tap(find.byTooltip('Increase REPS'));
      await tap('Complete set');
      expect(repository.rows('workout_sets'), hasLength(1));
      await tap('Skip exercise');
      await tap('Finish session early');
      await tap('Finish session');
      expect(find.text('You showed up.'), findsOneWidget);
      expect(container.read(appProvider).lastWorkoutSummary?['sets'], 1);
      expect(
        repository
            .rows('workouts')
            .firstWhere((row) => row['id'] == workoutId)['status'],
        'completed',
      );

      await route('/notification-permission');
      await tap('Allow notifications');
      expect(
        find.textContaining(
          'Notifications are unavailable or permission was denied',
        ),
        findsOneWidget,
      );
      await route('/paywall');
      expect(
        find.textContaining('Purchases are unavailable in sample preview'),
        findsOneWidget,
      );
      final restore = tester.widget<TextButton>(
        find
            .ancestor(
              of: find.text('Restore purchases'),
              matching: find.byType(TextButton),
            )
            .first,
      );
      expect(restore.onPressed, isNull);
      expect(container.read(appProvider).isPro, isFalse);

      final reopened = LeanRepository(store: store);
      await reopened.open('preview');
      expect(reopened.rows('weight_entries'), hasLength(1));
      expect(reopened.rows('protein_entries'), hasLength(1));
      expect(reopened.rows('workout_sets'), hasLength(1));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
      container.dispose();
    },
  );
}
