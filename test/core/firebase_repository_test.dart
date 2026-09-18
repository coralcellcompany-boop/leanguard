import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leanguard/core/data/firebase_repository.dart';
import 'package:leanguard/core/data/repository.dart';

void main() {
  group('Firestore document identity', () {
    test('singleton paths use the account owner rather than local row IDs', () {
      for (final table in LeanRepository.singletons) {
        expect(
          FirebaseRepositoryRemote.documentId(table, {
            'id': 'local-profile-id',
            'user_id': 'account-a',
          }),
          'account-a',
        );
      }
      expect(
        FirebaseRepositoryRemote.documentId('subscription_entitlements', {
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
          expect(
            FirebaseRepositoryRemote.documentId(table, first),
            '2026-09-18',
          );
          expect(
            FirebaseRepositoryRemote.documentId(table, second),
            FirebaseRepositoryRemote.documentId(table, first),
          );
          expect(first['id'], 'first-device-row');
        }
        expect(
          FirebaseRepositoryRemote.documentId('health_connections', {
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
          FirebaseRepositoryRemote.documentId('workout_sets', row),
          'exercise-in-workout_2',
        );
        expect(
          FirebaseRepositoryRemote.documentId('workout_sets', {
            ...row,
            'id': 'retry-set-id',
          }),
          'exercise-in-workout_2',
        );
        expect(
          FirebaseRepositoryRemote.documentId('workout_sets', {
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
      final id = FirebaseRepositoryRemote.documentId('weight_entries', row);
      expect(
        id,
        'ddb5635417ad40a98e053708ff96f8a3ae3ac2b7527747759b98efa601bfdd53',
      );
      expect(id, matches(RegExp(r'^[a-f0-9]{64}$')));
      expect(
        FirebaseRepositoryRemote.documentId('weight_entries', {
          ...row,
          'id': 'retry-local-id',
        }),
        id,
      );
      expect(
        FirebaseRepositoryRemote.documentId('weight_entries', {
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
          FirebaseRepositoryRemote.documentId(table, {'id': '$table-id'}),
          '$table-id',
        );
      }
      expect(
        FirebaseRepositoryRemote.documentId('weight_entries', {
          'id': 'manual-weight',
          'source': 'manual',
          'external_id': null,
        }),
        'manual-weight',
      );
    });
  });

  group('Firestore value normalization', () {
    test(
      'nested timestamps become UTC strings without losing scalar values',
      () {
        final instant = DateTime.utc(2026, 9, 18, 8, 35, 12, 123, 456);
        final timestamp = Timestamp.fromDate(instant);
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
        final result = FirebaseRepositoryRemote.normalize(input);
        expect(result, {
          'created_at': '2026-09-18T08:35:12.123456Z',
          'nested': [
            {
              'at': '2026-09-18T08:35:12.123456Z',
              'steps': 8000,
              'weight': 84.2,
            },
            null,
            true,
            '2026-09-18',
          ],
          '7': false,
        });
        expect(input['created_at'], same(timestamp));
        expect((input['nested'] as List).first['at'], same(timestamp));
      },
    );

    test(
      'normalization preserves stored row identity for natural-key paths',
      () {
        final row = {
          'id': 'stable-local-id',
          'user_id': 'account-a',
          'date': '2026-09-18',
        };
        final normalized = Json.from(FirebaseRepositoryRemote.normalize(row));
        expect(normalized['id'], 'stable-local-id');
        expect(
          FirebaseRepositoryRemote.documentId('daily_activities', normalized),
          '2026-09-18',
        );
        expect(FirebaseRepositoryRemote.normalize(null), isNull);
        expect(FirebaseRepositoryRemote.normalize([]), isEmpty);
      },
    );
  });

  test('app operation aliases resolve to deployed HTTPS function names', () {
    const aliases = {
      'approve-plan': 'approvePlan',
      'sync-entitlement': 'syncEntitlement',
      'data-export': 'dataExport',
      'delete-account': 'deleteAccount',
      'sync-health-activity': 'syncHealthActivity',
    };
    for (final alias in aliases.entries) {
      expect(FirebaseRepositoryRemote.endpoint(alias.key), alias.value);
    }
    for (final name in [
      'coach',
      'saveReminder',
      'deleteReminder',
      'recordConsent',
    ]) {
      expect(FirebaseRepositoryRemote.endpoint(name), name);
    }
  });

  test(
    'backend exceptions keep the display message separate from error codes',
    () {
      const error = BackendException(
        403,
        'app_check_required',
        'App verification failed.',
      );
      expect(error.status, 403);
      expect(error.code, 'app_check_required');
      expect(error.toString(), 'App verification failed.');
    },
  );
}
