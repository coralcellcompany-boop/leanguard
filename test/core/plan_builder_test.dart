import 'package:flutter_test/flutter_test.dart';
import 'package:leanguard/features/plan/domain/plan_builder.dart';

void main() {
  final library = [
    {
      'id': 'a',
      'name': 'Squat',
      'equipment': 'Dumbbell',
      'muscle_group': 'legs',
    },
    {
      'id': 'b',
      'name': 'Chair squat',
      'equipment': 'Bodyweight',
      'muscle_group': 'legs',
    },
    {
      'id': 'c',
      'name': 'Wall press',
      'equipment': 'Bodyweight',
      'muscle_group': 'chest',
    },
    {
      'id': 'd',
      'name': 'Row',
      'equipment': 'Bodyweight',
      'muscle_group': 'back',
    },
  ];
  test(
    'Free starter remains three days and uses selected available equipment',
    () {
      final result = PlanBuilder.build(
        library: library,
        equipment: ['Bodyweight'],
        days: [2],
        minutes: 10,
        personalized: false,
        now: DateTime(2026, 9, 18),
      );
      expect(result, hasLength(3));
      expect(result.every((r) => !r.exerciseIds.contains('a')), true);
      expect(result.map((r) => r.date.weekday), [1, 4, 6]);
    },
  );
  test('Pro schedule/time/preferences affect actual future sessions', () {
    final result = PlanBuilder.build(
      library: library,
      equipment: ['Bodyweight'],
      days: [2, 5],
      minutes: 15,
      personalized: true,
      now: DateTime(2026, 9, 18),
      preferredExercises: ['Wall'],
    );
    expect(result, hasLength(2));
    expect(result.map((r) => r.date.weekday), [2, 5]);
    expect(result.every((r) => r.sets == 2 && r.exerciseIds.length <= 2), true);
  });
  test('Empty library returns an empty plan without fake exercises', () {
    expect(
      PlanBuilder.build(
        library: [],
        equipment: [],
        days: [1],
        minutes: 35,
        personalized: true,
      ),
      isEmpty,
    );
  });
}
