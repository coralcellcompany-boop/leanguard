import 'package:flutter_test/flutter_test.dart';
import 'package:leanguard/features/insights/domain/adaptive_insights.dart';

final _now = DateTime(2026, 9, 18, 12);
Map<String, dynamic> _activity(
  int daysAgo,
  int steps, {
  bool wearable = false,
  double? energy,
  int? feeling,
}) => {
  'date': _now
      .subtract(Duration(days: daysAgo))
      .toIso8601String()
      .substring(0, 10),
  'steps': steps,
  'source': wearable ? 'apple_health' : 'manual',
  'active_energy_kcal': ?energy,
  'energy_level': ?feeling,
};
Map<String, dynamic> _meal(int daysAgo) => {
  'recorded_at': _now.subtract(Duration(days: daysAgo)).toIso8601String(),
  'protein_g': 90,
  'meal_type': 'dinner',
};
InsightsBundle _evaluate({
  List<Map<String, dynamic>> activities = const [],
  List<Map<String, dynamic>> meals = const [],
  List<Map<String, dynamic>> weights = const [],
  int? requested,
}) => AdaptiveInsights.evaluate(
  activities: activities,
  meals: meals,
  weights: weights,
  workouts: const [],
  proteinTarget: 116,
  stepTarget: 8000,
  requestedProteinTarget: requested,
  now: _now,
);

void main() {
  test('sparse logs produce no fabricated scores or target proposals', () {
    final result = _evaluate();
    expect(result.walkingTarget, isNull);
    expect(result.proteinTarget, isNull);
    expect(result.proteinDistribution, isNull);
    expect(result.weightPace, isNull);
    expect(result.plateau, isNull);
    expect(result.readiness, isNull);
    expect(result.energyStepCorrelation, isNull);
  });
  test(
    'consistent completed days suggest a capped walking increase requiring approval',
    () {
      final records = List.generate(7, (i) => _activity(i + 1, 9000));
      final result = _evaluate(activities: records).walkingTarget!;
      expect(result.currentTarget, 8000);
      expect(result.suggestedTarget, 8250);
      expect(result.requiresApproval, isTrue);
      expect(records.every((row) => row['steps'] == 9000), isTrue);
    },
  );
  test('missing observation days are not fabricated as zero-step days', () {
    expect(
      _evaluate(
        activities: List.generate(6, (i) => _activity(i + 1, 9000)),
      ).walkingTarget,
      isNull,
    );
  });
  test(
    'recent lower activity yields conservative optional recovery target',
    () {
      final result = _evaluate(
        activities: List.generate(
          7,
          (i) => _activity(i + 1, i < 2 ? 2000 : 9000),
        ),
      ).walkingTarget!;
      expect(result.isRecovery, isTrue);
      expect(result.suggestedTarget, 7200);
      expect(result.requiresApproval, isTrue);
    },
  );
  test(
    'protein changes need user request, sufficient logs, and conservative range',
    () {
      final meals = List.generate(7, _meal);
      expect(_evaluate(meals: meals).proteinTarget, isNull);
      expect(_evaluate(meals: meals, requested: 150).proteinTarget, isNull);
      expect(_evaluate(requested: 120).proteinTarget, isNull);
      final target = _evaluate(meals: meals, requested: 120).proteinTarget!;
      expect(target.currentTarget, 116);
      expect(target.suggestedTarget, 120);
      expect(target.requiresApproval, isTrue);
    },
  );
  test(
    'unknown compound allergy fails closed instead of suggesting named foods',
    () {
      expect(
        AdaptiveInsights.safeProteinFoods(allergies: ['milk and chicken']),
        isEmpty,
      );
      expect(
        AdaptiveInsights.safeProteinFoods(
          allergies: ['sesame', 'unknown ingredient'],
        ),
        isEmpty,
      );
      expect(
        AdaptiveInsights.safeProteinFoods(
          dietaryPreferences: ['vegan except soy'],
        ),
        isEmpty,
      );
    },
  );
  test('recognized compound restrictions filter every named ingredient', () {
    final foods = AdaptiveInsights.safeProteinFoods(
      allergies: ['milk and soy'],
    );
    expect(foods, isNot(contains('plain Greek yogurt')));
    expect(foods, isNot(contains('plain tofu')));
    expect(foods, contains('eggs'));
    expect(
      AdaptiveInsights.safeProteinFoods(
        dietaryPreferences: ['vegan and soy free'],
      ),
      ['lentils'],
    );
  });
  test(
    'stable long history produces descriptive plateau with observed smoothing',
    () {
      final weights = List.generate(
        28,
        (i) => {
          'recorded_at': _now.subtract(Duration(days: i)).toIso8601String(),
          'weight_kg': 80.0,
        },
      );
      final result = _evaluate(weights: weights);
      expect(result.weightPace, closeTo(0, 0.00001));
      expect(result.plateau, isTrue);
      expect(result.smoothedWeight, isNotEmpty);
      expect(
        result.smoothedWeight.every(
          (point) => point.kg == 80 && point.samples >= 3,
        ),
        isTrue,
      );
    },
  );
  test(
    'wearable correlation requires paired days and nonconstant observations',
    () {
      final manual = List.generate(
        14,
        (i) => _activity(i + 1, 7000 + i * 100, energy: 200.0 + i * 10),
      );
      expect(_evaluate(activities: manual).energyStepCorrelation, isNull);
      final wearable = List.generate(
        14,
        (i) => _activity(
          i + 1,
          7000 + i * 100,
          wearable: true,
          energy: 200.0 + i * 10,
        ),
      );
      final result = _evaluate(activities: wearable);
      expect(result.correlationSamples, 14);
      expect(result.energyStepCorrelation, closeTo(1, 0.0001));
    },
  );
}
