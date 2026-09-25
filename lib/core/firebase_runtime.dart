import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
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
    if (AppConfig.useEmulators) {
      await FirebaseAuth.instance.useAuthEmulator(AppConfig.emulatorHost, 9099);
    }
    _ready = true;
  }
}
