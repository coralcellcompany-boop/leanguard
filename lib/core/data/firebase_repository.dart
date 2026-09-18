import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import 'repository.dart';

class BackendException implements Exception {
  const BackendException(this.status, this.code, this.message);
  final int status;
  final String code, message;
  @override
  String toString() => message;
}

class FirebaseRepositoryRemote implements RepositoryRemote {
  FirebaseRepositoryRemote({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
    http.Client? httpClient,
  }) : db = firestore ?? FirebaseFirestore.instance,
       auth = auth ?? FirebaseAuth.instance,
       _http = httpClient ?? http.Client();
  final FirebaseFirestore db;
  final FirebaseAuth auth;
  final http.Client _http;
  final Map<String, DocumentSnapshot<Json>> _cursors = {};
  @override
  String? get authenticatedUserId => auth.currentUser?.uid;
  static String documentId(String table, Json row) {
    if (LeanRepository.singletons.contains(table)) {
      return row['user_id'] as String;
    }
    if (table == 'subscription_entitlements') return 'pro';
    if (table == 'daily_activities' || table == 'daily_targets') {
      return row['date'] as String;
    }
    if (table == 'health_connections') return row['provider'] as String;
    if (table == 'workout_sets') {
      return '${row['workout_exercise_id']}_${row['set_number']}';
    }
    if (table == 'weight_entries' && row['external_id'] != null) {
      return sha256
          .convert(utf8.encode('${row['source']}:${row['external_id']}'))
          .toString();
    }
    return row['id'] as String;
  }

  CollectionReference<Json> _collection(String table, String uid) =>
      db.collection('users').doc(uid).collection(table);
  @override
  Future<void> write(
    String table,
    Json row, {
    required String conflict,
    required bool appendOnly,
  }) async {
    final uid = authenticatedUserId;
    if (uid == null || row['user_id'] != uid) {
      throw StateError('Your session changed. Sign in again.');
    }
    if (table == 'reminder_preferences') {
      await invoke('saveReminder', {'row': row});
      return;
    }
    if (table == 'consent_records') {
      await invoke('recordConsent', {'row': row});
      return;
    }
    final doc = _collection(table, uid).doc(documentId(table, row));
    await db.runTransaction((transaction) async {
      final existing = await transaction.get(doc);
      if (appendOnly && existing.exists) {
        final saved = existing.data()!;
        if (saved['user_id'] != uid ||
            saved['kind'] != row['kind'] ||
            saved['granted'] != row['granted'] ||
            saved['policy_version'] != row['policy_version']) {
          throw StateError('Consent records cannot be modified.');
        }
        return;
      }
      final data = {
        ...row,
        if (existing.exists) 'id': existing.data()!['id'],
        if (existing.exists) 'created_at': existing.data()!['created_at'],
      };
      transaction.set(doc, data, SetOptions(merge: !appendOnly));
    });
  }

  static dynamic normalize(dynamic value) {
    if (value is Timestamp) return value.toDate().toUtc().toIso8601String();
    if (value is Map) {
      return value.map((k, v) => MapEntry(k.toString(), normalize(v)));
    }
    if (value is List) return value.map(normalize).toList();
    return value;
  }

  @override
  Future<List<Json>> readPage(
    String table,
    String userId,
    int offset,
    int limit,
  ) async {
    if (authenticatedUserId != userId) {
      throw StateError('Your account changed.');
    }
    Query<Json> query = _collection(
      table,
      userId,
    ).orderBy('created_at').orderBy(FieldPath.documentId).limit(limit);
    final cursor = _cursors['$userId/$table/$offset'];
    if (offset > 0) {
      if (cursor == null) {
        throw StateError('Refresh the records and try again.');
      }
      query = query.startAfterDocument(cursor);
    }
    final result = await query.get(const GetOptions(source: Source.server));
    if (result.docs.isNotEmpty) {
      _cursors['$userId/$table/${offset + limit}'] = result.docs.last;
    }
    return result.docs
        .map((d) => Json.from(normalize(d.data()) as Map))
        .toList();
  }

  static String endpoint(String name) =>
      const {
        'approve-plan': 'approvePlan',
        'sync-entitlement': 'syncEntitlement',
        'data-export': 'dataExport',
        'delete-account': 'deleteAccount',
        'sync-health-activity': 'syncHealthActivity',
      }[name] ??
      name;
  static Duration requestTimeout(String name) => switch (endpoint(name)) {
    'dataExport' || 'deleteAccount' => const Duration(seconds: 300),
    _ => const Duration(seconds: 35),
  };
  @override
  Future<Json> invoke(String name, Json body) async {
    final user = auth.currentUser;
    if (user == null) {
      throw const BackendException(
        401,
        'unauthenticated',
        'Sign in to continue.',
      );
    }
    final token = await user.getIdToken();
    final attestation = AppConfig.useEmulators
        ? null
        : await FirebaseAppCheck.instance.getToken();
    if (!AppConfig.useEmulators &&
        (attestation == null || attestation.isEmpty)) {
      throw const BackendException(
        403,
        'app_check_required',
        'App verification failed. Use a configured device build.',
      );
    }
    final uri = AppConfig.useEmulators
        ? Uri.http(
            '${AppConfig.emulatorHost}:5001',
            '/${AppConfig.firebaseProjectId}/${AppConfig.firebaseRegion}/${endpoint(name)}',
          )
        : Uri.https(
            '${AppConfig.firebaseRegion}-${AppConfig.firebaseProjectId}.cloudfunctions.net',
            '/${endpoint(name)}',
          );
    final response = await _http
        .post(
          uri,
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
            'X-Firebase-AppCheck': ?attestation,
          },
          body: jsonEncode(body),
        )
        .timeout(requestTimeout(name));
    Json result;
    try {
      result = Json.from(jsonDecode(response.body) as Map);
    } catch (_) {
      throw const BackendException(
        502,
        'invalid_response',
        'The service returned an invalid response. Try again later.',
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw BackendException(
        response.statusCode,
        result['error']?.toString() ?? 'unavailable',
        result['message']?.toString() ??
            'The service is temporarily unavailable.',
      );
    }
    return result;
  }
}
