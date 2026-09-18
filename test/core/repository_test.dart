import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:leanguard/core/data/repository.dart';

class FakeRemote implements RepositoryRemote {
  @override
  String? authenticatedUserId = 'a';
  final rows = <String, List<Json>>{};
  final writes = <Json>[];
  final conflicts = <String>[];
  final appendOnlyWrites = <bool>[];
  Future<void> Function(String table, Json row)? beforeWrite;
  Future<void> Function(String table)? beforeRead;
  Json invocation = {'ok': true};
  final calls = <String>[];
  @override
  Future<void> write(
    String table,
    Json row, {
    required String conflict,
    required bool appendOnly,
  }) async {
    await beforeWrite?.call(table, row);
    writes.add(Json.from(row));
    conflicts.add(conflict);
    appendOnlyWrites.add(appendOnly);
    final current = rows.putIfAbsent(table, () => []);
    current.removeWhere(
      (r) => conflict.split(',').every((key) => r[key] == row[key]),
    );
    current.add(Json.from(row));
  }

  @override
  Future<List<Json>> readPage(
    String table,
    String userId,
    int offset,
    int limit,
  ) async {
    await beforeRead?.call(table);
    return (rows[table] ?? [])
        .where((r) => r['user_id'] == userId)
        .skip(offset)
        .take(limit)
        .map(Json.from)
        .toList();
  }

  @override
  Future<Json> invoke(String name, Json body) async {
    calls.add(name);
    return Json.from(invocation);
  }
}

class BlockingStore extends MemoryLocalStore {
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<String?> read(String key) async {
    if (key.endsWith('.a')) {
      entered.complete();
      await release.future;
    }
    return super.read(key);
  }
}

void main() {
  test(
    'offline edits persist, merge and queue one current version per record',
    () async {
      final store = MemoryLocalStore(),
          repository = LeanRepository(store: MemoryLocalStore());
      final first = LeanRepository(store: store);
      await first.open('a');
      await first.put('weight_entries', {'id': 'weight', 'weight_kg': 85});
      await first.put('weight_entries', {'id': 'weight', 'weight_kg': 84});
      expect(first.pending, hasLength(1));
      final restored = LeanRepository(store: store);
      await restored.open('a');
      expect(restored.rows('weight_entries').single['weight_kg'], 84);
      expect(restored.pending.single['row']['user_id'], 'a');
      await repository.open('b');
      expect(repository.rows('weight_entries'), isEmpty);
    },
  );
  test('an older open cannot replace the newly opened account', () async {
    final store = BlockingStore();
    await store.write(
      'leanguard.v1.a',
      jsonEncode({
        'records': {
          'weight_entries': [
            {'id': 'secret', 'user_id': 'a', 'weight_kg': 80},
          ],
        },
        'pending': [],
      }),
    );
    final repository = LeanRepository(store: store);
    final openingA = repository.open('a');
    await store.entered.future;
    await repository.open('b');
    store.release.complete();
    await openingA;
    expect(repository.userId, 'b');
    expect(repository.rows('weight_entries'), isEmpty);
  });
  test('failed sync preserves queued logging for retry', () async {
    final remote = FakeRemote()
      ..beforeWrite = ((_, _) async => throw StateError('offline'));
    final repository = LeanRepository(
      store: MemoryLocalStore(),
      remote: remote,
    );
    await repository.open('a');
    await repository.put('weight_entries', {'id': 'w', 'weight_kg': 80});
    await expectLater(repository.sync(), throwsStateError);
    expect(repository.pending, hasLength(1));
    expect(repository.rows('weight_entries'), hasLength(1));
    remote.beforeWrite = null;
    await repository.sync();
    expect(repository.pending, isEmpty);
    expect(remote.writes, hasLength(1));
  });
  test(
    'a newer edit survives an older in-flight write and sync is single-flight',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      final remote = FakeRemote();
      remote.beforeWrite = (_, row) async {
        if (row['weight_kg'] == 80) {
          entered.complete();
          await release.future;
        }
      };
      final repository = LeanRepository(
        store: MemoryLocalStore(),
        remote: remote,
      );
      await repository.open('a');
      await repository.put('weight_entries', {'id': 'w', 'weight_kg': 80});
      final first = repository.sync();
      await entered.future;
      final second = repository.sync();
      await repository.put('weight_entries', {'id': 'w', 'weight_kg': 79});
      release.complete();
      await Future.wait([first, second]);
      expect(remote.writes.map((r) => r['weight_kg']), [80, 79]);
      expect(repository.rows('weight_entries').single['weight_kg'], 79);
      expect(repository.pending, isEmpty);
    },
  );
  test(
    'in-flight reads cannot leak data across sign-out and account switch',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      final remote = FakeRemote();
      remote.rows['user_profiles'] = [
        {'id': 'a-profile', 'user_id': 'a', 'display_name': 'Private A'},
      ];
      remote.beforeRead = (table) async {
        if (table == 'user_profiles') {
          entered.complete();
          await release.future;
        }
      };
      final repository = LeanRepository(
        store: MemoryLocalStore(),
        remote: remote,
      );
      await repository.open('a');
      final syncing = repository.sync();
      final rejection = expectLater(syncing, throwsStateError);
      await entered.future;
      await repository.eraseLocal();
      remote.authenticatedUserId = 'b';
      await repository.open('b');
      release.complete();
      await rejection;
      expect(repository.userId, 'b');
      expect(repository.rows('user_profiles'), isEmpty);
    },
  );
  test('edits queued during remote reads remain visible and pending', () async {
    final entered = Completer<void>(), release = Completer<void>();
    final remote = FakeRemote();
    remote.beforeRead = (table) async {
      if (table == 'weight_entries') {
        entered.complete();
        await release.future;
      }
    };
    final repository = LeanRepository(
      store: MemoryLocalStore(),
      remote: remote,
    );
    await repository.open('a');
    final syncing = repository.sync();
    await entered.future;
    await repository.put('weight_entries', {'id': 'new', 'weight_kg': 77});
    release.complete();
    await syncing;
    expect(repository.rows('weight_entries').single['weight_kg'], 77);
    expect(repository.pending, hasLength(1));
  });
  test(
    'natural keys deduplicate imported days and append-only consent is immutable',
    () async {
      final remote = FakeRemote(),
          repository = LeanRepository(store: MemoryLocalStore());
      await repository.open('a');
      await repository.put('daily_activities', {
        'id': 'first',
        'date': '2026-09-18',
        'steps': 10,
      });
      await repository.put('daily_activities', {
        'id': 'second',
        'date': '2026-09-18',
        'steps': 20,
      });
      expect(repository.rows('daily_activities'), hasLength(1));
      expect(repository.pending, hasLength(1));
      expect(repository.rows('daily_activities').single['id'], 'first');
      final syncing = LeanRepository(store: MemoryLocalStore(), remote: remote);
      await syncing.open('a');
      await syncing.put('consent_records', {
        'id': 'consent',
        'kind': 'ai_processing',
        'granted': true,
        'policy_version': 'v1',
      });
      await expectLater(
        syncing.put('consent_records', {
          'id': 'consent',
          'kind': 'ai_processing',
          'granted': false,
          'policy_version': 'v1',
        }),
        throwsStateError,
      );
      await syncing.sync();
      expect(remote.appendOnlyWrites.single, true);
      expect(
        LeanRepository.conflictFor('daily_activities', {}),
        'user_id,date',
      );
      expect(
        LeanRepository.conflictFor('weight_entries', {'external_id': 'x'}),
        'user_id,source,external_id',
      );
    },
  );
  test(
    'server-only data cannot be queued and mismatched auth cannot sync or invoke',
    () async {
      final remote = FakeRemote(),
          repository = LeanRepository(store: MemoryLocalStore());
      await repository.open('a');
      await expectLater(
        repository.put('subscription_entitlements', {
          'id': 'pro',
          'is_active': true,
        }),
        throwsStateError,
      );
      final mismatch = LeanRepository(
        store: MemoryLocalStore(),
        remote: remote,
      );
      await mismatch.open('b');
      await expectLater(mismatch.sync(), throwsStateError);
      await expectLater(mismatch.invoke('coach', {}), throwsStateError);
      expect(remote.calls, isEmpty);
    },
  );
}
