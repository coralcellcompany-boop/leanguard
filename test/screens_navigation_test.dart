import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leanguard/app.dart';
import 'package:leanguard/core/state.dart';
import 'package:leanguard/features/onboarding/presentation/onboarding_screens.dart';
import 'screens_test.dart' show ScreenTestController;

void main() {
  testWidgets('welcome opens authentication through production router', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appProvider.overrideWith(
            (ref) => ScreenTestController(authenticated: false),
          ),
        ],
        child: const LeanGuardApp(),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Build my plan'));
    await tester.tap(find.text('Build my plan'));
    await tester.pumpAndSettle();
    expect(find.byType(WelcomeScreen), findsNothing);
    expect(find.text('Email'), findsWidgets);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
