import 'package:flutter_test/flutter_test.dart';
import 'package:leanguard/core/services/notification_service.dart';
import 'package:leanguard/core/services/subscription_service.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

CustomerInfo customer({
  bool active = true,
  bool renew = true,
  bool billing = false,
  bool trial = false,
}) {
  final entitlement = EntitlementInfo(
    'pro',
    active,
    renew,
    '2026-09-01',
    '2026-09-01',
    'leanguard_annual',
    true,
    periodType: trial ? PeriodType.trial : PeriodType.normal,
    expirationDate: '2026-09-30T00:00:00Z',
    billingIssueDetectedAt: billing ? '2026-09-18T00:00:00Z' : null,
  );
  return CustomerInfo(
    EntitlementInfos({'pro': entitlement}, active ? {'pro': entitlement} : {}),
    {},
    [],
    [],
    [],
    '2026-09-01',
    'account',
    {},
    '2026-09-18',
    managementURL: 'https://apps.apple.com/account/subscriptions',
  );
}

void main() {
  setUpAll(tz_data.initializeTimeZones);
  test('cancelled subscription retains access while entitlement active', () {
    final status = SubscriptionStatus.fromCustomerInfo(customer(renew: false));
    expect(status.isPro, isTrue);
    expect(status.willRenew, isFalse);
  });
  test('billing grace period follows RevenueCat active access', () {
    final status = SubscriptionStatus.fromCustomerInfo(customer(billing: true));
    expect(status.isPro, isTrue);
    expect(status.hasBillingIssue, isTrue);
  });
  test('expired trial cannot unlock Pro or an active trial label', () {
    final status = SubscriptionStatus.fromCustomerInfo(
      customer(active: false, trial: true),
    );
    expect(status.isPro, isFalse);
    expect(status.isTrial, isFalse);
  });
  test('trial access and management URL preserved', () {
    final status = SubscriptionStatus.fromCustomerInfo(customer(trial: true));
    expect(status.isTrial, isTrue);
    expect(
      status.managementUrl,
      'https://apps.apple.com/account/subscriptions',
    );
  });
  test('quiet hours suppress nighttime and preserve daytime', () {
    const quiet = QuietHours();
    expect(quiet.contains(23 * 60), isTrue);
    expect(quiet.contains(6 * 60), isTrue);
    expect(quiet.contains(7 * 60), isFalse);
    expect(quiet.allowMinute(14 * 60), 14 * 60);
    expect(quiet.allowMinute(23 * 60), 7 * 60);
  });
  test(
    'selected Monday late-night reminder defers to Tuesday after quiet hours',
    () {
      final now = tz.TZDateTime(tz.UTC, 2026, 9, 21, 12);
      final next = NotificationService.nextOccurrence(
        now: now,
        weekday: DateTime.monday,
        minuteOfDay: 23 * 60,
        quietHours: const QuietHours(),
      );
      expect(next, tz.TZDateTime(tz.UTC, 2026, 9, 22, 7));
    },
  );
  test('past weekday occurrence advances one week, respecting local DST', () {
    final zone = tz.getLocation('America/New_York');
    final now = tz.TZDateTime(zone, 2026, 10, 26, 19);
    final next = NotificationService.nextOccurrence(
      now: now,
      weekday: DateTime.monday,
      minuteOfDay: 18 * 60,
      quietHours: const QuietHours(enabled: false),
    );
    expect(next, tz.TZDateTime(zone, 2026, 11, 2, 18));
    expect(next.hour, 18);
    expect(next.timeZoneOffset, const Duration(hours: -5));
  });
  test('equal quiet bounds disable quiet window', () {
    const quiet = QuietHours(startMinute: 420, endMinute: 420);
    expect(quiet.contains(420), isFalse);
  });
}
