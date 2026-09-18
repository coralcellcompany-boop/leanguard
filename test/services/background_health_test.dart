import 'package:flutter_test/flutter_test.dart';
import 'package:leanguard/core/services/background_health_service.dart';

void main() {
  final now = DateTime.utc(2026, 9, 18);
  bool allowed(
    Map<String, dynamic>? entitlement, {
    bool consent = true,
    bool connected = true,
  }) => BackgroundSyncPolicy.allows(
    entitlement: entitlement,
    healthConsent: consent,
    connected: connected,
    now: now,
  );
  test('background reads require server verified Pro', () {
    expect(allowed(null), isFalse);
    expect(allowed({'is_active': true, 'expires_at': 'invalid'}), isFalse);
    expect(
      allowed({'is_active': false, 'expires_at': '2027-01-01T00:00:00Z'}),
      isFalse,
    );
    expect(
      allowed({'is_active': true, 'expires_at': '2027-01-01T00:00:00Z'}),
      isTrue,
    );
  });
  test(
    'revoked health consent or disconnected account suppresses all reads',
    () {
      final entitlement = {
        'is_active': true,
        'expires_at': '2027-01-01T00:00:00Z',
      };
      expect(allowed(entitlement, consent: false), isFalse);
      expect(allowed(entitlement, connected: false), isFalse);
    },
  );
  test('expiration fails closed while valid store grace preserves access', () {
    expect(
      allowed({'is_active': true, 'expires_at': '2026-09-17T00:00:00Z'}),
      isFalse,
    );
    expect(
      allowed({
        'is_active': true,
        'expires_at': '2026-09-17T00:00:00Z',
        'grace_period_expires_at': '2026-09-20T00:00:00Z',
      }),
      isTrue,
    );
    expect(
      allowed({
        'is_active': true,
        'expires_at': '2026-09-17T00:00:00Z',
        'grace_period_expires_at': '2026-09-18T00:00:00Z',
      }),
      isFalse,
    );
  });
}
