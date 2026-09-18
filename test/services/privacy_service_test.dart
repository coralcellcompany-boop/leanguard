import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:leanguard/core/services/privacy_service.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

void main() {
  test(
    'diagnostics drop account and health content even in exception and breadcrumbs',
    () {
      final input = SentryEvent(
        message: const SentryMessage('Weight 82 kg, medication details'),
        throwable: StateError('coach text and health data'),
        user: SentryUser(id: 'user-secret-id', email: 'private@example.com'),
        tags: const {'screen': 'coach text'},
        breadcrumbs: [Breadcrumb(message: 'protein 90 g')],
      );
      final safe = PrivacyService.sanitizeForDelivery(
        input,
        analytics: false,
        diagnostics: true,
      );
      final encoded = jsonEncode(safe!.toJson());
      expect(encoded, contains('StateError'));
      for (final sensitive in [
        'Weight',
        '82 kg',
        'medication',
        'coach text',
        'user-secret-id',
        'private@example.com',
        'protein',
      ]) {
        expect(encoded, isNot(contains(sensitive)));
      }
    },
  );
  test(
    'analytics consent only allows fixed event names and drops extra values',
    () {
      final input = SentryEvent(
        message: const SentryMessage('health details'),
        tags: const {'analytics_event': 'paywallOpened', 'weight': '82'},
      );
      final safe = PrivacyService.sanitizeForDelivery(
        input,
        analytics: true,
        diagnostics: false,
      );
      expect(safe!.tags, {'analytics_event': 'paywallOpened'});
      expect(safe.message!.formatted, 'app_event');
      final unapproved = SentryEvent(
        tags: const {'analytics_event': 'custom_health_metric'},
      );
      expect(
        PrivacyService.sanitizeForDelivery(
          unapproved,
          analytics: true,
          diagnostics: true,
        ),
        isNull,
      );
    },
  );
  test('withdrawing consent drops diagnostics and analytics', () {
    expect(
      PrivacyService.sanitizeForDelivery(
        SentryEvent(throwable: StateError('x')),
        analytics: false,
        diagnostics: false,
      ),
      isNull,
    );
    expect(
      PrivacyService.sanitizeForDelivery(
        SentryEvent(tags: const {'analytics_event': 'appOpened'}),
        analytics: false,
        diagnostics: true,
      ),
      isNull,
    );
  });
}
