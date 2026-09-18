import 'dart:convert';
import '../domain/entities.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

typedef Json = Map<String, dynamic>;

abstract class LocalStore {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureLocalStore implements LocalStore {
  const SecureLocalStore();
  static const _storage = FlutterSecureStorage(
    aOptions: AndroidOptions(encryptedSharedPreferences: true),
    iOptions: IOSOptions(
      accessibility: KeychainAccessibility.first_unlock_this_device,
    ),
  );
  @override
  Future<String?> read(String key) => _storage.read(key: key);
  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

class MemoryLocalStore implements LocalStore {
  final Map<String, String> _data = {};
  @override
  Future<String?> read(String key) async => _data[key];
  @override
  Future<void> write(String key, String value) async {
    _data[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _data.remove(key);
  }
}

/// Transport seam keeps offline conflict and account-switch behavior testable.
abstract class RepositoryRemote {
  String? get authenticatedUserId;
  Future<void> write(
    String table,
    Json row, {
    required String conflict,
    required bool appendOnly,
  });
  Future<List<Json>> readPage(
    String table,
    String userId,
    int offset,
    int limit,
  );
  Future<Json> invoke(String name, Json body);
}

class LeanRepository {
  LeanRepository({required this.store,this.remote});
  final LocalStore store;
  final RepositoryRemote? remote;
  String? userId;
  Map<String, List<Json>> records = {};
  List<Json> pending = [];
  Future<void> _writes = Future.value();
  Future<void>? _sync;
  int _epoch = 0;
  bool get isDemo => userId == 'preview';
  static const singletons = {
    'user_profiles',
    'goal_profiles',
    'medication_support_preferences',
  };
  static const serverOwned = {
    'weekly_insights',
    'coach_messages',
    'subscription_entitlements',
    'plan_proposals',
  };
  static const tables = [
    'user_profiles',
    'goal_profiles',
    'health_connections',
    'medication_support_preferences',
    'strength_plans',
    'workouts',
    'exercises',
    'workout_exercises',
    'workout_sets',
    'daily_targets',
    'daily_activities',
    'protein_entries',
    'weight_entries',
    'body_measurements',
    'weekly_insights',
    'coach_conversations',
    'coach_messages',
    'reminder_preferences',
    'subscription_entitlements',
    'consent_records',
    'plan_proposals',
  ];
  Future<void> open(String id) async {
    if (id.isEmpty) {
      throw ArgumentError.value(id, 'id', 'An account ID is required.');
    }
    final epoch = ++_epoch;
    _sync = null;
    userId = id;
    records = {};
    pending = [];
    await _writes.catchError((_) {});
    final raw = await store.read('leanguard.v1.$id');
    if (_epoch != epoch || userId != id) return;
    if (raw != null) {
      final data = Json.from(jsonDecode(raw) as Map);
      records = Json.from(data['records'] as Map).map(
        (key, value) => MapEntry(
          key,
          (value as List)
              .map((row) => Json.from(row as Map))
              .where((row) => row['user_id'] == id)
              .toList(),
        ),
      );
      pending = (data['pending'] as List? ?? [])
          .map((entry) => Json.from(entry as Map))
          .where(
            (entry) =>
                (entry['row'] as Map)['user_id'] == id &&
                tables.contains(entry['table']) &&
                !serverOwned.contains(entry['table']),
          )
          .toList();
    }
  }

  List<Json> rows(String table) => records[table] ?? [];
  List<OwnedEntity> entities(String table) => rows(
    table,
  ).map((row) => OwnedEntity.fromTable(table, row)).toList(growable: false);
  Future<void> save() {
    final id = userId;
    if (id == null) return Future.value();
    final payload = jsonEncode({'records': records, 'pending': pending});
    // Capture owner and payload before awaiting; old writes cannot win races.
    _writes = _writes
        .catchError((_) {})
        .then((_) => store.write('leanguard.v1.$id', payload));
    return _writes;
  }

  static String conflictFor(String table, Json row) {
    if (singletons.contains(table)) return 'user_id';
    if (table == 'health_connections') return 'user_id,provider';
    if (table == 'daily_activities' || table == 'daily_targets') {
      return 'user_id,date';
    }
    if (table == 'workout_sets') return 'workout_exercise_id,set_number';
    if (table == 'weight_entries' && row['external_id'] != null) {
      return 'user_id,source,external_id';
    }
    return 'id';
  }

  static bool _sameRecord(String table, Json a, Json b) {
    if (a['id'] == b['id']) return true;
    final conflict = conflictFor(table, b);
    return conflict != 'id' &&
        conflict.split(',').every((key) => a[key] == b[key]);
  }

  Future<void> put(String table, Json row, {bool queue = true}) async {
    if (userId == null) throw StateError('Open an account before saving data.');
    if (!tables.contains(table)) {
      throw ArgumentError.value(table, 'table', 'Unknown LeanGuard table.');
    }
    if (queue && !isDemo && serverOwned.contains(table)) {
      throw StateError('This record can only be written by the server.');
    }
    if (row['id'] is! String || (row['id'] as String).isEmpty) {
      throw const FormatException('A record ID is required.');
    }
    if(row['user_id']!=null && row['user_id']!=userId)throw StateError('This record belongs to a different account.');
    final owned = {...row, 'user_id': userId};
    final current = [...rows(table)];
    final index = current.indexWhere(
      (existing) => _sameRecord(table, existing, owned),
    );
    if (table == 'consent_records' &&
        index >= 0 &&
        jsonEncode(current[index]) != jsonEncode(owned)) {
      throw StateError(
        'Consent records cannot be edited. Record a new consent decision.',
      );
    }
    if (index < 0) {
      current.add(owned);
    } else {
      current[index] = {
        ...current[index],
        ...owned,
        'id': current[index]['id'],
      };
    }
    records[table] = current;
    if (queue && !isDemo) {
      final stored = current[index < 0 ? current.length - 1 : index];
      final queued = pending.indexWhere(
        (entry) =>
            entry['table'] == table &&
            _sameRecord(table, Json.from(entry['row']), stored),
      );
      final mutation = {'table': table, 'row': Json.from(stored)};
      if (queued < 0) {
        pending.add(mutation);
      } else {
        pending[queued] = mutation;
      }
    }
    await save();
  }

  Future<void> sync() {
    if (isDemo || remote == null || userId == null) return Future.value();
    if (_sync != null) return _sync!;
    final epoch = _epoch, id = userId!;
    final operation = _synchronize(id, epoch);
    _sync = operation;
    return operation.whenComplete(() {
      if (_epoch == epoch) _sync = null;
    });
  }

  void _assertOwner(String id, int epoch) {
    if (_epoch != epoch || userId != id || remote?.authenticatedUserId != id) {
      throw StateError('Your session has changed. Please sign in again.');
    }
  }

  Future<void> _synchronize(String id, int epoch) async {
    _assertOwner(id, epoch);
    // FIFO keeps parents ahead of children. Replaced in-flight edits stay queued.
    while (pending.isNotEmpty) {
      _assertOwner(id, epoch);
      final change = pending.first, table = change['table'] as String;
      final row = Json.from(change['row']);
      if (row['user_id'] != id || serverOwned.contains(table)) {
        throw StateError('Invalid queued record ownership.');
      }
      await remote!.write(
        table,
        row,
        conflict: conflictFor(table, row),
        appendOnly: table == 'consent_records',
      );
      _assertOwner(id, epoch);
      pending.remove(change);
      await save();
    }
    for (final table in tables) {
      final all = <Json>[];
      for (var start = 0; ; start += 500) {
        _assertOwner(id, epoch);
        final page = await remote!.readPage(table, id, start, 500);
        _assertOwner(id, epoch);
        all.addAll(page.where((row) => row['user_id'] == id));
        if (page.length < 500) break;
      }
      for (final mutation in pending.where(
        (entry) => entry['table'] == table,
      )) {
        final row = Json.from(mutation['row']);
        all.removeWhere((entry) => _sameRecord(table, entry, row));
        all.add(row);
      }
      records[table] = all;
    }
    _assertOwner(id, epoch);
    await save();
  }

  Future<Json> invoke(String name, [Json body = const {}]) async {
    if (remote == null || isDemo || userId == null) {
      throw StateError('Connect a LeanGuard account to use this service.');
    }
    final id = userId!, epoch = _epoch;
    _assertOwner(id, epoch);
    final result = await remote!.invoke(name, body);
    _assertOwner(id, epoch);
    return result;
  }

  Future<void> eraseLocal() async {
    final id = userId;
    ++_epoch;
    _sync = null;
    userId = null;
    records = {};
    pending = [];
    if (id != null) {
      _writes = _writes
          .catchError((_) {})
          .then((_) => store.delete('leanguard.v1.$id'));
      await _writes;
    }
  }
}
