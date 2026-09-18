import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:health/health.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:workmanager/workmanager.dart';
import '../config.dart';
import '../firebase_runtime.dart';
import '../data/firebase_repository.dart';
import 'health_service.dart';

const _taskName = 'com.coralcell.leanguard.health-sync';
const _preferenceKey = 'leanguard.background-health';
const _storage = FlutterSecureStorage(
  aOptions: AndroidOptions(encryptedSharedPreferences: true),
  iOptions: IOSOptions(
    accessibility: KeychainAccessibility.first_unlock_this_device,
  ),
);

@pragma('vm:entry-point')
void healthBackgroundDispatcher() {
  Workmanager().executeTask((task, input) async {
    if (task != _taskName) return true;
    WidgetsFlutterBinding.ensureInitialized();
    try {
      if (!AppConfig.configured) return true;
      final raw = await _storage.read(key: _preferenceKey);
      if (raw == null) return true;
      final preference = jsonDecode(raw) as Map<String, dynamic>;
      if (preference['enabled'] != true) return true;
      await FirebaseRuntime.initialize(background: true);
      final auth = FirebaseAuth.instance;
      final userId = auth.currentUser?.uid;
      if (userId == null || userId != preference['user_id']) return true;
      await auth.currentUser!.getIdToken();
      return await BackgroundHealthSync(auth: auth).run(userId);
    } catch (_) {
      // Network loss, protected data while locked and revoked system access
      // are recoverable on the next scheduled/foreground sync. No PHI logs.
      return false;
    }
  });
}

class BackgroundHealthService {
  bool _initialized = false;
  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.android);

  Future<void> initialize() async {
    if (!supported || _initialized) return;
    await Workmanager().initialize(healthBackgroundDispatcher);
    _initialized = true;
  }

  /// Separate, explicit opt-in. Android permission is requested only here.
  /// iOS schedules opportunistic refresh; it cannot guarantee an interval.
  Future<bool> enable({required String userId, required bool pro}) async {
    if (!supported || !pro || userId.isEmpty) return false;
    if (defaultTargetPlatform == TargetPlatform.android) {
      final health = Health();
      await health.configure();
      if (!await health.isHealthConnectAvailable() ||
          !await health.isHealthDataInBackgroundAvailable()) {
        return false;
      }
      if (!await health.isHealthDataInBackgroundAuthorized() &&
          !await health.requestHealthDataInBackgroundAuthorization()) {
        return false;
      }
    }
    await initialize();
    await _storage.write(
      key: _preferenceKey,
      value: jsonEncode({'enabled': true, 'user_id': userId}),
    );
    try {
      await Workmanager().registerPeriodicTask(
        _taskName,
        _taskName,
        frequency: const Duration(hours: 6),
        constraints: Constraints(
          networkType: NetworkType.connected,
          requiresBatteryNotLow: true,
        ),
        existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
        backoffPolicy: BackoffPolicy.exponential,
        backoffPolicyDelay: const Duration(minutes: 15),
      );
      return true;
    } catch (_) {
      await _storage.delete(key: _preferenceKey);
      rethrow;
    }
  }

  Future<bool> isEnabled(String userId) async {
    final raw = await _storage.read(key: _preferenceKey);
    if (raw == null) return false;
    final preference = jsonDecode(raw) as Map<String, dynamic>;
    return preference['enabled'] == true && preference['user_id'] == userId;
  }

  /// Invoke on health disconnect, sign-out, deletion or entitlement expiration.
  Future<void> disable() async {
    await _storage.delete(key: _preferenceKey);
    if (supported) {
      await initialize();
      await Workmanager().cancelByUniqueName(_taskName);
    }
  }
}

class BackgroundSyncPolicy {
  static bool allows({
    required Map<String, dynamic>? entitlement,
    required bool healthConsent,
    required bool connected,
    required DateTime now,
  }) {
    if (!healthConsent || !connected || entitlement?['is_active'] != true) {
      return false;
    }
    final expires = DateTime.tryParse(
      entitlement?['expires_at'] as String? ?? '',
    );
    if (entitlement?['expires_at'] != null && expires == null) return false;
    final grace = DateTime.tryParse(
      entitlement?['grace_period_expires_at'] as String? ?? '',
    );
    return (expires == null || expires.isAfter(now)) ||
        (grace?.isAfter(now) ?? false);
  }
}

/// Checks fresh backend entitlement + consent before reading protected data.
/// A server transaction rechecks access and deduplicates imports independently
/// of the foreground encrypted write queue.
class BackgroundHealthSync {
  BackgroundHealthSync({
    FirebaseAuth? auth,
    FirebaseFirestore? firestore,
    HealthService? health,
  }) : auth = auth ?? FirebaseAuth.instance,
       firestore = firestore ?? FirebaseFirestore.instance,
       health = health ?? HealthService();
  final FirebaseAuth auth;
  final FirebaseFirestore firestore;
  final HealthService health;

  Future<bool> run(String userId) async {
    if (auth.currentUser?.uid != userId) return true;
    final provider = defaultTargetPlatform == TargetPlatform.iOS
        ? 'apple_health'
        : 'health_connect';
    final user = firestore.collection('users').doc(userId);
    const server = GetOptions(source: Source.server);
    final entitlement = await user
        .collection('subscription_entitlements')
        .doc('pro')
        .get(server);
    final consents = await user
        .collection('consent_records')
        .where('kind', isEqualTo: 'health_data')
        .orderBy('created_at', descending: true)
        .limit(1)
        .get(server);
    final connection = await user
        .collection('health_connections')
        .doc(provider)
        .get(server);
    if (!BackgroundSyncPolicy.allows(
      entitlement: entitlement.data(),
      healthConsent: consents.docs.firstOrNull?.data()['granted'] == true,
      connected: connection.data()?['status'] == 'connected',
      now: DateTime.now().toUtc(),
    )) {
      return true;
    }
    if (defaultTargetPlatform == TargetPlatform.android) {
      final native = Health();
      await native.configure();
      if (!await native.isHealthDataInBackgroundAuthorized()) return true;
    }
    if (!await _stillEnabled(userId)) return true;
    final snapshot = await health.readToday(pro: true);
    if (snapshot.access != HealthAccess.authorized ||
        !await _stillEnabled(userId)) {
      return true;
    }
    // The server rechecks consent, Pro, ownership and connection in its atomic
    // transaction, protects manually entered steps and deduplicates weight UUIDs.
    await FirebaseRepositoryRemote(auth: auth, firestore: firestore).invoke(
      'sync-health-activity',
      {
        'background': true,
        'date': snapshot.date.toIso8601String().substring(0, 10),
        'steps': snapshot.steps,
        'active_energy': snapshot.activeEnergyKcal,
        'source': provider,
        if (snapshot.latestWeightKg != null &&
            snapshot.weightExternalId != null &&
            snapshot.weightRecordedAt != null)
          'weight': {
            'kg': snapshot.latestWeightKg,
            'external_id': snapshot.weightExternalId,
            'recorded_at': snapshot.weightRecordedAt!.toUtc().toIso8601String(),
          },
      },
    );
    return true;
  }

  Future<bool> _stillEnabled(String userId) async {
    if (auth.currentUser?.uid != userId) return false;
    final local = await _storage.read(key: _preferenceKey);
    if (local == null) return false;
    final preference = jsonDecode(local) as Map;
    return preference['enabled'] == true && preference['user_id'] == userId;
  }
}
