import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:leanguard/core/data/firebase_repository.dart';
import 'package:leanguard/core/services/firebase_auth_service.dart';
import 'package:leanguard/core/state.dart';
import 'package:leanguard/features/support/presentation/support_screens.dart';

import '../screens_test.dart' show ScreenTestController;
import '../services/firebase_auth_test.dart'
    show TestFirebaseAuth, TestFirebaseUser;

class RejectedReauthUser extends TestFirebaseUser {
  @override
  Future<UserCredential> reauthenticateWithCredential(
    AuthCredential credential,
  ) async {
    throw FirebaseAuthException(
      code: 'wrong-password',
      message: 'That password could not verify this account.',
    );
  }
}

class ReauthRequiredController extends ScreenTestController {
  @override
  Future<void> recordConsent(String purpose, bool granted) async {
    throw const BackendException(
      401,
      'reauth_required',
      'Verify your identity.',
    );
  }
}

Future<void> _launch(
  WidgetTester tester,
  TestFirebaseAuth auth, {
  bool privacyAction = false,
}) async {
  final router = GoRouter(
    initialLocation: '/privacy',
    routes: [
      GoRoute(
        path: '/privacy',
        builder: (context, state) => privacyAction
            ? const PrivacyScreen()
            : Scaffold(
                body: TextButton(
                  onPressed: () => context.push('/reauth'),
                  child: const Text('Review sensitive action'),
                ),
              ),
      ),
      GoRoute(
        path: '/reauth',
        builder: (_, _) => const AuthScreen(reauthenticate: true),
      ),
    ],
  );
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(() {
    router.dispose();
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appProvider.overrideWith(
          (ref) => privacyAction
              ? ReauthRequiredController()
              : ScreenTestController(),
        ),
        authServiceProvider.overrideWithValue(FirebaseAuthService(auth)),
      ],
      child: MaterialApp.router(routerConfig: router),
    ),
  );
  if (!privacyAction) {
    await tester.tap(find.text('Review sensitive action'));
  }
  await tester.pumpAndSettle();
}

Finder _field(String label) => find.byWidgetPredicate(
  (widget) => widget is TextField && widget.decoration?.labelText == label,
);

void main() {
  testWidgets(
    'reauthentication is bound to the current account and accepts its password',
    (tester) async {
      final auth = TestFirebaseAuth();
      auth.sessionUser = auth.testUser;
      await _launch(tester, auth);
      expect(find.text('Verify your identity'), findsOneWidget);
      expect(find.text('New here? Create an account'), findsNothing);
      expect(find.text('Forgot password?'), findsNothing);
      expect(find.text('Explore local preview'), findsNothing);
      final emailField = _field('Email');
      if (emailField.evaluate().isNotEmpty) {
        final field = tester.widget<TextField>(emailField);
        expect(field.controller!.text, 'person@example.com');
        expect(field.readOnly || field.enabled == false, isTrue);
      }
      await tester.enterText(_field('Password'), 'current-password-12');
      await tester.tap(find.byType(FilledButton).first);
      await tester.pumpAndSettle();
      expect(find.text('Review sensitive action'), findsOneWidget);
      final credential = auth.testUser.reauthCredential as EmailAuthCredential;
      expect(credential.email, 'person@example.com');
      expect(credential.password, 'current-password-12');
      expect(auth.testUser.tokenRefreshes, 1);
      expect(auth.creates, 0);
      expect(auth.currentUser, same(auth.testUser));
      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('failed verification stays on the form without switching users', (
    tester,
  ) async {
    final user = RejectedReauthUser();
    final auth = TestFirebaseAuth()..sessionUser = user;
    await _launch(tester, auth);
    await tester.enterText(_field('Password'), 'incorrect-password');
    await tester.tap(find.byType(FilledButton).first);
    await tester.pumpAndSettle();
    expect(find.text('Verify your identity'), findsOneWidget);
    expect(
      find.text('That password could not verify this account.'),
      findsOneWidget,
    );
    expect(auth.currentUser, same(user));
    expect(auth.creates, 0);
    expect(user.tokenRefreshes, 0);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final cancel in [false, true]) {
    testWidgets(
      'privacy retry reports ${cancel ? 'canceled' : 'verified'} only from the returned verification result',
      (tester) async {
        final auth = TestFirebaseAuth();
        auth.sessionUser = auth.testUser;
        await _launch(tester, auth, privacyAction: true);
        await tester.tap(find.text('AI processing'));
        await tester.pumpAndSettle();
        expect(find.text('Verify your identity'), findsOneWidget);
        if (cancel) {
          await tester.pageBack();
        } else {
          await tester.enterText(_field('Password'), 'current-password-12');
          await tester.tap(find.text('Verify identity'));
        }
        await tester.pumpAndSettle();
        final resultText = cancel
            ? 'Verification was canceled. Verify your identity to retry this request.'
            : 'Identity verified. You can retry your request.';
        await tester.scrollUntilVisible(
          find.text(resultText),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        expect(
          find.text(resultText),
          findsOneWidget,
        );
        if (cancel) expect(auth.testUser.tokenRefreshes, 0);
        expect(auth.currentUser, same(auth.testUser));
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}
