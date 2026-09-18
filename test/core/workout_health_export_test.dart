import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:leanguard/core/data/repository.dart';
import 'package:leanguard/core/services/firebase_auth_service.dart';
import 'package:leanguard/core/services/health_service.dart';
import 'package:leanguard/core/services/notification_service.dart';
import 'package:leanguard/core/services/subscription_service.dart';
import 'package:leanguard/core/state.dart';

import 'lifecycle_test.dart' show LifecycleAuth, LifecycleUser;

class ExportHealth extends HealthService {
  bool allowed = true, succeeds = true;
  int permissionCalls = 0;
  final writes = <Map<String, DateTime>>[];
  final permissionStarted = Completer<void>();
  final writeStarted = Completer<void>();
  Completer<bool>? permission, result;
  @override
  Future<bool> requestWorkoutWriteAccess({required bool pro}) async {
    permissionCalls++;
    if (!permissionStarted.isCompleted) permissionStarted.complete();
    return permission?.future ?? allowed;
  }

  @override
  Future<bool> writeStrengthWorkout({
    required bool pro,
    required DateTime start,
    required DateTime end,
  }) async {
    writes.add({'start': start, 'end': end});
    if (!writeStarted.isCompleted) writeStarted.complete();
    return result?.future ?? succeeds;
  }
}

class ExportController extends AppController {
  ExportController(LeanRepository repo, ExportHealth health, LifecycleAuth auth)
    : super(
        repo,
        SubscriptionService(),
        health,
        NotificationService(),
        auth: FirebaseAuthService(auth),
      );
  AppState get current => state;
  void showSummary({
    String? workoutId = 'target',
    bool pro = true,
    bool demo = false,
  }) {
    state = AppState(
      initialized: true,
      authenticated: true,
      demo: demo,
      subscription: SubscriptionStatus(isPro: pro),
      records: Map.of(repository.records),
      lastWorkoutSummary: {
        'workout_id': workoutId,
        'workout_name': 'The selected workout',
        'duration_seconds': 1200,
        'sets': 3,
        'exercises': 1,
        'volume_kg': 300,
      },
    );
  }
}

Future<void> seedWorkouts(LeanRepository repository) async {
  for (final entry in [('target', 8), ('other', 10)]) {
    await repository.put('workouts', {
      'id': entry.$1,
      'name': '${entry.$1} session',
      'status': 'completed',
      'created_at': '2026-09-18T07:00:00Z',
      'started_at': DateTime.utc(2026, 9, 18, entry.$2).toIso8601String(),
      'completed_at': DateTime.utc(2026, 9, 18, entry.$2, 20).toIso8601String(),
    }, queue: false);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryLocalStore store;
  late LeanRepository repository;
  late LifecycleAuth auth;
  late ExportHealth health;
  late ExportController controller;
  setUp(() async {
    store = MemoryLocalStore();
    repository = LeanRepository(store: store);
    await repository.open('account-a');
    await seedWorkouts(repository);
    auth = LifecycleAuth()..user = LifecycleUser('account-a');
    health = ExportHealth();
    controller = ExportController(repository, health, auth)..showSummary();
  });
  tearDown(() {
    controller.dispose();
    controller.subscriptions.dispose();
  });

  test(
    'exports the summary workout exactly once and persists its marker',
    () async {
      await controller.syncWorkoutToHealth();
      expect(health.writes, [
        {
          'start': DateTime.utc(2026, 9, 18, 8),
          'end': DateTime.utc(2026, 9, 18, 8, 20),
        },
      ]);
      final target = repository.rows('workouts').first;
      expect(target['health_exported_at'], isA<String>());
      expect(repository.rows('workouts').last['health_exported_at'], isNull);
      final stamp = target['health_exported_at'];
      await controller.syncWorkoutToHealth();
      expect(health.writes, hasLength(1));
      expect(health.permissionCalls, 1);
      final restored = LeanRepository(store: store);
      await restored.open('account-a');
      expect(restored.rows('workouts').first['health_exported_at'], stamp);
    },
  );

  test(
    'simultaneous taps cannot issue duplicate permission or native writes',
    () async {
      health.permission = Completer<bool>();
      final first = controller.syncWorkoutToHealth();
      await health.permissionStarted.future;
      await expectLater(controller.syncWorkoutToHealth(), throwsStateError);
      health.permission!.complete(true);
      await first;
      expect(health.permissionCalls, 1);
      expect(health.writes, hasLength(1));
    },
  );

  test('native false result is a failure without an exported marker', () async {
    health.succeeds = false;
    await expectLater(controller.syncWorkoutToHealth(), throwsStateError);
    expect(repository.rows('workouts').first['health_exported_at'], isNull);
    health.succeeds = true;
    await controller.syncWorkoutToHealth();
    expect(health.writes, hasLength(2));
    expect(repository.rows('workouts').first['health_exported_at'], isNotNull);
  });

  test(
    'permission denial does not write and can be retried explicitly',
    () async {
      health.allowed = false;
      await expectLater(controller.syncWorkoutToHealth(), throwsStateError);
      expect(health.writes, isEmpty);
      expect(repository.rows('workouts').first['health_exported_at'], isNull);
      health.allowed = true;
      await controller.syncWorkoutToHealth();
      expect(health.writes, hasLength(1));
    },
  );

  test(
    'Free, preview and missing summary workout are rejected before permission',
    () async {
      for (final scenario in ['free', 'preview', 'missing']) {
        controller.showSummary(
          pro: scenario != 'free',
          demo: scenario == 'preview',
          workoutId: scenario == 'missing' ? null : 'target',
        );
        await expectLater(controller.syncWorkoutToHealth(), throwsStateError);
      }
      expect(health.permissionCalls, 0);
      expect(health.writes, isEmpty);
    },
  );

  test(
    'account switch while permission is pending stops the native write',
    () async {
      health.permission = Completer<bool>();
      final pending = controller.syncWorkoutToHealth();
      final rejection = expectLater(pending, throwsStateError);
      await health.permissionStarted.future;
      auth.user = LifecycleUser('account-b');
      await repository.open('account-b');
      await seedWorkouts(repository);
      controller.showSummary();
      health.permission!.complete(true);
      await rejection;
      expect(health.writes, isEmpty);
      expect(repository.rows('workouts').first['health_exported_at'], isNull);
    },
  );

  test(
    'missing or skipped workout never falls back to another completed one',
    () async {
      controller.showSummary(workoutId: 'deleted-workout');
      await expectLater(controller.syncWorkoutToHealth(), throwsStateError);
      await repository.put('workouts', {
        ...repository.rows('workouts').first,
        'status': 'skipped',
      }, queue: false);
      controller.showSummary();
      await expectLater(controller.syncWorkoutToHealth(), throwsStateError);
      expect(health.permissionCalls, 0);
      expect(health.writes, isEmpty);
    },
  );

  test('invalid workout timestamps are rejected before permission', () async {
    await repository.put('workouts', {
      ...repository.rows('workouts').first,
      'completed_at': '2026-09-18T07:59:00Z',
    }, queue: false);
    controller.showSummary();
    await expectLater(controller.syncWorkoutToHealth(), throwsStateError);
    expect(health.permissionCalls, 0);
    expect(health.writes, isEmpty);
  });

  test('entitlement loss during permission prevents native export', () async {
    health.permission = Completer<bool>();
    final pending = controller.syncWorkoutToHealth();
    final rejection = expectLater(pending, throwsStateError);
    await health.permissionStarted.future;
    controller.showSummary(pro: false);
    health.permission!.complete(true);
    await rejection;
    expect(health.writes, isEmpty);
  });

  test(
    'account switch during native write cannot mark the new account',
    () async {
      health.result = Completer<bool>();
      final pending = controller.syncWorkoutToHealth();
      final rejection = expectLater(pending, throwsStateError);
      await health.writeStarted.future;
      auth.user = LifecycleUser('account-b');
      await repository.open('account-b');
      await seedWorkouts(repository);
      controller.showSummary();
      health.result!.complete(true);
      await rejection;
      expect(repository.rows('workouts').first['health_exported_at'], isNull);
    },
  );
}
