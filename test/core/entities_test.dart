import 'package:flutter_test/flutter_test.dart';
import 'package:leanguard/core/domain/entities.dart';

void main() {
  final base = <String, dynamic>{
    'id': '11111111-1111-4111-8111-111111111111',
    'user_id': '22222222-2222-4222-8222-222222222222',
    'created_at': '2026-09-18T10:00:00.000Z',
  };
  final records = <String, Map<String, dynamic>>{
    'user_profiles': {},
    'goal_profiles': {},
    'health_connections': {'provider': 'apple_health'},
    'medication_support_preferences': {},
    'strength_plans': {'name': 'Starter'},
    'workouts': {'name': 'Upper body'},
    'exercises': {'name': 'Squat'},
    'workout_exercises': {'workout_id': 'workout', 'exercise_id': 'exercise'},
    'workout_sets': {
      'workout_exercise_id': 'session-exercise',
      'set_number': 1,
      'reps': 10,
    },
    'daily_targets': {'date': '2026-09-18'},
    'daily_activities': {'date': '2026-09-18'},
    'protein_entries': {
      'name': 'Lunch',
      'protein_g': 32.5,
      'recorded_at': '2026-09-18T12:00:00Z',
    },
    'weight_entries': {
      'weight_kg': 80.5,
      'recorded_at': '2026-09-18T07:00:00Z',
    },
    'body_measurements': {
      'waist_cm': 92.5,
      'recorded_at': '2026-09-18T07:00:00Z',
    },
    'weekly_insights': {
      'week_start': '2026-09-14',
      'snapshot_hash': 'abc',
      'prompt_version': 'v1',
      'content': {'summary': 'Steady work'},
    },
    'coach_conversations': {},
    'coach_messages': {
      'conversation_id': 'conversation',
      'role': 'assistant',
      'content': 'Keep it manageable.',
    },
    'reminder_preferences': {'kind': 'walking', 'title': 'Walk'},
    'subscription_entitlements': {'verified_at': '2026-09-18T07:00:00Z'},
    'consent_records': {
      'kind': 'ai_processing',
      'granted': false,
      'policy_version': 'v1',
    },
  };
  for (final entry in records.entries) {
    test(
      '${entry.key} serializes canonical database field names and round trips',
      () {
        final entity = OwnedEntity.fromTable(entry.key, {
          ...base,
          ...entry.value,
        });
        expect(entity.table, entry.key);
        expect(entity.id, base['id']);
        expect(entity.userId, base['user_id']);
        final json = entity.toJson();
        expect(OwnedEntity.fromTable(entry.key, json).toJson(), json);
        expect(json['created_at'], '2026-09-18T10:00:00.000Z');
        expect(json.containsKey('userId'), false);
      },
    );
  }
  test(
    'numeric database strings are normalized and nonfinite/fractional integers rejected',
    () {
      final weight = WeightEntry.fromJson({
        ...base,
        'weight_kg': '81.25',
        'recorded_at': '2026-09-18T12:00:00+03:00',
      });
      expect(weight.weightKg, 81.25);
      expect(weight.recordedAt.hour, 9);
      expect(
        () => WeightEntry.fromJson({
          ...base,
          'weight_kg': 'NaN',
          'recorded_at': '2026-09-18',
        }),
        throwsFormatException,
      );
      expect(
        () => WorkoutSet.fromJson({
          ...base,
          'workout_exercise_id': 'w',
          'set_number': 1,
          'reps': 10.5,
        }),
        throwsFormatException,
      );
    },
  );
  test('calendar dates preserve their day while instants serialize in UTC', () {
    final target = DailyTarget.fromJson({...base, 'date': '2026-09-18'});
    expect(target.date.isUtc, true);
    expect(target.toJson()['date'], '2026-09-18');
    final profile = UserProfile.fromJson(base);
    expect(profile.toJson().containsKey('updated_at'), false);
  });
  test('collections are immutable and require ownership', () {
    final values = ['dumbbell'];
    final goal = GoalProfile(
      id: base['id'],
      userId: base['user_id'],
      createdAt: DateTime.utc(2026),
      equipment: values,
    );
    values.add('barbell');
    expect(goal.equipment, ['dumbbell']);
    expect(() => goal.equipment.add('bench'), throwsUnsupportedError);
    expect(
      () => UserProfile.fromJson({'id': 'id', 'created_at': '2026-09-18'}),
      throwsFormatException,
    );
  });
  test(
    'entitlement access honors expiry and grace without treating cancellation as immediate expiry',
    () {
      final entitlement = SubscriptionEntitlement.fromJson({
        ...base,
        'is_active': true,
        'status': 'cancelled',
        'verified_at': '2026-09-18',
        'expires_at': '2026-09-20',
        'grace_period_expires_at': '2026-09-22',
      });
      expect(entitlement.hasAccessAt(DateTime.utc(2026, 9, 21)), true);
      expect(entitlement.hasAccessAt(DateTime.utc(2026, 9, 22)), false);
    },
  );
}
