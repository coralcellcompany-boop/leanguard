import 'dart:convert';
import 'dart:io';
import 'package:firebase_auth/firebase_auth.dart' as firebase;
import 'package:leanguard/core/data/api_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:leanguard/app.dart';
import 'package:leanguard/core/data/repository.dart';
import 'package:leanguard/core/state.dart';

class NativeApiTestUser extends Fake implements firebase.User {
  NativeApiTestUser(this.uid);
  @override
  final String uid;
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async =>
      'native-loopback-test-token';
}

class NativeApiTestAuth extends Fake implements firebase.FirebaseAuth {
  @override
  firebase.User? currentUser = NativeApiTestUser('native-api-test');
}

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
  testWidgets(
    'native API sockets preserve authentication, records and account boundaries',
    (tester) async {
      await tester.runAsync(() async {
        // This fixture binds only the simulator's own loopback interface. It
        // verifies native HTTP transport without contacting a live user backend.
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final auth = NativeApiTestAuth();
        var switchOwner = false;
        var requests = 0;
        final listener = server.listen((request) async {
          requests++;
          expect(
            request.headers.value(HttpHeaders.authorizationHeader),
            'Bearer native-loopback-test-token',
          );
          expect(request.uri.path, '/v1/records/weight_entries');
          expect(request.uri.queryParameters, {'offset': '0', 'limit': '100'});
          if (switchOwner) {
            auth.currentUser = NativeApiTestUser('another-account');
          }
          request.response.headers.contentType = ContentType.json;
          request.response.write(
            jsonEncode({
              'records': [
                {
                  'id': 'native-weight',
                  'user_id': 'native-api-test',
                  'weight_kg': 82.3,
                },
              ],
            }),
          );
          await request.response.close();
        });
        final remote = ApiRepositoryRemote(
          auth: auth,
          baseUrl: 'http://127.0.0.1:${server.port}',
          allowLocalHttp: true,
          releaseMode: false,
        );
        try {
          final rows = await remote.readPage(
            'weight_entries',
            'native-api-test',
            0,
            100,
          );
          expect(rows.single['weight_kg'], 82.3);
          switchOwner = true;
          await expectLater(
            remote.readPage('weight_entries', 'native-api-test', 0, 100),
            throwsStateError,
          );
          expect(requests, 2);
        } finally {
          remote.dispose();
          await server.close(force: true);
          await listener.cancel();
        }
      });
    },
  );
}
