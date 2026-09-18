import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leanguard/core/data/repository.dart';
import 'package:leanguard/core/services/health_service.dart';
import 'package:leanguard/core/services/firebase_auth_service.dart';
import 'package:leanguard/core/services/notification_service.dart';
import 'package:leanguard/core/services/subscription_service.dart';
import 'package:leanguard/core/state.dart';

class LifecycleSubscriptions extends SubscriptionService {
  final events = StreamController<SubscriptionStatus>.broadcast(sync: true);
  String? owner;
  @override
  String? get activeUserId => owner;
  bool failSignOut = false;
  int refreshes = 0;
  int signOuts = 0;
  @override
  Stream<SubscriptionStatus> get changes => events.stream;
  @override
  bool get isConfigured => true;
  @override
  Future<SubscriptionStatus> refresh() async {
    refreshes++;
    const status = SubscriptionStatus(isPro: true);
    events.add(status);
    return status;
  }

  @override
  Future<void> signOut() async {
    signOuts++;
    if (failSignOut) throw StateError('Store unavailable');
  }

  @override
  Future<void> dispose() => events.close();
}

class DeferredHealth extends HealthService {
  Completer<HealthSnapshot>? response;
  Completer<HealthAccess>? permission;
  final readStarted = Completer<void>();
  final permissionStarted = Completer<void>();
  int reads = 0;
  int disconnects = 0;
  @override
  Future<HealthSnapshot> readToday({DateTime? now, bool pro = false}) {
    reads++;
    if (!readStarted.isCompleted) readStarted.complete();
    return response?.future ?? Future.value(snapshot());
  }

  @override
  Future<HealthAccess> requestAccess({bool pro = false}) {
    if (!permissionStarted.isCompleted) permissionStarted.complete();
    return permission?.future ?? Future.value(HealthAccess.authorized);
  }

  @override
  Future<void> disconnect() async {
    disconnects++;
  }
}

class LifecycleNotifications extends NotificationService {
  bool failCancel = false;
  int cancellations = 0;
  final scheduled = <Json>[];
  Completer<void>? scheduledCountReached;
  int targetCount = 0;
  @override
  Future<void> initialize({void Function(String route)? onTap}) async {}
  @override
  Future<void> cancelAll() async {
    cancellations++;
    if (failCancel) throw StateError('Native notification error');
    scheduled.clear();
  }

  @override
  Future<void> scheduleWeekly({
    required int id,
    required List<int> daysOfWeek,
    required int hour,
    required int minute,
    required String title,
    required String body,
    String route = '/today',
    QuietHours quietHours = const QuietHours(),
  }) async {
    scheduled.add({
      'id': id,
      'days': daysOfWeek,
      'hour': hour,
      'minute': minute,
      'title': title,
      'body': body,
      'route': route,
      'quiet': quietHours.enabled,
    });
    if (scheduled.length == targetCount &&
        scheduledCountReached?.isCompleted == false) {
      scheduledCountReached!.complete();
    }
  }
}

class LifecycleController extends AppController {
  LifecycleController(
    super.repository,
    super.subscriptions,
    super.health,
    super.notifications, {
    super.auth,
  });
  AppState get current => state;
  Future<void> useAccount(String owner, {bool pro = false}) async {
    (auth!.auth as LifecycleAuth).user = LifecycleUser(owner);
    (subscriptions as LifecycleSubscriptions).owner = owner;
    await repository.open(owner);
    state = AppState(
      initialized: true,
      authenticated: true,
      subscription: SubscriptionStatus(isPro: pro),
      records: Map.of(repository.records),
    );
  }
}

class LifecycleUser extends Fake implements User {
  LifecycleUser(this.uid);
  @override
  final String uid;
  @override
  bool get emailVerified => true;
  @override
  List<UserInfo> get providerData => [];
}

class LifecycleAuth extends Fake implements FirebaseAuth {
  User? user;
  @override
  User? get currentUser => user;
  @override
  Stream<User?> userChanges() => const Stream.empty();
  @override
  Future<void> signOut() async {
    user = null;
  }
}

class LifecycleRepository extends LeanRepository {
  LifecycleRepository({required super.store});
  final requests = <Json>[];
  Future<Json> Function(String name, Json body)? onInvoke;
  @override
  Future<Json> invoke(String name, [Json body = const {}]) async {
    requests.add({'name': name, ...body});
    if (onInvoke != null) return onInvoke!(name, body);
    return {};
  }
}

HealthSnapshot snapshot() => HealthSnapshot(
  date: DateTime.now(),
  access: HealthAccess.authorized,
  steps: 8700,
  activeEnergyKcal: 400,
  latestWeightKg: 82.5,
  weightExternalId: 'native-weight-one',
  weightRecordedAt: DateTime(2026, 9, 16, 8),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryLocalStore store;
  late LifecycleRepository repository;
  late LifecycleSubscriptions subscriptions;
  late DeferredHealth health;
  late LifecycleNotifications notifications;
  late LifecycleController controller;
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    FlutterSecureStorage.setMockInitialValues({});
    store = MemoryLocalStore();
    repository = LifecycleRepository(store: store);
    subscriptions = LifecycleSubscriptions();
    health = DeferredHealth();
    notifications = LifecycleNotifications();
    controller = LifecycleController(
      repository,
      subscriptions,
      health,
      notifications,
      auth: FirebaseAuthService(LifecycleAuth()),
    );
    await controller.initialize();
  });
  tearDown(() async {
    controller.dispose();
    await subscriptions.dispose();
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'preview never inherits late paid-account entitlement updates',
    () async {
      await controller.useAccount('account-a', pro: true);
      await controller.enterDemo();
      subscriptions.events.add(const SubscriptionStatus(isPro: true));
      expect(controller.current.demo, isTrue);
      expect(controller.current.isPro, isFalse);
      expect(controller.current.healthAccess, HealthAccess.notRequested);
      await controller.onResume();
      expect(subscriptions.refreshes, 0);
      expect(health.reads, 0);
      expect(controller.current.isPro, isFalse);
    },
  );

  test('signed-out state ignores late entitlements', () async {
    subscriptions.events.add(const SubscriptionStatus(isPro: true));
    expect(controller.current.authenticated, isFalse);
    expect(controller.current.isPro, isFalse);
  });

  test(
    'new account ignores an older SDK identity still finishing login',
    () async {
      await controller.useAccount('account-b');
      subscriptions.owner = 'account-a';
      subscriptions.events.add(const SubscriptionStatus(isPro: true));
      expect(controller.current.isPro, isFalse);
      subscriptions.owner = 'account-b';
      subscriptions.events.add(const SubscriptionStatus(isPro: true));
      expect(controller.current.isPro, isTrue);
    },
  );

  test(
    'health read completing after account switch cannot write to next owner',
    () async {
      await controller.useAccount('account-a', pro: true);
      await controller.recordConsent('health_data', true);
      health.response = Completer<HealthSnapshot>();
      final pending = controller.syncHealth();
      await health.readStarted.future;
      await controller.useAccount('account-b', pro: true);
      await controller.recordConsent('health_data', true);
      health.response!.complete(snapshot());
      await pending;
      expect(repository.rows('daily_activities'), isEmpty);
      expect(repository.rows('weight_entries'), isEmpty);
      expect(repository.rows('health_connections'), isEmpty);
    },
  );

  test('revoking consent discards already in-flight health reads', () async {
    await controller.useAccount('account-a', pro: true);
    await controller.recordConsent('health_data', true);
    health.response = Completer<HealthSnapshot>();
    final pending = controller.syncHealth();
    await health.readStarted.future;
    await controller.disconnectHealth();
    health.response!.complete(snapshot());
    await pending;
    expect(controller.hasConsent('health_data'), isFalse);
    expect(repository.rows('daily_activities'), isEmpty);
    expect(repository.rows('weight_entries'), isEmpty);
    expect(controller.current.healthAccess, HealthAccess.notRequested);
  });

  test(
    'permission sheet completion never grants consent to another account',
    () async {
      await controller.useAccount('account-a');
      health.permission = Completer<HealthAccess>();
      final pending = controller.connectHealth();
      await health.permissionStarted.future;
      await controller.useAccount('account-b');
      health.permission!.complete(HealthAccess.authorized);
      await pending;
      expect(controller.hasConsent('health_data'), isFalse);
      expect(repository.rows('weight_entries'), isEmpty);
      expect(health.reads, 0);
    },
  );

  test('expiration while reading cannot import Pro-only energy', () async {
    await controller.useAccount('account-a', pro: true);
    await controller.recordConsent('health_data', true);
    health.response = Completer<HealthSnapshot>();
    final pending = controller.syncHealth();
    await health.readStarted.future;
    subscriptions.events.add(const SubscriptionStatus());
    health.response!.complete(snapshot());
    await pending;
    expect(controller.current.isPro, isFalse);
    expect(repository.requests.single['active_energy'], isNull);
    expect(
      repository.rows('daily_activities').firstOrNull?['active_energy_kcal'],
      isNull,
    );
  });

  test('sign-out erases account cache even if native cleanup fails', () async {
    await controller.useAccount('account-a', pro: true);
    await controller.recordConsent('health_data', true);
    await repository.put('weight_entries', {
      'id': 'weight-a',
      'weight_kg': 82.5,
    });
    expect(await store.read('leanguard.v1.account-a'), isNotNull);
    subscriptions.failSignOut = true;
    notifications.failCancel = true;
    await controller.signOut();
    expect(repository.userId, isNull);
    expect(await store.read('leanguard.v1.account-a'), isNull);
    expect(controller.current.authenticated, isFalse);
    expect(controller.current.isPro, isFalse);
    expect(controller.current.records, isEmpty);
    expect(notifications.cancellations, 1);
    expect(subscriptions.signOuts, 1);
    expect(health.disconnects, 1);
  });

  test(
    'a completed deletion for account A cannot sign out or erase account B',
    () async {
      await controller.useAccount('account-a', pro: true);
      final invoked = Completer<void>();
      final response = Completer<Json>();
      repository.onInvoke = (name, body) {
        expect(name, 'delete-account');
        expect(body, {'confirmation': 'DELETE'});
        invoked.complete();
        return response.future;
      };
      final deleting = controller.deleteAccount();
      await invoked.future;
      await controller.useAccount('account-b', pro: true);
      await controller.addWeight(76.5);
      final before = await store.read('leanguard.v1.account-b');
      response.complete({'deleted': true});
      await deleting;
      expect(repository.userId, 'account-b');
      expect(controller.auth!.currentUser!.uid, 'account-b');
      expect(controller.current.authenticated, isTrue);
      expect(controller.current.isPro, isTrue);
      expect(controller.current.weights.single['weight_kg'], 76.5);
      expect(await store.read('leanguard.v1.account-b'), before);
      expect(subscriptions.signOuts, 0);
      expect(health.disconnects, 0);
      expect(notifications.cancellations, 0);
    },
  );

  test(
    'expiration keeps logs and reschedules at most three fixed reminders',
    () async {
      await controller.useAccount('account-a', pro: true);
      await controller.addWeight(81.2);
      for (final entry in [
        ('smart', true, 'local', true),
        ('push', false, 'push', true),
        ('disabled', false, 'local', false),
        for (var index = 0; index < 5; index++)
          ('fixed-$index', false, 'local', true),
      ]) {
        await repository.put('reminder_preferences', {
          'id': entry.$1,
          'kind': 'workout',
          'title': entry.$1,
          'smart': entry.$2,
          'delivery': entry.$3,
          'enabled': entry.$4,
          'time_of_day': '18:30:00',
          'days_of_week': [1, 3, 5],
          'quiet_start': '21:00:00',
          'quiet_end': '08:00:00',
        });
      }
      await controller.refresh();
      await controller.rescheduleNotifications();
      expect(notifications.scheduled, hasLength(5));
      expect(
        notifications.scheduled.every((row) => row['quiet'] == true),
        isTrue,
      );
      final savedLogs = await store.read('leanguard.v1.account-a');
      notifications.targetCount = 3;
      notifications.scheduledCountReached = Completer<void>();
      subscriptions.events.add(const SubscriptionStatus());
      await notifications.scheduledCountReached!.future.timeout(
        const Duration(seconds: 2),
      );
      expect(controller.current.isPro, isFalse);
      expect(notifications.cancellations, 2);
      expect(notifications.scheduled.map((row) => row['title']), [
        'fixed-0',
        'fixed-1',
        'fixed-2',
      ]);
      expect(
        notifications.scheduled.every((row) => row['quiet'] == false),
        isTrue,
      );
      expect(controller.current.weights.single['weight_kg'], 81.2);
      expect(controller.current.reminders, hasLength(8));
      expect(await store.read('leanguard.v1.account-a'), savedLogs);
    },
  );
}
