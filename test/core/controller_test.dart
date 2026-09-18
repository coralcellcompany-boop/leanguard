import 'package:flutter_test/flutter_test.dart';
import 'package:leanguard/core/data/repository.dart';
import 'package:leanguard/core/services/health_service.dart';
import 'package:leanguard/core/services/notification_service.dart';
import 'package:leanguard/core/services/subscription_service.dart';
import 'package:leanguard/core/state.dart';
import 'repository_test.dart' show FakeRemote;

class TestController extends AppController {
  TestController(
    super.repository,
    super.subscriptions,
    super.health,
    super.notifications,
  );
  AppState get current => state;
  void seed(AppState value) {
    state = value;
  }
}

class TestSubscriptions extends SubscriptionService {
  int restoreCalls = 0;
  SubscriptionStatus restored = const SubscriptionStatus(isPro: true);
  @override
  Future<SubscriptionStatus> restore() async {
    restoreCalls++;
    return restored;
  }

  @override
  Future<void> signOut() async {}
}

class DeniedHealth extends HealthService {
  int reads = 0;
  @override
  Future<HealthAccess> requestAccess({bool pro = false}) async =>
      HealthAccess.denied;
  @override
  Future<HealthSnapshot> readToday({DateTime? now, bool pro = false}) async {
    reads++;
    return HealthSnapshot(date: DateTime.now(), access: HealthAccess.denied);
  }
}

class TestNotifications extends NotificationService {
  @override
  Future<void> initialize({void Function(String route)? onTap}) async {}
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<void> cancelAll() async {}
}

class FailingCoachRemote extends FakeRemote {
  @override
  Future<Json> invoke(String name, Json body) async {
    calls.add(name);
    if (name == 'coach') throw StateError('AI timeout');
    return {};
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late LeanRepository repository;
  late TestSubscriptions subscriptions;
  late DeniedHealth health;
  late TestController controller;
  setUp(() {
    repository = LeanRepository(store: MemoryLocalStore());
    subscriptions = TestSubscriptions();
    health = DeniedHealth();
    controller = TestController(
      repository,
      subscriptions,
      health,
      TestNotifications(),
    );
  });
  tearDown(() {
    controller.dispose();
    subscriptions.dispose();
  });
  test(
    'onboarding persists selected goals, optional GLP support and completion',
    () async {
      await controller.enterDemo();
      await controller.setGoals(['Keep my muscle', 'Get stronger']);
      await controller.setGlp(true);
      await controller.finishOnboarding();
      expect(controller.current.onboardingComplete, true);
      expect(controller.current.glpEnabled, true);
      expect(controller.current.goals, ['Keep my muscle', 'Get stronger']);
      expect(
        repository
            .rows('medication_support_preferences')
            .single['clinician_supervised'],
        true,
      );
      expect(
        repository.rows('consent_records').map((r) => r['kind']),
        containsAll(['terms', 'privacy']),
      );
      expect(repository.pending, isEmpty);
    },
  );
  test(
    'workout logs persist sets and skips; completion records duration and volume',
    () async {
      await controller.enterDemo();
      await controller.startWorkout('Upper body');
      final activeId = controller.current.activeWorkout!['id'];
      final exerciseRows = repository
          .rows('workout_exercises')
          .where((r) => r['workout_id'] == activeId)
          .toList();
      final exerciseId = exerciseRows.first['exercise_id'] as String;
      await controller.logSet(
        exerciseId: exerciseId,
        setNumber: 1,
        reps: 10,
        weightKg: 20,
      );
      await controller.logSet(
        exerciseId: exerciseId,
        setNumber: 2,
        reps: 8,
        weightKg: 20,
      );
      await controller.skipExercise(exerciseRows[1]['exercise_id'] as String);
      expect(repository.rows('workout_sets'), hasLength(2));
      await controller.finishWorkout();
      expect(controller.current.activeWorkout, isNull);
      expect(controller.current.lastWorkoutSummary!['workout_id'], activeId);
      expect(controller.current.lastWorkoutSummary!['sets'], 2);
      expect(controller.current.lastWorkoutSummary!['volume_kg'], 360);
      expect(
        repository
            .rows('workouts')
            .firstWhere((r) => r['id'] == activeId)['status'],
        'completed',
      );
      expect(
        repository
            .rows('workouts')
            .where(
              (r) => r['name'] == 'Upper body' && r['status'] == 'planned',
            ),
        isNotEmpty,
      );
    },
  );
  test('invalid logging is rejected before any persistence', () async {
    await controller.enterDemo();
    await expectLater(controller.addWeight(double.nan), throwsFormatException);
    await expectLater(
      controller.addMeal(' ', 30, 'lunch'),
      throwsFormatException,
    );
    await expectLater(
      controller.addMeal('Lunch', -1, 'lunch'),
      throwsFormatException,
    );
    await expectLater(controller.logWalk(-10), throwsFormatException);
    expect(repository.rows('weight_entries'), isEmpty);
    expect(repository.rows('protein_entries'), isEmpty);
  });
  test(
    'Free denies new premium measurements while keeping existing records',
    () async {
      await controller.enterDemo();
      await controller.addMeasurement('waist', 92);
      await expectLater(
        controller.addMeasurement('chest', 105),
        throwsStateError,
      );
      expect(repository.rows('body_measurements'), hasLength(1));
      await repository.put('body_measurements', {
        'id': 'old-pro',
        'chest_cm': 105,
      }, queue: false);
      controller.seed(
        controller.current.copy(records: Map.of(repository.records)),
      );
      expect(controller.current.measurements, hasLength(2));
    },
  );
  test(
    'medical warning receives deterministic escalation and never calls AI',
    () async {
      final remote = FakeRemote();
      final ownRepository = LeanRepository(
        store: MemoryLocalStore(),
        remote: remote,
      );
      await ownRepository.open('a');
      final own = TestController(
        ownRepository,
        subscriptions,
        health,
        TestNotifications(),
      );
      await own.askCoach('I fainted after exercise');
      expect(remote.calls, isEmpty);
      expect(own.current.messages.last['content'], contains('medical care'));
      expect(own.current.proposal, isNull);
      own.dispose();
    },
  );
  test(
    'health permission denial preserves manual functionality and records revocation',
    () async {
      await repository.open('a');
      await controller.connectHealth();
      expect(controller.current.healthAccess, HealthAccess.denied);
      expect(repository.rows('consent_records').single['granted'], false);
      expect(health.reads, 0);
      await controller.addWeight(80);
      expect(repository.rows('weight_entries').single['weight_kg'], 80);
    },
  );
  test(
    'purchase restoration updates entitlement and reconciles backend',
    () async {
      final remote = FakeRemote();
      final ownRepository = LeanRepository(
        store: MemoryLocalStore(),
        remote: remote,
      );
      await ownRepository.open('a');
      final own = TestController(
        ownRepository,
        subscriptions,
        health,
        TestNotifications(),
      );
      await own.restorePurchases();
      expect(subscriptions.restoreCalls, 1);
      expect(own.current.isPro, true);
      expect(remote.calls, ['sync-entitlement']);
      expect(own.current.purchasing, false);
      own.dispose();
    },
  );
  test(
    'AI failure leaves current plan unchanged and supplies a useful fallback',
    () async {
      final remote = FailingCoachRemote();
      final ownRepository = LeanRepository(
        store: MemoryLocalStore(),
        remote: remote,
      );
      await ownRepository.open('a');
      await ownRepository.put('consent_records', {
        'id': 'consent',
        'kind': 'ai_processing',
        'granted': true,
        'policy_version': 'v1',
      });
      await ownRepository.put('strength_plans', {
        'id': 'plan',
        'name': 'Starter',
        'version': 1,
      });
      final own = TestController(
        ownRepository,
        subscriptions,
        health,
        TestNotifications(),
      );
      await own.askCoach('How can I stay consistent?');
      expect(own.current.messages.last['fallback'], true);
      expect(ownRepository.rows('strength_plans').single['version'], 1);
      expect(own.current.busy, false);
      expect(own.current.proposal, isNull);
      own.dispose();
    },
  );
  test(
    'unavailable store offering never starts checkout or grants Pro',
    () async {
      await controller.enterDemo();
      await controller.purchase(true);
      expect(controller.current.isPro, false);
      expect(controller.current.purchasing, false);
      expect(
        controller.current.error,
        contains('Store products are unavailable'),
      );
    },
  );
}
