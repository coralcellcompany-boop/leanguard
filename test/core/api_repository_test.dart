import 'package:flutter_test/flutter_test.dart';
import 'package:leanguard/core/data/api_repository.dart';
import 'package:leanguard/core/data/repository.dart';

void main() {
  group('API record identity', () {
    test('singleton paths use the account owner rather than local row IDs', () {
      for (final table in LeanRepository.singletons) {
        expect(
          ApiRepositoryRemote.documentId(table, {
            'id': 'local-profile-id',
            'user_id': 'account-a',
          }),
          'account-a',
        );
      }
      expect(
        ApiRepositoryRemote.documentId('subscription_entitlements', {
          'id': 'event-id',
          'user_id': 'account-a',
        }),
        'pro',
      );
    });

    test(
      'repeated daily and provider imports share a natural document key',
      () {
        for (final table in ['daily_activities', 'daily_targets']) {
          final first = {
            'id': 'first-device-row',
            'date': '2026-09-18',
            'steps': 7000,
          };
          final second = {...first, 'id': 'second-device-row', 'steps': 7100};
          expect(ApiRepositoryRemote.documentId(table, first), '2026-09-18');
          expect(
            ApiRepositoryRemote.documentId(table, second),
            ApiRepositoryRemote.documentId(table, first),
          );
          expect(first['id'], 'first-device-row');
        }
        expect(
          ApiRepositoryRemote.documentId('health_connections', {
            'id': 'connection-id',
            'provider': 'health_connect',
          }),
          'health_connect',
        );
      },
    );

    test(
      'set paths deduplicate the same exercise position but separate sets',
      () {
        final row = {
          'id': 'new-set-id',
          'workout_exercise_id': 'exercise-in-workout',
          'set_number': 2,
        };
        expect(
          ApiRepositoryRemote.documentId('workout_sets', row),
          'exercise-in-workout_2',
        );
        expect(
          ApiRepositoryRemote.documentId('workout_sets', {
            ...row,
            'id': 'retry-set-id',
          }),
          'exercise-in-workout_2',
        );
        expect(
          ApiRepositoryRemote.documentId('workout_sets', {
            ...row,
            'set_number': 3,
          }),
          'exercise-in-workout_3',
        );
      },
    );

    test('imported weight keys match the backend SHA-256 source identity', () {
      final row = {
        'id': 'local-weight-id',
        'source': 'apple_health',
        'external_id': 'weight/sample:1',
      };
      final id = ApiRepositoryRemote.documentId('weight_entries', row);
      expect(
        id,
        'ddb5635417ad40a98e053708ff96f8a3ae3ac2b7527747759b98efa601bfdd53',
      );
      expect(id, matches(RegExp(r'^[a-f0-9]{64}$')));
      expect(
        ApiRepositoryRemote.documentId('weight_entries', {
          ...row,
          'id': 'retry-local-id',
        }),
        id,
      );
      expect(
        ApiRepositoryRemote.documentId('weight_entries', {
          ...row,
          'source': 'health_connect',
        }),
        isNot(id),
      );
    });

    test('ordinary row IDs retain the identity used by parent references', () {
      for (final table in [
        'strength_plans',
        'workouts',
        'exercises',
        'workout_exercises',
        'protein_entries',
        'body_measurements',
        'coach_conversations',
      ]) {
        expect(
          ApiRepositoryRemote.documentId(table, {'id': '$table-id'}),
          '$table-id',
        );
      }
      expect(
        ApiRepositoryRemote.documentId('weight_entries', {
          'id': 'manual-weight',
          'source': 'manual',
          'external_id': null,
        }),
        'manual-weight',
      );
    });
  });

  group('JSON value normalization', () {
    test('UTC JSON timestamps remain strings without losing scalar values', () {
      final instant = DateTime.utc(2026, 9, 18, 8, 35, 12, 123, 456);
      final timestamp = instant.toUtc().toIso8601String();
      final input = <Object, Object?>{
        'created_at': timestamp,
        'nested': [
          {'at': timestamp, 'steps': 8000, 'weight': 84.2},
          null,
          true,
          '2026-09-18',
        ],
        7: false,
      };
      final result = ApiRepositoryRemote.normalize(input);
      expect(result, {
        'created_at': '2026-09-18T08:35:12.123456Z',
        'nested': [
          {'at': '2026-09-18T08:35:12.123456Z', 'steps': 8000, 'weight': 84.2},
          null,
          true,
          '2026-09-18',
        ],
        '7': false,
      });
      expect(input['created_at'], same(timestamp));
      expect((input['nested'] as List).first['at'], same(timestamp));
    });

    test(
      'normalization preserves stored row identity for natural-key paths',
      () {
        final row = {
          'id': 'stable-local-id',
          'user_id': 'account-a',
          'date': '2026-09-18',
        };
        final normalized = Json.from(ApiRepositoryRemote.normalize(row));
        expect(normalized['id'], 'stable-local-id');
        expect(
          ApiRepositoryRemote.documentId('daily_activities', normalized),
          '2026-09-18',
        );
        expect(ApiRepositoryRemote.normalize(null), isNull);
        expect(ApiRepositoryRemote.normalize([]), isEmpty);
      },
    );
  });

  test('app operation aliases resolve to standalone API endpoint names', () {
    const aliases = {
      'approve-plan': 'approvePlan',
      'sync-entitlement': 'syncEntitlement',
      'data-export': 'dataExport',
      'delete-account': 'deleteAccount',
      'sync-health-activity': 'syncHealthActivity',
    };
    for (final alias in aliases.entries) {
      expect(ApiRepositoryRemote.endpoint(alias.key), alias.value);
    }
    for (final name in [
      'coach',
      'saveReminder',
      'deleteReminder',
      'recordConsent',
    ]) {
      expect(ApiRepositoryRemote.endpoint(name), name);
    }
  });

  test(
    'backend exceptions keep the display message separate from error codes',
    () {
      const error = BackendException(
        403,
        'permission_denied',
        'Permission denied.',
      );
      expect(error.status, 403);
      expect(error.code, 'permission_denied');
      expect(error.toString(), 'Permission denied.');
    },
  );
}
