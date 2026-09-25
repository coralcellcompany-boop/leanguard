import 'package:flutter_test/flutter_test.dart';
import 'package:leanguard/core/data/repository.dart';
import 'package:leanguard/core/services/health_service.dart';
import 'package:leanguard/core/services/notification_service.dart';
import 'package:leanguard/core/services/subscription_service.dart';
import 'package:leanguard/core/state.dart';

class PlanExpiryController extends AppController {
  PlanExpiryController(LeanRepository repository)
    : super(
        repository,
        SubscriptionService(),
        HealthService(),
        NotificationService(),
      );
  void showAccount({required bool pro}) {
    state = AppState(
      initialized: true,
      authenticated: true,
      subscription: SubscriptionStatus(isPro: pro),
      records: Map.of(repository.records),
    );
  }

  // The test exercises the persisted mutation queue; transport is covered by
  // API tests and server policy tests without introducing background test work.
  @override
  Future<void> refresh() async {}
}

Future<LeanRepository> accountWithPaidPlan(String source) async {
  final repository = LeanRepository(store: MemoryLocalStore());
  await repository.open('account-a');
  Future<void> put(String table, Json row) => repository.put(table, {
    'created_at': '2026-09-20T00:00:00Z',
    ...row,
  }, queue: false);
  await put('goal_profiles', {
    'id': 'goal',
    'training_days': [2, 5],
    'session_minutes': 15,
    'workouts_per_week': 2,
    'equipment': ['Dumbbell'],
  });
  await put('strength_plans', {
    'id': 'existing-plan',
    'name': 'Personalized two-day plan',
    'description': 'Two short personalized sessions.',
    'source': source,
    'is_active': true,
    'version': 7,
    'schedule': [
      {'day': 2},
      {'day': 5},
    ],
  });
  for (final exercise in [
    {
      'id': 'squat',
      'name': 'Chair squat',
      'equipment': 'Bodyweight',
      'muscle_group': 'legs',
    },
    {
      'id': 'press',
      'name': 'Wall press',
      'equipment': 'Bodyweight',
      'muscle_group': 'chest',
    },
    {
      'id': 'dumbbell',
      'name': 'Dumbbell row',
      'equipment': 'Dumbbell',
      'muscle_group': 'back',
    },
  ]) {
    await put('exercises', exercise);
  }
  await put('workouts', {
    'id': 'completed-session',
    'plan_id': 'existing-plan',
    'name': 'My completed workout',
    'status': 'completed',
    'duration_seconds': 900,
  });
  await put('workouts', {
    'id': 'future-session',
    'plan_id': 'existing-plan',
    'name': 'Custom future workout',
    'status': 'planned',
    'duration_seconds': 0,
  });
  return repository;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final source in ['manual', 'coach']) {
    test(
      'equipment change after $source plan expires rebuilds canonical Free plan and keeps history',
      () async {
        final repository = await accountWithPaidPlan(source);
        final controller = PlanExpiryController(repository)
          ..showAccount(pro: false);
        addTearDown(() async {
          controller.dispose();
          await controller.subscriptions.dispose();
        });
        final historyBefore = Json.from(repository.rows('workouts').first);
        await controller.saveEquipment(['Bodyweight']);
        final plan = repository.rows('strength_plans').single;
        expect(plan['id'], 'existing-plan');
        expect(plan['name'], 'Muscle retention foundation');
        expect(
          plan['description'],
          'A starter 3-day plan. Start with a comfortable load and controlled repetitions.',
        );
        expect(plan['source'], 'starter');
        expect(plan['version'], 8);
        expect((plan['schedule'] as List).map((day) => day['day']), [1, 4, 6]);
        final future = repository
            .rows('workouts')
            .where((workout) => workout['status'] == 'planned')
            .toList();
        expect(future, hasLength(3));
        expect(
          future.map(
            (workout) => DateTime.parse(workout['scheduled_date']).weekday,
          ),
          [1, 4, 6],
        );
        expect(
          repository
              .rows('workout_exercises')
              .every(
                (exercise) =>
                    exercise['exercise_id'] != 'dumbbell' &&
                    exercise['target_sets'] == 3,
              ),
          isTrue,
        );
        expect(
          repository
              .rows('workouts')
              .firstWhere((workout) => workout['id'] == 'completed-session'),
          historyBefore,
        );
        expect(
          repository
              .rows('workouts')
              .firstWhere(
                (workout) => workout['id'] == 'future-session',
              )['status'],
          'skipped',
        );
        expect(repository.rows('goal_profiles').single['training_days'], [
          2,
          5,
        ]);
        expect(
          repository.pending.firstWhere(
            (mutation) => mutation['table'] == 'strength_plans',
          )['row'],
          plan,
        );
      },
    );
  }

  test(
    'active Pro equipment changes preserve personalized days and description',
    () async {
      final repository = await accountWithPaidPlan('manual');
      final controller = PlanExpiryController(repository)
        ..showAccount(pro: true);
      addTearDown(() async {
        controller.dispose();
        await controller.subscriptions.dispose();
      });
      await controller.saveEquipment(['Bodyweight']);
      final plan = repository.rows('strength_plans').single;
      expect(plan['source'], 'manual');
      expect(plan['description'], 'Two short personalized sessions.');
      expect(plan['version'], 8);
      expect((plan['schedule'] as List).map((day) => day['day']), [2, 5]);
      expect(
        repository
            .rows('workouts')
            .where((workout) => workout['status'] == 'planned'),
        hasLength(2),
      );
    },
  );
}
