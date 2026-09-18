import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leanguard/core/firebase_runtime.dart';

void main() {
  const expected = FirebaseOptions(
    apiKey: 'public-client-key',
    appId: '1:123:ios:test',
    messagingSenderId: '123',
    projectId: 'leanguard-test',
  );
  test('matching native SDK configuration can initialize the expected app', () {
    expect(
      () => FirebaseRuntime.validateNativeOptions(expected, expected),
      returnsNormally,
    );
  });
  test('stale native project or app configuration fails closed', () {
    for (final actual in [
      const FirebaseOptions(
        apiKey: 'public-client-key',
        appId: '1:123:ios:test',
        messagingSenderId: '123',
        projectId: 'another-project',
      ),
      const FirebaseOptions(
        apiKey: 'public-client-key',
        appId: '1:123:ios:old-bundle-app',
        messagingSenderId: '123',
        projectId: 'leanguard-test',
      ),
      const FirebaseOptions(
        apiKey: 'public-client-key',
        appId: '1:123:ios:test',
        messagingSenderId: '999',
        projectId: 'leanguard-test',
      ),
    ]) {
      expect(
        () => FirebaseRuntime.validateNativeOptions(expected, actual),
        throwsStateError,
      );
    }
  });
}
