import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leanguard/core/data/api_repository.dart';
import 'package:leanguard/core/data/repository.dart';
import 'package:leanguard/core/services/background_health_service.dart';
import 'package:leanguard/core/services/health_service.dart';
import '../core/api_transport_test.dart' show ApiTestAuth, ApiTestUser;

class BackgroundApi extends ApiRepositoryRemote {
  BackgroundApi(ApiTestAuth superAuth)
    : super(auth: superAuth, baseUrl: 'https://api.leanguard.test');
  final queried = <String>[];
  final List<Json> consents = [
    {
      'kind': 'health_data',
      'granted': true,
      'created_at': '2026-09-25T00:00:00Z',
    },
  ];
  bool pro = true;
  bool connected = true;
  Object? readError;
  Json? synced;
  @override
  Future<List<Json>> readAll(String table, String userId) async {
    queried.add(table);
    if (readError != null) throw readError!;
    return switch (table) {
      'subscription_entitlements' => [
        {
          'id': 'entitlement-row',
          'entitlement_id': 'pro',
          'is_active': pro,
          'expires_at': '2099-01-01T00:00:00Z',
        },
      ],
      'consent_records' => consents,
      'health_connections' => [
        {
          'provider': 'apple_health',
          'status': connected ? 'connected' : 'disconnected',
        },
      ],
      _ => [],
    };
  }

  @override
  Future<Json> invoke(String name, Json body) async {
    expect(name, 'sync-health-activity');
    synced = body;
    return {'synced': true};
  }
}

class BackgroundTestHealth extends HealthService {
  int reads = 0;
  Completer<HealthSnapshot>? pending;
  final snapshot = HealthSnapshot(
    date: DateTime.utc(2026, 9, 25),
    access: HealthAccess.authorized,
    steps: 4200,
    activeEnergyKcal: 250,
    latestWeightKg: 82,
    weightExternalId: 'health-original-uuid',
    weightRecordedAt: DateTime.utc(2026, 9, 23, 12),
  );
  @override
  Future<HealthSnapshot> readToday({DateTime? now, bool pro = false}) async {
    expect(pro, isTrue);
    reads++;
    return pending == null ? snapshot : pending!.future;
  }
}

void main() {
  late ApiTestAuth auth;
  late BackgroundApi api;
  late BackgroundTestHealth health;
  late BackgroundHealthSync sync;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    auth = ApiTestAuth();
    api = BackgroundApi(auth);
    health = BackgroundTestHealth();
    sync = BackgroundHealthSync(
      auth: auth,
      remote: api,
      health: health,
      isStillEnabled: (_) async => true,
    );
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test(
    'background sync fetches fresh API policy before native reads and sends original weight identity',
    () async {
      expect(await sync.run('account-a'), isTrue);
      expect(
        api.queried,
        containsAll([
          'subscription_entitlements',
          'consent_records',
          'health_connections',
        ]),
      );
      expect(health.reads, 1);
      expect(api.synced, {
        'background': true,
        'date': '2026-09-25',
        'steps': 4200,
        'active_energy': 250.0,
        'source': 'apple_health',
        'weight': {
          'kg': 82.0,
          'external_id': 'health-original-uuid',
          'recorded_at': '2026-09-23T12:00:00.000Z',
        },
      });
    },
  );

  test(
    'latest revoked consent suppresses native reads even when older consent was granted',
    () async {
      api.consents.add({
        'kind': 'health_data',
        'granted': false,
        'created_at': '2026-09-25T01:00:00Z',
      });
      await sync.run('account-a');
      expect(health.reads, 0);
      expect(api.synced, isNull);
    },
  );

  test(
    'missing Pro or disconnected health stops before reading the device',
    () async {
      api.pro = false;
      await sync.run('account-a');
      api.pro = true;
      api.connected = false;
      await sync.run('account-a');
      expect(health.reads, 0);
    },
  );

  test(
    'policy API failure never falls back to stale local authorization',
    () async {
      api.readError = const BackendException(503, 'unavailable', 'Offline');
      await expectLater(
        sync.run('account-a'),
        throwsA(isA<BackendException>()),
      );
      expect(health.reads, 0);
    },
  );

  test(
    'account switch during native background read prevents import',
    () async {
      health.pending = Completer<HealthSnapshot>();
      final running = sync.run('account-a');
      while (health.reads == 0) {
        await Future<void>.delayed(Duration.zero);
      }
      auth.currentUser = ApiTestUser('account-b');
      health.pending!.complete(health.snapshot);
      await running;
      expect(api.synced, isNull);
    },
  );
}
