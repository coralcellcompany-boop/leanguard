import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';

class FirebaseSignUpResult {
  const FirebaseSignUpResult({required this.needsConfirmation});
  final bool needsConfirmation;
}

/// Firebase owns native refresh-token persistence; no password or OAuth token is
/// placed in the application cache, analytics, or notification payloads.
class FirebaseAuthService {
  FirebaseAuthService(this.auth);
  final FirebaseAuth auth;
  static Future<void>? _googleInitialization;
  User? get currentUser => auth.currentUser;
  Stream<User?> get userChanges => auth.userChanges();

  Future<FirebaseSignUpResult> signUp({
    required String email,
    required String password,
    required String name,
  }) async {
    _validateEmail(email);
    _validatePassword(password);
    if (name.trim().isEmpty || name.trim().length > 80) {
      throw const FormatException('Enter a name up to 80 characters.');
    }
    final result = await auth.createUserWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    try {
      await result.user!.updateDisplayName(name.trim());
      await result.user!.sendEmailVerification();
    } finally {
      await auth.signOut();
    }
    return const FirebaseSignUpResult(needsConfirmation: true);
  }

  Future<UserCredential> signIn({
    required String email,
    required String password,
  }) async {
    _validateEmail(email);
    final result = await auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    if (result.user?.emailVerified != true) {
      try {
        await result.user?.sendEmailVerification();
      } finally {
        await auth.signOut();
      }
      throw FirebaseAuthException(
        code: 'email-not-verified',
        message:
            'Verify your email before signing in. A verification link has been sent.',
      );
    }
    return result;
  }

  Future<void> resetPassword(String email) {
    _validateEmail(email);
    return auth.sendPasswordResetEmail(email: email.trim());
  }

  Future<void> updatePassword(String password) async {
    _validatePassword(password);
    await _requireUser().updatePassword(password);
  }

  Future<void> reauthenticateWithEmail(String password) async {
    final user = _requireUser();
    if (user.email == null) {
      throw StateError('Sign in again with your original provider.');
    }
    await user.reauthenticateWithCredential(
      EmailAuthProvider.credential(email: user.email!, password: password),
    );
    await user.getIdToken(true);
  }

  Future<UserCredential> signInWithApple() {
    final provider = AppleAuthProvider()
      ..addScope('email')
      ..addScope('name');
    return kIsWeb
        ? auth.signInWithPopup(provider)
        : auth.signInWithProvider(provider);
  }

  Future<UserCredential> signInWithGoogle() async {
    if (kIsWeb) return auth.signInWithPopup(GoogleAuthProvider());
    return auth.signInWithCredential(await _googleCredential());
  }

  Future<void> reauthenticateWithApple() async {
    final user = _requireUser();
    if (kIsWeb) {
      await user.reauthenticateWithPopup(AppleAuthProvider());
    } else {
      await user.reauthenticateWithProvider(AppleAuthProvider());
    }
    await user.getIdToken(true);
  }

  Future<void> reauthenticateWithGoogle() async {
    final user = _requireUser();
    if (kIsWeb) {
      await user.reauthenticateWithPopup(GoogleAuthProvider());
    } else {
      await user.reauthenticateWithCredential(await _googleCredential());
    }
    await user.getIdToken(true);
  }

  Future<AuthCredential> _googleCredential() async {
    const iosId = String.fromEnvironment('GOOGLE_IOS_CLIENT_ID');
    const webId = String.fromEnvironment('GOOGLE_WEB_CLIENT_ID');
    if (webId.isEmpty ||
        (defaultTargetPlatform == TargetPlatform.iOS && iosId.isEmpty)) {
      throw FirebaseAuthException(
        code: 'provider-not-configured',
        message: 'Google sign-in is not configured for this build.',
      );
    }
    _googleInitialization ??= GoogleSignIn.instance.initialize(
      clientId: defaultTargetPlatform == TargetPlatform.iOS ? iosId : null,
      serverClientId: webId,
    );
    await _googleInitialization;
    try {
      final account = await GoogleSignIn.instance.authenticate();
      final token = account.authentication.idToken;
      if (token == null) {
        throw StateError('Google did not return an identity token.');
      }
      return GoogleAuthProvider.credential(idToken: token);
    } on GoogleSignInException catch (error) {
      throw FirebaseAuthException(
        code: error.code == GoogleSignInExceptionCode.canceled
            ? 'sign-in-canceled'
            : 'google-sign-in-failed',
        message: error.code == GoogleSignInExceptionCode.canceled
            ? 'Sign-in was canceled.'
            : 'Google sign-in could not finish. Please try again.',
      );
    }
  }

  Future<void> signOut() async {
    try {
      if (_googleInitialization != null) await GoogleSignIn.instance.signOut();
    } finally {
      await auth.signOut();
    }
  }

  User _requireUser() =>
      auth.currentUser ?? (throw StateError('Sign in to continue.'));
  static void _validateEmail(String value) {
    if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(value.trim())) {
      throw const FormatException('Enter a valid email address.');
    }
  }

  static void _validatePassword(String value) {
    if (value.length < 12) {
      throw const FormatException('Use at least 12 characters.');
    }
  }
}
