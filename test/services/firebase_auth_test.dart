import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leanguard/core/services/firebase_auth_service.dart';
import 'package:leanguard/core/services/push_service.dart';

class TestFirebaseUser extends Fake implements User {
  @override
  String? get email => 'person@example.com';
  @override
  bool emailVerified = false;
  String? savedName;
  String? savedPassword;
  int verificationEmails = 0;
  int tokenRefreshes = 0;
  AuthCredential? reauthCredential;
  @override
  Future<void> updateDisplayName(String? name) async {
    savedName = name;
  }

  @override
  Future<void> sendEmailVerification([ActionCodeSettings? settings]) async {
    verificationEmails++;
  }

  @override
  Future<void> updatePassword(String password) async {
    savedPassword = password;
  }

  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async {
    if (forceRefresh) tokenRefreshes++;
    return 'test-token';
  }

  @override
  Future<UserCredential> reauthenticateWithCredential(
    AuthCredential credential,
  ) async {
    reauthCredential = credential;
    return TestCredential(this);
  }
}

class TestCredential extends Fake implements UserCredential {
  TestCredential(this.user);
  @override
  final User? user;
}

class TestFirebaseAuth extends Fake implements FirebaseAuth {
  final testUser = TestFirebaseUser();
  User? sessionUser;
  int creates = 0;
  int signsOut = 0;
  String? resetEmail;
  AuthProvider? provider;
  @override
  User? get currentUser => sessionUser;
  @override
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    creates++;
    sessionUser = testUser;
    return TestCredential(testUser);
  }

  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    sessionUser = testUser;
    return TestCredential(testUser);
  }

  @override
  Future<void> signOut() async {
    signsOut++;
    sessionUser = null;
  }

  @override
  Future<void> sendPasswordResetEmail({
    required String email,
    ActionCodeSettings? actionCodeSettings,
  }) async {
    resetEmail = email;
  }

  @override
  Future<UserCredential> signInWithProvider(AuthProvider authProvider) async {
    provider = authProvider;
    sessionUser = testUser;
    return TestCredential(testUser);
  }
}

void main() {
  late TestFirebaseAuth auth;
  late FirebaseAuthService service;
  setUp(() {
    auth = TestFirebaseAuth();
    service = FirebaseAuthService(auth);
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });
  test(
    'signup validates before creating account and requires verification',
    () async {
      await expectLater(
        service.signUp(
          email: 'invalid',
          password: 'longpassword12',
          name: 'Taylor',
        ),
        throwsFormatException,
      );
      await expectLater(
        service.signUp(
          email: 'person@example.com',
          password: 'short',
          name: 'Taylor',
        ),
        throwsFormatException,
      );
      expect(auth.creates, 0);
      final result = await service.signUp(
        email: ' person@example.com ',
        password: 'longpassword12',
        name: ' Taylor ',
      );
      expect(result.needsConfirmation, isTrue);
      expect(auth.testUser.savedName, 'Taylor');
      expect(auth.testUser.verificationEmails, 1);
      expect(auth.signsOut, 1);
      expect(service.currentUser, isNull);
    },
  );
  test(
    'unverified password login sends confirmation and removes temporary session',
    () async {
      await expectLater(
        service.signIn(email: 'person@example.com', password: 'longpassword12'),
        throwsA(
          isA<FirebaseAuthException>().having(
            (e) => e.code,
            'code',
            'email-not-verified',
          ),
        ),
      );
      expect(auth.signsOut, 1);
      expect(auth.testUser.verificationEmails, 1);
      expect(service.currentUser, isNull);
    },
  );
  test('verified login returns native Firebase identity', () async {
    auth.testUser.emailVerified = true;
    final result = await service.signIn(
      email: 'person@example.com',
      password: 'longpassword12',
    );
    expect(result.user, same(auth.testUser));
    expect(service.currentUser, same(auth.testUser));
    expect(auth.signsOut, 0);
  });
  test(
    'recovery validates email and password update requires a signed-in user',
    () async {
      expect(() => service.resetPassword('invalid'), throwsFormatException);
      await service.resetPassword(' person@example.com ');
      expect(auth.resetEmail, 'person@example.com');
      await expectLater(
        service.updatePassword('longpassword12'),
        throwsStateError,
      );
      auth.sessionUser = auth.testUser;
      await expectLater(service.updatePassword('short'), throwsFormatException);
      await service.updatePassword('newlongpassword12');
      expect(auth.testUser.savedPassword, 'newlongpassword12');
    },
  );
  test(
    'sensitive email operation reauthenticates and refreshes the ID token',
    () async {
      auth.sessionUser = auth.testUser;
      await service.reauthenticateWithEmail('longpassword12');
      expect(auth.testUser.reauthCredential, isA<EmailAuthCredential>());
      expect(auth.testUser.tokenRefreshes, 1);
    },
  );
  test('Apple uses Firebase native provider flow', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await service.signInWithApple();
    expect(auth.provider, isA<AppleAuthProvider>());
  });
  test('Google missing public OAuth configuration fails explicitly', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await expectLater(
      service.signInWithGoogle(),
      throwsA(
        isA<FirebaseAuthException>().having(
          (e) => e.code,
          'code',
          'provider-not-configured',
        ),
      ),
    );
  });
  test(
    'push document identifiers are deterministic hashes, not raw tokens',
    () {
      final id = PushService.tokenDocumentId('FCM:private/token');
      expect(id, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(id, PushService.tokenDocumentId('FCM:private/token'));
      expect(id, isNot(PushService.tokenDocumentId('other-token')));
    },
  );
}
