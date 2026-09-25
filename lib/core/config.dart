import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

abstract final class AppConfig {
  static const backendBaseUrl = String.fromEnvironment('BACKEND_BASE_URL');
  static const allowLocalBackendHttp = bool.fromEnvironment(
    'BACKEND_ALLOW_HTTP_LOCAL',
  );

  static Uri parseBackendUri(
    String value, {
    bool allowLocalHttp = false,
    bool releaseMode = true,
  }) {
    if (value.trim().isEmpty) {
      throw StateError(
        'BACKEND_BASE_URL is not configured. Set the HTTPS address of your LeanGuard server.',
      );
    }
    final uri = Uri.tryParse(value.trim());
    if (uri == null ||
        !uri.hasAuthority ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      throw const FormatException(
        'BACKEND_BASE_URL must be a server origin without a path, credentials, query or fragment.',
      );
    }
    final localHttp =
        !releaseMode &&
        allowLocalHttp &&
        uri.scheme == 'http' &&
        const {'localhost', '127.0.0.1', '::1', '10.0.2.2'}.contains(uri.host);
    if (uri.scheme != 'https' && !localHttp) {
      throw const FormatException(
        'Use HTTPS for BACKEND_BASE_URL. Local HTTP requires an explicit debug-only opt-in.',
      );
    }
    return uri.replace(path: '');
  }

  static const firebaseProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
  );
  static const firebaseSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const useEmulators = bool.fromEnvironment('FIREBASE_USE_EMULATORS');
  static const emulatorHost = String.fromEnvironment(
    'FIREBASE_EMULATOR_HOST',
    defaultValue: 'localhost',
  );
  static const revenueCatIos = String.fromEnvironment('REVENUECAT_IOS_KEY');
  static const revenueCatAndroid = String.fromEnvironment(
    'REVENUECAT_ANDROID_KEY',
  );
  static const sentryDsn = String.fromEnvironment('SENTRY_DSN');
  static const privacyUrl = String.fromEnvironment('PRIVACY_URL');
  static const termsUrl = String.fromEnvironment('TERMS_URL');
  static FirebaseOptions? get firebaseOptions {
    final apple =
        defaultTargetPlatform == TargetPlatform.iOS ||
        defaultTargetPlatform == TargetPlatform.macOS;
    const iosId = String.fromEnvironment('FIREBASE_IOS_APP_ID'),
        androidId = String.fromEnvironment('FIREBASE_ANDROID_APP_ID');
    const iosKey = String.fromEnvironment('FIREBASE_IOS_API_KEY'),
        androidKey = String.fromEnvironment('FIREBASE_ANDROID_API_KEY');
    final appId = apple ? iosId : androidId, key = apple ? iosKey : androidKey;
    if (firebaseProjectId.isEmpty ||
        firebaseSenderId.isEmpty ||
        appId.isEmpty ||
        key.isEmpty) {
      return null;
    }
    return FirebaseOptions(
      apiKey: key,
      appId: appId,
      messagingSenderId: firebaseSenderId,
      projectId: firebaseProjectId,
      iosBundleId: apple ? 'com.coralcell.leanguard' : null,
    );
  }

  static bool get configured => firebaseOptions != null;
}
