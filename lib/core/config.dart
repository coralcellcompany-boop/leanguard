import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

abstract final class AppConfig {
  static const firebaseProjectId = String.fromEnvironment(
    'FIREBASE_PROJECT_ID',
  );
  static const firebaseRegion = String.fromEnvironment(
    'FIREBASE_REGION',
    defaultValue: 'europe-west1',
  );
  static const firebaseSenderId = String.fromEnvironment(
    'FIREBASE_MESSAGING_SENDER_ID',
  );
  static const firebaseStorageBucket = String.fromEnvironment(
    'FIREBASE_STORAGE_BUCKET',
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
      storageBucket: firebaseStorageBucket.isEmpty
          ? null
          : firebaseStorageBucket,
      iosBundleId: apple ? 'com.coralcell.leanguard' : null,
    );
  }

  static bool get configured => firebaseOptions != null;
}
