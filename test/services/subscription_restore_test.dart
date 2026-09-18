import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leanguard/core/services/subscription_service.dart';

Map<String, Object?> payload(bool active) {
  final entitlement = <String, Object?>{
    'identifier': 'pro',
    'isActive': active,
    'willRenew': active,
    'latestPurchaseDate': '2026-09-18',
    'originalPurchaseDate': '2026-09-18',
    'productIdentifier': 'leanguard_annual',
    'isSandbox': true,
    'expirationDate': '2027-09-18T00:00:00Z',
    'periodType': 'NORMAL',
  };
  return {
    'entitlements': {
      'all': active ? {'pro': entitlement} : {},
      'active': active ? {'pro': entitlement} : {},
    },
    'allPurchaseDates': <String, Object?>{},
    'activeSubscriptions': <String>[],
    'allPurchasedProductIdentifiers': <String>[],
    'nonSubscriptionTransactions': <Object>[],
    'firstSeen': '2026-09-18',
    'originalAppUserId': 'test-user',
    'allExpirationDates': <String, Object?>{},
    'requestDate': '2026-09-18',
  };
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('purchases_flutter');
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });
  test('restoration uses native RevenueCat entitlement result', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    var restored = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getCustomerInfo') return payload(false);
          if (call.method == 'restorePurchases') {
            restored = true;
            return payload(true);
          }
          return null;
        });
    final service = SubscriptionService();
    await service.configure(
      iosApiKey: 'appl_test',
      androidApiKey: '',
      userId: 'test-user',
    );
    expect(service.status.isPro, isFalse);
    final status = await service.restore();
    expect(restored, isTrue);
    expect(status.isPro, isTrue);
    await service.dispose();
  });
  test('store restoration failure never manufactures Pro access', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'getCustomerInfo') return payload(false);
          if (call.method == 'restorePurchases') {
            throw PlatformException(code: '10', message: 'Network unavailable');
          }
          return null;
        });
    final service = SubscriptionService();
    await service.configure(
      iosApiKey: 'appl_test',
      androidApiKey: '',
      userId: 'test-user',
    );
    await expectLater(service.restore(), throwsA(isA<PlatformException>()));
    expect(service.status.isPro, isFalse);
    await service.dispose();
  });
  test(
    'failed account switch cannot retain previous user Pro access',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'getCustomerInfo') return payload(true);
            if (call.method == 'logIn') {
              throw PlatformException(code: '10', message: 'Offline');
            }
            return null;
          });
      final service = SubscriptionService();
      await service.configure(
        iosApiKey: 'appl_test',
        androidApiKey: '',
        userId: 'first-user',
      );
      expect(service.status.isPro, isTrue);
      await expectLater(
        service.configure(
          iosApiKey: 'appl_test',
          androidApiKey: '',
          userId: 'second-user',
        ),
        throwsA(isA<PlatformException>()),
      );
      expect(service.status.isPro, isFalse);
      expect(service.activeUserId, isNull);
      expect(() => service.offerings(), throwsStateError);
      await service.dispose();
    },
  );

  for (final operation in ['restorePurchases', 'getCustomerInfo']) {
    test('late $operation cannot unlock a different account', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final response = Completer<Map<String, Object?>>();
      final started = Completer<void>();
      var waiting = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == operation && waiting) {
              started.complete();
              return response.future;
            }
            if (call.method == 'getCustomerInfo') return payload(false);
            if (call.method == 'logIn') {
              return {'customerInfo': payload(false), 'created': false};
            }
            return null;
          });
      final service = SubscriptionService();
      await service.configure(
        iosApiKey: 'appl_test',
        androidApiKey: '',
        userId: 'first-user',
      );
      waiting = true;
      final oldOperation = operation == 'restorePurchases'
          ? service.restore()
          : service.refresh();
      final failure = expectLater(oldOperation, throwsStateError);
      await started.future;
      await service.configure(
        iosApiKey: 'appl_test',
        androidApiKey: '',
        userId: 'second-user',
      );
      response.complete(payload(true));
      await failure;
      expect(service.status.isPro, isFalse);
      await service.dispose();
    });
  }

  test(
    'native account changes are serialized and stale login stays Free',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final slowLogin = Completer<Map<String, Object?>>();
      final started = Completer<void>();
      final logins = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            if (call.method == 'getCustomerInfo') return payload(false);
            if (call.method == 'logIn') {
              final userId = (call.arguments as Map)['appUserID'] as String;
              logins.add(userId);
              if (userId == 'second-user') {
                started.complete();
                return slowLogin.future;
              }
              return {'customerInfo': payload(false), 'created': false};
            }
            return null;
          });
      final service = SubscriptionService();
      await service.configure(
        iosApiKey: 'appl_test',
        androidApiKey: '',
        userId: 'first-user',
      );
      final second = service.configure(
        iosApiKey: 'appl_test',
        androidApiKey: '',
        userId: 'second-user',
      );
      await started.future;
      final third = service.configure(
        iosApiKey: 'appl_test',
        androidApiKey: '',
        userId: 'third-user',
      );
      await Future<void>.delayed(Duration.zero);
      expect(logins, ['second-user']);
      slowLogin.complete({'customerInfo': payload(true), 'created': false});
      await Future.wait([second, third]);
      expect(logins, ['second-user', 'third-user']);
      expect(service.status.isPro, isFalse);
      await service.dispose();
    },
  );
}
