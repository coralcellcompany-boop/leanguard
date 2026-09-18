import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leanguard/app.dart';
import 'package:leanguard/core/data/repository.dart';
import 'package:leanguard/core/services/health_service.dart';
import 'package:leanguard/core/services/background_health_service.dart';
import 'package:leanguard/core/services/notification_service.dart';
import 'package:leanguard/core/services/subscription_service.dart';
import 'package:leanguard/core/state.dart';

class WidgetHealthService extends HealthService {
  @override
  Future<void> disconnect() async {}
}

class DeniedHealthService extends WidgetHealthService {
  @override
  Future<HealthAccess> requestAccess({bool pro = false}) async =>
      HealthAccess.denied;
}

class WidgetBackgroundHealth extends BackgroundHealthService {
  @override
  Future<void> disable() async {}
}

class WidgetNotifications extends NotificationService {
  @override
  Future<void> cancelAll() async {}
}

class SupportController extends AppController {
  SupportController(LeanRepository repo, {HealthService? health})
    : super(
        repo,
        SubscriptionService(),
        health ?? WidgetHealthService(),
        WidgetNotifications(),
      );
  final _background = WidgetBackgroundHealth();
  @override
  BackgroundHealthService get backgroundHealth => _background;
  void signedInForPermissionTest() =>
      state = state.copy(demo: false, authenticated: true);
}

class SupportHarness {
  SupportHarness(this.container, this.controller, this.repo);
  final ProviderContainer container;
  final SupportController controller;
  final LeanRepository repo;
  Future<void> push(WidgetTester tester, String route) async {
    container.read(routerProvider).push(route);
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    container.dispose();
  }
}

Future<SupportHarness> launch(
  WidgetTester tester, {
  bool preview = true,
  HealthService? health,
}) async {
  tester.view.physicalSize = const Size(430, 932);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final repo = LeanRepository(store: MemoryLocalStore());
  final controller = SupportController(repo, health: health);
  await controller.initialize();
  if (preview) {
    await controller.enterDemo();
    await controller.finishOnboarding();
  }
  final container = ProviderContainer(
    overrides: [
      repositoryProvider.overrideWithValue(repo),
      appProvider.overrideWith((ref) => controller),
    ],
  );
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: const LeanGuardApp(),
    ),
  );
  await tester.pumpAndSettle();
  return SupportHarness(container, controller, repo);
}

Finder field(String label) => find.byWidgetPredicate(
  (w) => w is TextField && w.decoration?.labelText == label,
);
Future<void> tapLabel(WidgetTester tester, String text) async {
  final matches = find.text(text);
  if (matches.evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      matches,
      300,
      scrollable: find.byType(Scrollable).first,
    );
  }
  await tester.ensureVisible(matches.last);
  await tester.tap(matches.last);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'authentication validates email and signup password; recovery is navigable',
    (tester) async {
      final h = await launch(tester, preview: false);
      await h.push(tester, '/auth');
      await tapLabel(tester, 'Sign in');
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(find.text('Enter your password.'), findsOneWidget);
      await tapLabel(tester, 'New here? Create an account');
      await tester.enterText(field('Your name'), 'Taylor');
      await tester.enterText(field('Email'), 'taylor@example.com');
      await tester.enterText(field('Password'), 'short');
      await tapLabel(tester, 'Create account');
      expect(find.text('Use at least 12 characters.'), findsOneWidget);
      await tapLabel(tester, 'Forgot password?');
      expect(find.text('Send reset link'), findsOneWidget);
      await tester.enterText(field('Email'), 'not-an-email');
      await tapLabel(tester, 'Send reset link');
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      await h.close(tester);
    },
  );

  testWidgets(
    'weight validates then persists through real controller and route pop',
    (tester) async {
      final h = await launch(tester);
      await h.push(tester, '/add-weight');
      await tester.enterText(field('kg'), '0');
      await tapLabel(tester, 'Save entry');
      expect(h.repo.rows('weight_entries'), isEmpty);
      expect(find.textContaining('Enter a number between'), findsOneWidget);
      await tester.enterText(field('kg'), '84.2');
      await tapLabel(tester, 'Save entry');
      expect(h.repo.rows('weight_entries').single['weight_kg'], 84.2);
      expect(find.text('Add weight'), findsNothing);
      await h.close(tester);
    },
  );

  testWidgets('protein meal entry rejects missing name and stores valid meal', (
    tester,
  ) async {
    final h = await launch(tester);
    await h.push(tester, '/add-meal');
    await tester.enterText(field('g protein'), '30');
    await tapLabel(tester, 'Save entry');
    expect(find.text('Name your meal.'), findsOneWidget);
    await tester.enterText(field('Meal or food'), 'Greek yogurt');
    await tapLabel(tester, 'Save entry');
    expect(h.repo.rows('protein_entries').single['name'], 'Greek yogurt');
    expect(h.repo.rows('protein_entries').single['protein_g'], 30);
    await h.close(tester);
  });

  testWidgets('Free measurement exposes waist and links its upgrade action', (
    tester,
  ) async {
    final h = await launch(tester);
    await h.push(tester, '/add-measurement');
    final dropdown = tester.widget<DropdownButtonFormField<String>>(
      find.byType(DropdownButtonFormField<String>),
    );
    expect(dropdown.initialValue, 'waist');
    await tapLabel(tester, 'Track all measurements with Pro');
    expect(find.text('Restore purchases'), findsOneWidget);
    expect(
      find.textContaining('Purchases are unavailable in sample preview'),
      findsOneWidget,
    );
    await h.close(tester);
  });

  testWidgets(
    'profile changes save and target validation prevents invalid values',
    (tester) async {
      final h = await launch(tester);
      await h.push(tester, '/edit-profile');
      await tester.enterText(field('Name'), 'Taylor');
      await tapLabel(tester, 'Save changes');
      expect(h.container.read(appProvider).name, 'Taylor');
      await h.push(tester, '/targets');
      await tester.enterText(field('Daily steps'), '-1');
      await tapLabel(tester, 'Save changes');
      expect(find.textContaining('Enter a number between'), findsOneWidget);
      await h.close(tester);
    },
  );

  testWidgets(
    'health denial preserves manual logging and notification preview reports unavailable',
    (tester) async {
      final h = await launch(tester, health: DeniedHealthService());
      h.controller.signedInForPermissionTest();
      await h.push(tester, '/health-permission');
      await tapLabel(tester, 'Choose what to share');
      expect(
        find.textContaining(
          'Permission was denied. Manual logging still works.',
        ),
        findsOneWidget,
      );
      await tapLabel(tester, 'Continue with manual logging');
      expect(h.container.read(appProvider).onboardingComplete, isTrue);
      await h.controller.enterDemo();
      await h.push(tester, '/notification-permission');
      await tapLabel(tester, 'Allow notifications');
      expect(
        find.textContaining(
          'Notifications are unavailable or permission was denied.',
        ),
        findsOneWidget,
      );
      await h.close(tester);
    },
  );

  testWidgets(
    'privacy consent updates and deletion cancellation preserves all logs',
    (tester) async {
      final h = await launch(tester);
      await h.controller.addWeight(80);
      await h.push(tester, '/privacy');
      final consent = find.widgetWithText(SwitchListTile, 'AI processing');
      await tester.tap(consent);
      await tester.pumpAndSettle();
      expect(h.controller.hasConsent('ai_processing'), isTrue);
      await tapLabel(tester, 'Delete my account');
      expect(find.text('Permanently delete account?'), findsOneWidget);
      await tapLabel(tester, 'Delete permanently');
      expect(find.text('Permanently delete account?'), findsOneWidget);
      await tapLabel(tester, 'Keep account');
      expect(h.repo.rows('weight_entries'), hasLength(1));
      await h.close(tester);
    },
  );

  testWidgets(
    'exercise detail, empty workout summary and Free quiet-hour gate work',
    (tester) async {
      final h = await launch(tester);
      final exerciseId = h.container.read(appProvider).exercises.first['id'];
      await h.push(tester, '/exercise/$exerciseId');
      expect(find.text('Technique'), findsOneWidget);
      expect(
        find.text('No sets yet. Your logged sets will appear here.'),
        findsOneWidget,
      );
      await h.push(tester, '/workout-summary');
      expect(find.text('Start a workout to see your summary.'), findsOneWidget);
      await h.push(tester, '/quiet-hours');
      await tapLabel(tester, 'Save quiet hours');
      expect(find.text('Quiet hours are included with Pro.'), findsOneWidget);
      await h.close(tester);
    },
  );
}
