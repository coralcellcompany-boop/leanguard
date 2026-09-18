import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:leanguard/app.dart';
import 'package:leanguard/core/state.dart';
import 'package:leanguard/core/data/repository.dart';

void main() {
  testWidgets('App opens welcome without credentials, no fake metrics', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          repositoryProvider.overrideWithValue(
            LeanRepository(store: MemoryLocalStore()),
          ),
        ],
        child: const LeanGuardApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Lose weight.'), findsOneWidget);
    expect(find.text('186.4'), findsNothing);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
