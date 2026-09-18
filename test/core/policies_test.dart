import 'package:flutter_test/flutter_test.dart';
import 'package:leanguard/core/domain/policies.dart';
import 'package:leanguard/core/services/report_service.dart';

void main() {
  test('Feature matrix all advanced gates and unlimited existing data', () {
    for (final f in ProFeature.values) {
      expect(EntitlementPolicy.allows(f, isPro: false), false);
      expect(EntitlementPolicy.allows(f, isPro: true), true);
    }
    expect(EntitlementPolicy.canReadExistingData, true);
    expect(EntitlementPolicy.coachLimit(false), 3);
    expect(EntitlementPolicy.coachLimit(true), 100);
    expect(EntitlementPolicy.canAddReminder(isPro: false, count: 3), false);
    expect(EntitlementPolicy.canLogMeasurement('waist', false), true);
    expect(EntitlementPolicy.canLogMeasurement('hips', false), false);
  });
  test(
    'Progress calculations avoid divide by zero and require longitudinal data',
    () {
      expect(ProgressMath.fraction(2, 0), 0);
      expect(ProgressMath.fraction(20, 10), 1);
      expect(ProgressMath.consistency(completed: 2, planned: 3), 67);
      expect(ProgressMath.weeklyLossPercent([]), null);
      expect(
        ProgressMath.readiness(
          observedDays: 1,
          proteinRatio: 1,
          stepsRatio: 1,
          workoutRatio: 1,
        ),
        null,
      );
      expect(ProgressMath.estimatedOneRepMax(30, 10), 40);
      expect(
        ProgressMath.rapidLossWithStrengthDecline(
          weeklyLossPercent: 1.2,
          strengthChangePercent: -6,
        ),
        true,
      );
      expect(
        ProgressMath.rapidLossWithStrengthDecline(
          weeklyLossPercent: null,
          strengthChangePercent: -6,
        ),
        false,
      );
    },
  );
  test('Offline medical and medication safety never depends on AI quota', () {
    for (final message in [
      'I fainted',
      'I have chest pain',
      'I am dehydrated',
      'I feel severe weakness',
      'What dose should I take?',
      'Should I stop semaglutide?',
      'My knee hurts with pain',
    ]) {
      expect(CoachSafety.localEscalation(message), isNotNull, reason: message);
    }
    expect(CoachSafety.localEscalation('How many sets did I log?'), null);
  });
  test('Validation rejects non-finite and invalid form data', () {
    expect(InputRules.number('NaN', min: 1, max: 100), isNotNull);
    expect(InputRules.number('Infinity', min: 1, max: 100), isNotNull);
    expect(InputRules.email('bad@'), isNotNull);
    expect(InputRules.email('a@example.com'), null);
    expect(InputRules.password('123'), isNotNull);
  });
  test('CSV filters period and escapes records', () {
    final csv = ReportService.toCsv({
      'weight_entries': [
        {'recorded_at': '2026-09-18T12:00:00Z', 'weight_kg': 80},
        {'recorded_at': '2020-01-01', 'weight_kg': 90},
      ],
    }, DateTime(2026, 9, 1));
    expect(csv, contains('80'));
    expect(csv, isNot(contains('90')));
    expect(ReportService.csvCell('a"b'), '"a""b"');
  });
  test('PDF report produces real PDF bytes', () async {
    final bytes = await ReportService.toPdf(
      {},
      DateTime(2026, 9, 1),
      clinician: true,
    );
    expect(String.fromCharCodes(bytes.take(4)), '%PDF');
    expect(bytes.length, greaterThan(1000));
  });
}
