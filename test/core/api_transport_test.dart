import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:leanguard/core/config.dart';
import 'package:leanguard/core/data/api_repository.dart';

class ApiTestUser extends Fake implements User {
  ApiTestUser(this.uid);
  @override
  final String uid;
  Completer<String?>? tokenResult;
  int tokenRequests = 0;
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async {
    tokenRequests++;
    return tokenResult == null ? 'firebase-id-token-$uid' : tokenResult!.future;
  }
}

class ApiTestAuth extends Fake implements FirebaseAuth {
  @override
  User? currentUser = ApiTestUser('account-a');
}

void main() {
  const base = 'https://api.leanguard.test';
  late ApiTestAuth auth;
  setUp(() => auth = ApiTestAuth());

  test(
    'production requires a HTTPS origin, with explicit loopback-only debug HTTP',
    () {
      for (final valid in [base, '$base/', 'https://api.leanguard.test:8443']) {
        expect(AppConfig.parseBackendUri(valid).scheme, 'https');
      }
      for (final invalid in [
        'http://api.leanguard.test',
        '$base/v1',
        '$base?key=value',
        '$base#fragment',
        'https://user:password@api.leanguard.test',
        'file:///tmp/api',
      ]) {
        expect(() => AppConfig.parseBackendUri(invalid), throwsFormatException);
      }
      for (final local in ['localhost', '127.0.0.1', '10.0.2.2', '[::1]']) {
        final uri = 'http://$local:3000';
        expect(() => AppConfig.parseBackendUri(uri), throwsFormatException);
        expect(
          () => AppConfig.parseBackendUri(
            uri,
            allowLocalHttp: true,
            releaseMode: true,
          ),
          throwsFormatException,
        );
        expect(
          AppConfig.parseBackendUri(
            uri,
            allowLocalHttp: true,
            releaseMode: false,
          ).scheme,
          'http',
        );
      }
      expect(
        () => AppConfig.parseBackendUri(
          'http://192.168.1.1:3000',
          allowLocalHttp: true,
          releaseMode: false,
        ),
        throwsFormatException,
      );
    },
  );

  test(
    'missing backend fails clearly before obtaining or transmitting credentials',
    () async {
      var sent = false;
      final remote = ApiRepositoryRemote(
        auth: auth,
        baseUrl: '',
        httpClient: MockClient((_) async {
          sent = true;
          return http.Response('{}', 200);
        }),
      );
      await expectLater(
        remote.readPage('weight_entries', 'account-a', 0, 100),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('BACKEND_BASE_URL'),
          ),
        ),
      );
      expect((auth.currentUser as ApiTestUser).tokenRequests, 0);
      expect(sent, isFalse);
    },
  );

  test(
    'paged records use only Firebase bearer token and preserve full JSON values',
    () async {
      final row = {
        'id': 'weight-1',
        'user_id': 'account-a',
        'weight_kg': 82.3,
        'recorded_at': '2026-09-25T08:00:00Z',
      };
      final remote = ApiRepositoryRemote(
        auth: auth,
        baseUrl: base,
        httpClient: MockClient((request) async {
          expect(request.method, 'GET');
          expect(
            request.url.toString(),
            '$base/v1/records/weight_entries?offset=500&limit=100',
          );
          expect(
            request.headers['authorization'],
            'Bearer firebase-id-token-account-a',
          );
          expect(
            request.headers.keys.any(
              (key) => key.toLowerCase().contains('appcheck'),
            ),
            isFalse,
          );
          expect(request.followRedirects, isFalse);
          return http.Response(
            jsonEncode({
              'records': [row],
            }),
            200,
          );
        }),
      );
      expect(await remote.readPage('weight_entries', 'account-a', 500, 100), [
        row,
      ]);
    },
  );

  test('writes use canonical natural IDs and keep raw row data', () async {
    final row = {
      'id': 'local-row-id',
      'user_id': 'account-a',
      'date': '2026-09-25',
      'steps': 5000,
    };
    final remote = ApiRepositoryRemote(
      auth: auth,
      baseUrl: base,
      httpClient: MockClient((request) async {
        expect(request.method, 'PUT');
        expect(request.url.path, '/v1/records/daily_activities/2026-09-25');
        expect(jsonDecode(request.body), row);
        return http.Response(jsonEncode(row), 200);
      }),
    );
    await remote.write(
      'daily_activities',
      row,
      conflict: 'user_id,date',
      appendOnly: false,
    );
  });

  test('reminder and consent writes use validated server operations', () async {
    final paths = <String>[];
    final remote = ApiRepositoryRemote(
      auth: auth,
      baseUrl: base,
      httpClient: MockClient((request) async {
        paths.add(request.url.path);
        expect(request.method, 'POST');
        expect(
          (jsonDecode(request.body) as Map)['row']['user_id'],
          'account-a',
        );
        return http.Response('{}', 200);
      }),
    );
    for (final table in ['reminder_preferences', 'consent_records']) {
      await remote.write(
        table,
        {'id': 'record-1', 'user_id': 'account-a'},
        conflict: 'id',
        appendOnly: table == 'consent_records',
      );
    }
    expect(paths, ['/v1/saveReminder', '/v1/recordConsent']);
  });

  test(
    'foreign-owner writes and server-owned data never reach the network',
    () async {
      var count = 0;
      final remote = ApiRepositoryRemote(
        auth: auth,
        baseUrl: base,
        httpClient: MockClient((_) async {
          count++;
          return http.Response('{}', 200);
        }),
      );
      await expectLater(
        remote.write(
          'weight_entries',
          {'id': '1', 'user_id': 'other'},
          conflict: 'id',
          appendOnly: false,
        ),
        throwsStateError,
      );
      await expectLater(
        remote.write(
          'subscription_entitlements',
          {'id': 'pro', 'user_id': 'account-a'},
          conflict: 'id',
          appendOnly: false,
        ),
        throwsStateError,
      );
      expect(count, 0);
    },
  );

  test(
    'account switch while Firebase refreshes its token cancels the request',
    () async {
      final user = auth.currentUser as ApiTestUser;
      user.tokenResult = Completer<String?>();
      var count = 0;
      final remote = ApiRepositoryRemote(
        auth: auth,
        baseUrl: base,
        httpClient: MockClient((_) async {
          count++;
          return http.Response('{}', 200);
        }),
      );
      final request = remote.invoke('coach', {'message': 'question'});
      auth.currentUser = ApiTestUser('account-b');
      user.tokenResult!.complete('old-account-token');
      await expectLater(request, throwsStateError);
      expect(count, 0);
    },
  );

  test(
    'account switch during response cannot expose old account records',
    () async {
      final remote = ApiRepositoryRemote(
        auth: auth,
        baseUrl: base,
        httpClient: MockClient((_) async {
          auth.currentUser = ApiTestUser('account-b');
          return http.Response(
            jsonEncode({
              'records': [
                {'user_id': 'account-a', 'id': 'secret'},
              ],
            }),
            200,
          );
        }),
      );
      await expectLater(
        remote.readPage('weight_entries', 'account-a', 0, 100),
        throwsStateError,
      );
    },
  );

  test('unexpected owner in a server response is rejected', () async {
    final remote = ApiRepositoryRemote(
      auth: auth,
      baseUrl: base,
      httpClient: MockClient(
        (_) async => http.Response(
          jsonEncode({
            'records': [
              {'user_id': 'account-b', 'id': 'foreign'},
            ],
          }),
          200,
        ),
      ),
    );
    await expectLater(
      remote.readPage('weight_entries', 'account-a', 0, 100),
      throwsA(
        isA<BackendException>().having((e) => e.code, 'code', 'invalid_owner'),
      ),
    );
  });

  test(
    'redirecting servers cannot receive forwarded Firebase credentials',
    () async {
      final remote = ApiRepositoryRemote(
        auth: auth,
        baseUrl: base,
        httpClient: MockClient((request) async {
          expect(request.followRedirects, isFalse);
          return http.Response(
            '',
            302,
            headers: {'location': 'https://untrusted.test/'},
          );
        }),
      );
      await expectLater(
        remote.invoke('coach', {}),
        throwsA(
          isA<BackendException>().having(
            (e) => e.code,
            'code',
            'redirect_refused',
          ),
        ),
      );
    },
  );

  test(
    'transport and malformed-response failures have bounded safe messages',
    () async {
      for (final client in [
        MockClient((_) async => throw http.ClientException('unsafe details')),
        MockClient(
          (_) async => http.Response('<html>upstream failure</html>', 502),
        ),
      ]) {
        final remote = ApiRepositoryRemote(
          auth: auth,
          baseUrl: base,
          httpClient: client,
        );
        await expectLater(
          remote.invoke('coach', {}),
          throwsA(
            isA<BackendException>().having(
              (e) => e.message,
              'message',
              isNot(contains('unsafe')),
            ),
          ),
        );
      }
    },
  );

  test(
    'backend error codes are available to reauthentication and quota flows',
    () async {
      final remote = ApiRepositoryRemote(
        auth: auth,
        baseUrl: base,
        httpClient: MockClient(
          (_) async => http.Response(
            jsonEncode({
              'error': 'recent_login_required',
              'message': 'Sign in again.',
            }),
            401,
          ),
        ),
      );
      await expectLater(
        remote.invoke('delete-account', {'confirmation': 'DELETE'}),
        throwsA(
          isA<BackendException>()
              .having((e) => e.code, 'code', 'recent_login_required')
              .having((e) => e.status, 'status', 401),
        ),
      );
    },
  );

  test(
    'FCM token registration and removal use authenticated owner APIs',
    () async {
      final requests = <http.Request>[];
      final remote = ApiRepositoryRemote(
        auth: auth,
        baseUrl: base,
        httpClient: MockClient((request) async {
          requests.add(request);
          return http.Response('{}', 200);
        }),
      );
      await remote.registerDeviceToken('native-token', 'ios');
      await remote.deleteDeviceToken('abc123');
      expect(requests[0].method, 'PUT');
      expect(requests[0].url.path, '/v1/device-tokens');
      expect(jsonDecode(requests[0].body), {
        'token': 'native-token',
        'platform': 'ios',
      });
      expect(requests[1].method, 'DELETE');
      expect(requests[1].url.path, '/v1/device-tokens/abc123');
    },
  );

  test(
    'background policy reads paginate instead of silently truncating consent history',
    () async {
      final offsets = <String>[];
      final remote = ApiRepositoryRemote(
        auth: auth,
        baseUrl: base,
        httpClient: MockClient((request) async {
          final offset = request.url.queryParameters['offset']!;
          offsets.add(offset);
          final count = offset == '0' ? 500 : 1;
          return http.Response(
            jsonEncode({
              'records': List.generate(
                count,
                (i) => {'id': '$offset-$i', 'user_id': 'account-a'},
              ),
            }),
            200,
          );
        }),
      );
      expect(
        await remote.readAll('consent_records', 'account-a'),
        hasLength(501),
      );
      expect(offsets, ['0', '500']);
    },
  );
}
