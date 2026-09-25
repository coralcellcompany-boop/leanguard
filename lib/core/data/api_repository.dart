import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
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

/// The Node API owns authorization, persistence and privileged operations.
/// Only a Firebase Auth ID token is attached; redirects are never followed.
class ApiRepositoryRemote implements RepositoryRemote {
  ApiRepositoryRemote({
    FirebaseAuth? auth,
    http.Client? httpClient,
    this.baseUrl = AppConfig.backendBaseUrl,
    this.allowLocalHttp = AppConfig.allowLocalBackendHttp,
    this.releaseMode = kReleaseMode,
  }) : auth = auth ?? FirebaseAuth.instance,
       _http = httpClient ?? http.Client();

  final FirebaseAuth auth;
  final http.Client _http;
  final String baseUrl;
  final bool allowLocalHttp, releaseMode;
  @override
  String? get authenticatedUserId => auth.currentUser?.uid;

  Uri get baseUri => AppConfig.parseBackendUri(
    baseUrl,
    allowLocalHttp: allowLocalHttp,
    releaseMode: releaseMode,
  );

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

  static dynamic normalize(dynamic value) {
    if (value is Map) {
      return value.map(
        (key, child) => MapEntry(key.toString(), normalize(child)),
      );
    }
    if (value is List) return value.map(normalize).toList();
    return value;
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

  void _checkOwner(String owner) {
    if (authenticatedUserId != owner) {
      throw StateError('Your account changed. Sign in again.');
    }
  }

  static void _validateTable(String table) {
    if (!LeanRepository.tables.contains(table)) {
      throw ArgumentError('Unknown record type.');
    }
  }

  static void _validateId(String id) {
    if (id.isEmpty ||
        id == '.' ||
        id == '..' ||
        id.contains('/') ||
        id.contains(r'\')) {
      throw const FormatException('The record identifier is invalid.');
    }
  }

  Future<Json> _request(
    String method,
    List<String> path, {
    Json? body,
    Map<String, String>? query,
    Duration timeout = const Duration(seconds: 35),
  }) async {
    // Fail before obtaining credentials if no VPS origin was configured.
    final origin = baseUri;
    final user = auth.currentUser;
    if (user == null) {
      throw const BackendException(
        401,
        'unauthenticated',
        'Sign in to continue.',
      );
    }
    final owner = user.uid;
    final token = await user.getIdToken();
    _checkOwner(owner);
    if (token == null || token.isEmpty) {
      throw const BackendException(
        401,
        'unauthenticated',
        'Sign in again to continue.',
      );
    }
    final uri = origin.replace(
      pathSegments: ['v1', ...path],
      queryParameters: query,
    );
    final abort = Completer<void>();
    final request =
        http.AbortableRequest(method, uri, abortTrigger: abort.future)
          ..followRedirects = false
          ..headers.addAll({
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          });
    if (body != null) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode(body);
    }
    try {
      final response = await _http
          .send(request)
          .then(http.Response.fromStream)
          .timeout(
            timeout,
            onTimeout: () {
              if (!abort.isCompleted) abort.complete();
              throw TimeoutException(
                'The server took too long to respond. Try again.',
              );
            },
          );
      _checkOwner(owner);
      if (response.statusCode >= 300 && response.statusCode < 400) {
        throw const BackendException(
          502,
          'redirect_refused',
          'The backend address redirected. Check BACKEND_BASE_URL.',
        );
      }
      if (response.statusCode == 204) return {};
      final Json result;
      try {
        result = Json.from(jsonDecode(response.body) as Map);
      } catch (_) {
        throw const BackendException(
          502,
          'invalid_response',
          'The server returned an invalid response. Try again later.',
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
    } on http.ClientException {
      throw const BackendException(
        503,
        'unavailable',
        'The server could not be reached. Check your connection and try again.',
      );
    }
  }

  @override
  Future<void> write(
    String table,
    Json row, {
    required String conflict,
    required bool appendOnly,
  }) async {
    _validateTable(table);
    final owner = authenticatedUserId;
    if (owner == null || row['user_id'] != owner) {
      throw StateError('Your account changed. Sign in again.');
    }
    if (LeanRepository.serverOwned.contains(table)) {
      throw StateError('This record is managed by the server.');
    }
    if (table == 'reminder_preferences') {
      await invoke('saveReminder', {'row': row});
      return;
    }
    if (table == 'consent_records') {
      await invoke('recordConsent', {'row': row});
      return;
    }
    final id = documentId(table, row);
    _validateId(id);
    await _request('PUT', ['records', table, id], body: row);
  }

  @override
  Future<List<Json>> readPage(
    String table,
    String userId,
    int offset,
    int limit,
  ) async {
    _validateTable(table);
    _checkOwner(userId);
    if (offset < 0 || limit < 1 || limit > 500) {
      throw ArgumentError('Invalid page bounds.');
    }
    final response = await _request(
      'GET',
      ['records', table],
      query: {'offset': '$offset', 'limit': '$limit'},
    );
    _checkOwner(userId);
    final rows = response['records'];
    if (rows is! List) {
      throw const BackendException(
        502,
        'invalid_response',
        'The server returned invalid records.',
      );
    }
    final result = rows.map((row) => Json.from(row as Map)).toList();
    if (result.any((row) => row['user_id'] != userId)) {
      throw const BackendException(
        502,
        'invalid_owner',
        'The server returned records for an unexpected account.',
      );
    }
    return result;
  }

  /// Fresh, paginated reads for background consent and entitlement checks.
  Future<List<Json>> readAll(String table, String userId) async {
    final result = <Json>[];
    for (var offset = 0; ; offset += 500) {
      final page = await readPage(table, userId, offset, 500);
      result.addAll(page);
      if (page.length < 500) return result;
    }
  }

  @override
  Future<Json> invoke(String name, Json body) {
    final target = endpoint(name);
    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9]*$').hasMatch(target)) {
      throw ArgumentError('Invalid API operation.');
    }
    return _request(
      'POST',
      [target],
      body: body,
      timeout: requestTimeout(target),
    );
  }

  Future<Json> registerDeviceToken(String token, String platform) => _request(
    'PUT',
    ['device-tokens'],
    body: {'token': token, 'platform': platform},
  );
  Future<void> deleteDeviceToken(String id) async {
    _validateId(id);
    await _request('DELETE', ['device-tokens', id]);
  }

  void dispose() => _http.close();
}
