import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'config.dart';

abstract final class FirebaseRuntime {
  static bool _ready = false;

  /// Native resources and Dart options must refer to the same app. Otherwise a
  /// stale SDK file could silently attach an environment to another project.
  static void validateNativeOptions(
    FirebaseOptions expected,
    FirebaseOptions actual,
  ) {
    if (expected.projectId != actual.projectId ||
        expected.appId != actual.appId ||
        expected.messagingSenderId != actual.messagingSenderId) {
      throw StateError(
        'Firebase native configuration does not match the app environment.',
      );
    }
  }

  static Future<void> initialize({bool background = false}) async {
    if (_ready || !AppConfig.configured) return;
    if (kReleaseMode && AppConfig.useEmulators) {
      throw StateError('Release builds cannot connect to emulators.');
    }
    final expected = AppConfig.firebaseOptions!;
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: expected);
    }
    validateNativeOptions(expected, Firebase.app().options);
    // Health data has one explicitly encrypted offline cache. Disable the
    // Firestore SDK's disk cache and require server reads in the repository.
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: false,
    );
    if (AppConfig.useEmulators) {
      await FirebaseAuth.instance.useAuthEmulator(AppConfig.emulatorHost, 9099);
      FirebaseFirestore.instance.useFirestoreEmulator(
        AppConfig.emulatorHost,
        8080,
      );
      await FirebaseStorage.instance.useStorageEmulator(
        AppConfig.emulatorHost,
        9199,
      );
    } else {
      await FirebaseAppCheck.instance.activate(
        providerAndroid: kDebugMode
            ? const AndroidDebugProvider()
            : const AndroidPlayIntegrityProvider(),
        providerApple: kDebugMode
            ? const AppleDebugProvider()
            : const AppleAppAttestWithDeviceCheckFallbackProvider(),
      );
    }
    _ready = true;
  }
}
