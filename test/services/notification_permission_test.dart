import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leanguard/core/services/notification_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const notifications = MethodChannel(
    'dexterous.com/flutter/local_notifications',
  );
  const timezone = MethodChannel('flutter_timezone');
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(notifications, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(timezone, null);
  });
  test(
    'OS notification denial is returned without fabricating permission',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      IOSFlutterLocalNotificationsPlugin.registerWith();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(timezone, (call) async => 'UTC');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(notifications, (call) async {
            switch (call.method) {
              case 'initialize':
                return true;
              case 'getNotificationAppLaunchDetails':
                return {'notificationLaunchedApp': false};
              case 'requestPermissions':
                return false;
              default:
                return null;
            }
          });
      final service = NotificationService();
      expect(await service.requestPermission(), isFalse);
    },
  );

  test(
    'handler can attach after permission initialization and replace router',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      IOSFlutterLocalNotificationsPlugin.registerWith();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(timezone, (call) async => 'UTC');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(notifications, (call) async {
            if (call.method == 'initialize') return true;
            if (call.method == 'getNotificationAppLaunchDetails') {
              return {
                'notificationLaunchedApp': true,
                'notificationResponse': {
                  'notificationId': 1,
                  'notificationResponseType': 0,
                  'payload': '/plan',
                },
              };
            }
            return null;
          });
      final service = NotificationService();
      final first = <String>[], replacement = <String>[];
      await service.initialize();
      await service.initialize(onTap: first.add);
      expect(first, ['/plan']);
      await service.initialize(onTap: replacement.add);
      Future<void> tap(String route) async {
        final done = Completer<void>();
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .handlePlatformMessage(
              notifications.name,
              const StandardMethodCodec().encodeMethodCall(
                MethodCall('didReceiveNotificationResponse', {
                  'notificationId': 2,
                  'notificationResponseType': 0,
                  'payload': route,
                }),
              ),
              (_) => done.complete(),
            );
        await done.future;
      }

      await tap('/protein');
      await tap('/delete-account');
      expect(first, ['/plan']);
      expect(replacement, ['/protein']);
      service.setTapHandler(null);
      await tap('/walking');
      expect(replacement, ['/protein']);
      service.setTapHandler(first.add);
      expect(first, ['/plan', '/walking']);
    },
  );
}
