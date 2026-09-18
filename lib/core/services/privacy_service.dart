import 'package:sentry_flutter/sentry_flutter.dart';

/// These event names never contain user-generated content or health values.
enum AnalyticsEvent {
  appOpened,
  onboardingCompleted,
  permissionEducationOpened,
  paywallOpened,
  purchaseCompleted,
  purchaseRestored,
  exportCompleted,
}

class PrivacyService {
  PrivacyService({required this.dsn});
  final String dsn;
  bool _initialized = false;
  bool _analytics = false;
  bool _diagnostics = false;

  Future<void> setConsent({
    required bool analytics,
    required bool diagnostics,
  }) async {
    _analytics = analytics;
    _diagnostics = diagnostics;
    if (dsn.isEmpty || (!analytics && !diagnostics)) {
      if (_initialized) await Sentry.close();
      _initialized = false;
      return;
    }
    if (_initialized) return;
    await SentryFlutter.init((options) {
      options.dsn = dsn;
      options.sendDefaultPii = false;
      options.enableAutoSessionTracking = false;
      options.enableAutoNativeBreadcrumbs = false;
      options.enableAutoPerformanceTracing = false;
      options.enableNativeCrashHandling = false;
      options.attachScreenshot = false;
      options.attachViewHierarchy = false;
      options.attachStacktrace = false;
      options.maxBreadcrumbs = 0;
      options.tracesSampleRate = 0;
      options.beforeBreadcrumb = (breadcrumb, hint) => null;
      options.beforeSend = (event, hint) => sanitizeForDelivery(
        event,
        analytics: _analytics,
        diagnostics: _diagnostics,
      );
    });
    _initialized = true;
  }

  static SentryEvent? sanitizeForDelivery(
    SentryEvent event, {
    required bool analytics,
    required bool diagnostics,
  }) {
    final analyticName = event.tags?['analytics_event'];
    if (analyticName != null) {
      if (!analytics ||
          !AnalyticsEvent.values.any((value) => value.name == analyticName)) {
        return null;
      }
      return SentryEvent(
        message: const SentryMessage('app_event'),
        tags: {'analytics_event': analyticName},
      );
    }
    if (!diagnostics) return null;
    // A new event discards network bodies, identities, exception messages,
    // screen contents, paths, contexts and third-party breadcrumbs.
    return SentryEvent(
      message: const SentryMessage('Application error'),
      level: event.level ?? SentryLevel.error,
      tags: {
        'error_type':
            event.throwable?.runtimeType.toString() ?? 'UnhandledError',
      },
    );
  }

  Future<void> track(AnalyticsEvent event) async {
    if (!_initialized || !_analytics) return;
    await Sentry.captureEvent(
      SentryEvent(
        message: const SentryMessage('app_event'),
        tags: {'analytics_event': event.name},
      ),
    );
  }

  Future<void> report(Object error, StackTrace stackTrace) async {
    if (!_initialized || !_diagnostics) return;
    await Sentry.captureException(error, stackTrace: stackTrace);
  }
}
