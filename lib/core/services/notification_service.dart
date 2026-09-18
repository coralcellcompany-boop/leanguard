import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

class QuietHours {
  const QuietHours({
    this.enabled = true,
    this.startMinute = 22 * 60,
    this.endMinute = 7 * 60,
  });
  final bool enabled;
  final int startMinute;
  final int endMinute;
  bool contains(int minute) {
    if (!enabled || startMinute == endMinute) return false;
    return startMinute < endMinute
        ? minute >= startMinute && minute < endMinute
        : minute >= startMinute || minute < endMinute;
  }

  int allowMinute(int minute) => contains(minute) ? endMinute : minute;
}

class NotificationService {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();
  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;
  void Function(String route)? _onTap;
  String? _pendingRoute;

  /// The router can be rebuilt independently of the native notification plugin.
  /// Keep one replaceable handler and retain a launch route until it is ready.
  void setTapHandler(void Function(String route)? handler) {
    _onTap = handler;
    if (handler != null && _pendingRoute != null) {
      final route = _pendingRoute!;
      _pendingRoute = null;
      handler(route);
    }
  }

  void _dispatch(String? route) {
    if (!_routes.contains(route)) return;
    if (_onTap == null) {
      _pendingRoute = route;
    } else {
      _onTap!(route!);
    }
  }

  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  String get timezone => tz.local.name;

  Future<void> initialize({void Function(String route)? onTap}) async {
    if (onTap != null) setTapHandler(onTap);
    if (_initialized || !supported) return;
    tz_data.initializeTimeZones();
    final current = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(current.identifier));
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('ic_notification'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
      onDidReceiveNotificationResponse: (response) {
        _dispatch(response.payload);
      },
    );
    _initialized = true;
    final launch = await _plugin.getNotificationAppLaunchDetails();
    final route = launch?.notificationResponse?.payload;
    if (launch?.didNotificationLaunchApp == true) _dispatch(route);
  }

  static const _routes = {'/today', '/plan', '/walking', '/protein', '/coach'};

  Future<bool> requestPermission() async {
    if (!supported) return false;
    await initialize();
    if (defaultTargetPlatform == TargetPlatform.android) {
      return await _plugin
              .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin
              >()
              ?.requestNotificationsPermission() ??
          false;
    }
    return await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true) ??
        false;
  }

  /// Inexact reminders deliberately avoid special exact-alarm access.
  /// Quiet-hour changes must reschedule every reminder; the same rule is server-side.
  Future<void> scheduleDaily({
    required int id,
    required int hour,
    required int minute,
    required String title,
    required String body,
    String route = '/today',
    QuietHours quietHours = const QuietHours(),
  }) async {
    if (!supported) return;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) {
      throw const FormatException('Invalid reminder time.');
    }
    if (!_routes.contains(route)) {
      throw const FormatException('Invalid reminder route.');
    }
    await initialize();
    final adjusted = quietHours.allowMinute(hour * 60 + minute);
    final now = tz.TZDateTime.now(tz.local);
    var next = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      adjusted ~/ 60,
      adjusted % 60,
    );
    if (!next.isAfter(now)) {
      next = tz.TZDateTime(
        tz.local,
        now.year,
        now.month,
        now.day + 1,
        adjusted ~/ 60,
        adjusted % 60,
      );
    }
    await _plugin.zonedSchedule(
      id,
      title,
      body,
      next,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'leanguard_reminders',
          'LeanGuard reminders',
          channelDescription: 'Your optional habit reminders',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
          visibility: NotificationVisibility.private,
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: false,
          presentSound: true,
        ),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      matchDateTimeComponents: DateTimeComponents.time,
      payload: route,
    );
  }

  /// One repeating request per selected weekday. IDs reserve ten slots per
  /// reminder, so callers pass small stable positive IDs and cancelAll to reset.
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
    if (!supported) return;
    if (hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59 ||
        daysOfWeek.any((day) => day < 1 || day > 7)) {
      throw const FormatException('Invalid reminder schedule.');
    }
    if (!_routes.contains(route)) {
      throw const FormatException('Invalid reminder route.');
    }
    await initialize();
    for (final day in daysOfWeek.toSet()) {
      final next = nextOccurrence(
        now: tz.TZDateTime.now(tz.local),
        weekday: day,
        minuteOfDay: hour * 60 + minute,
        quietHours: quietHours,
      );
      await _plugin.zonedSchedule(
        id * 10 + day,
        title,
        body,
        next,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'leanguard_reminders',
            'LeanGuard reminders',
            channelDescription: 'Your optional habit reminders',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            visibility: NotificationVisibility.private,
          ),
          iOS: DarwinNotificationDetails(
            presentAlert: true,
            presentBadge: false,
            presentSound: true,
          ),
        ),
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        payload: route,
      );
    }
  }

  static tz.TZDateTime nextOccurrence({
    required tz.TZDateTime now,
    required int weekday,
    required int minuteOfDay,
    required QuietHours quietHours,
  }) {
    final offset = (weekday - now.weekday + 7) % 7;
    final allowed = quietHours.allowMinute(minuteOfDay);
    final rollsDay =
        quietHours.contains(minuteOfDay) &&
        quietHours.startMinute > quietHours.endMinute &&
        minuteOfDay >= quietHours.startMinute;
    var next = tz.TZDateTime(
      now.location,
      now.year,
      now.month,
      now.day + offset + (rollsDay ? 1 : 0),
      allowed ~/ 60,
      allowed % 60,
    );
    if (!next.isAfter(now)) {
      next = tz.TZDateTime(
        now.location,
        next.year,
        next.month,
        next.day + 7,
        next.hour,
        next.minute,
      );
    }
    return next;
  }

  Future<void> cancel(int id) async {
    if (supported) await _plugin.cancel(id);
  }

  Future<void> cancelAll() async {
    if (supported) await _plugin.cancelAll();
  }
}
