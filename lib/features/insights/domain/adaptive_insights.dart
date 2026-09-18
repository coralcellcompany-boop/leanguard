import 'dart:math' as math;

/// A proposed personal habit goal. Callers must ask for approval before writing.
class TargetRecommendation {
  TargetRecommendation({
    required this.currentTarget,
    required this.suggestedTarget,
    required this.rationale,
    required List<String> evidence,
    this.isRecovery = false,
  }) : evidence = List.unmodifiable(evidence);
  final int currentTarget;
  final int suggestedTarget;
  final String rationale;
  final List<String> evidence;
  final bool isRecovery;
  bool get requiresApproval => true;
}

class InsightSuggestion {
  InsightSuggestion({
    required this.title,
    required this.description,
    List<String> evidence = const [],
  }) : evidence = List.unmodifiable(evidence);
  final String title;
  final String description;
  final List<String> evidence;
}

class ProteinDistribution {
  ProteinDistribution({
    required this.loggedDays,
    required this.averageLoggedGrams,
    required Map<String, double> mealTypeAverages,
    required this.highestMealShare,
    required this.rationale,
  }) : mealTypeAverages = Map.unmodifiable(mealTypeAverages);
  final int loggedDays;
  final double averageLoggedGrams;

  /// Recorded grams/category divided by recorded days; missing meals are unknown.
  final Map<String, double> mealTypeAverages;
  final double highestMealShare;
  final String rationale;
}

class WeightTrendPoint {
  const WeightTrendPoint({
    required this.date,
    required this.kg,
    required this.samples,
  });
  final DateTime date;
  final double kg;

  /// Number of observed calendar dates, not estimated or interpolated days.
  final int samples;
}

class InsightsBundle {
  InsightsBundle({
    this.walkingTarget,
    this.proteinTarget,
    this.proteinDistribution,
    List<InsightSuggestion> suggestions = const [],
    List<WeightTrendPoint> smoothedWeight = const [],
    this.weightPace,
    this.plateau,
    this.readiness,
    this.energyStepCorrelation,
    this.correlationSamples = 0,
    List<String> readinessEvidence = const [],
  }) : suggestions = List.unmodifiable(suggestions),
       smoothedWeight = List.unmodifiable(smoothedWeight),
       readinessEvidence = List.unmodifiable(readinessEvidence);
  final TargetRecommendation? walkingTarget;
  final TargetRecommendation? proteinTarget;
  final ProteinDistribution? proteinDistribution;
  final List<InsightSuggestion> suggestions;
  final List<WeightTrendPoint> smoothedWeight;

  /// Positive = weight loss, percent of the earlier average per week.
  final double? weightPace;

  /// A descriptive steady-weight heuristic, never a diagnosis.
  final bool? plateau;

  /// Nonclinical habit/relative-activity estimate, not exercise clearance.
  final int? readiness;
  final double? energyStepCorrelation;
  final int correlationSamples;
  final List<String> readinessEvidence;
}

/// Deterministic product heuristics, not clinically validated thresholds.
/// No missing observation is replaced by zero. This class performs no writes.
abstract final class AdaptiveInsights {
  static InsightsBundle evaluate({
    required List<Map<String, dynamic>> activities,
    required List<Map<String, dynamic>> meals,
    required List<Map<String, dynamic>> weights,
    required List<Map<String, dynamic>> workouts,
    required int proteinTarget,
    required int stepTarget,
    DateTime? now,
    List<String> allergies = const [],
    List<String> dietaryPreferences = const [],
    String appetiteLevel = 'normal',
    int? requestedProteinTarget,
    int weeklyWorkoutTarget = 3,
  }) {
    final instant = now ?? DateTime.now();
    final today = _day(instant);
    final activity = _activities(activities, instant);
    final complete = activity
        .where(
          (row) =>
              row.day.isBefore(today) &&
              !row.day.isBefore(today.subtract(const Duration(days: 14))),
        )
        .toList();
    final week = complete.length >= 7
        ? complete.sublist(complete.length - 7)
        : <_Activity>[];
    final suggestions = <InsightSuggestion>[];
    final walking = _walking(week, today, stepTarget);
    if (walking != null) {
      suggestions.add(
        InsightSuggestion(
          title: walking.isRecovery
              ? 'A manageable restart'
              : 'A small walking progression',
          description: walking.rationale,
          evidence: walking.evidence,
        ),
      );
    }

    final mealData = _meals(meals, instant);
    final recentMeals = mealData
        .where(
          (meal) => !meal.day.isBefore(today.subtract(const Duration(days: 6))),
        )
        .toList();
    final byDay = <DateTime, double>{};
    final byType = <String, double>{};
    for (final meal in recentMeals) {
      byDay.update(meal.day, (v) => v + meal.grams, ifAbsent: () => meal.grams);
      byType.update(
        meal.type,
        (v) => v + meal.grams,
        ifAbsent: () => meal.grams,
      );
    }
    ProteinDistribution? distribution;
    if (byDay.length >= 3) {
      final total = _sum(byDay.values);
      final most = byType.entries.reduce((a, b) => a.value > b.value ? a : b);
      final share = most.value / total;
      distribution = ProteinDistribution(
        loggedDays: byDay.length,
        averageLoggedGrams: total / byDay.length,
        mealTypeAverages: byType.map((k, v) => MapEntry(k, v / byDay.length)),
        highestMealShare: share,
        rationale:
            '${(share * 100).round()}% of your recorded protein was logged as ${most.key} across ${byDay.length} recorded days. Unlogged meals are unknown.',
      );
      if (share >= 0.6) {
        suggestions.add(
          InsightSuggestion(
            title: 'Spread your existing goal across the day',
            description:
                'If it suits your appetite, move some of the protein within your existing personal goal to another meal or snack. Your daily target has not changed.',
            evidence: [distribution.rationale],
          ),
        );
      }
    }
    final proteinProposal = _proteinProposal(
      requestedProteinTarget,
      proteinTarget,
      mealData,
      today,
    );
    final todayGrams = byDay[today] ?? 0.0;
    if (proteinTarget >= 20 &&
        proteinTarget <= 400 &&
        (todayGrams < proteinTarget || appetiteLevel != 'normal')) {
      final foods = safeProteinFoods(
        allergies: allergies,
        dietaryPreferences: dietaryPreferences,
      );
      final foodText = foods.isEmpty
          ? 'Choose a protein food you already know is safe for your allergies and eating preferences.'
          : 'Options matching the recorded preferences include ${foods.take(3).join(', ')}. Check ingredient labels and cross-contact information before choosing a product.';
      final low = appetiteLevel == 'low' || appetiteLevel == 'very_low';
      suggestions.add(
        InsightSuggestion(
          title: low
              ? 'Keep portions manageable'
              : 'An idea for your next meal',
          description: low
              ? 'Try smaller, manageable portions at separate eating occasions within your existing goal. $foodText If a low appetite persists or you cannot eat or drink enough, contact your clinician.'
              : foodText,
          evidence: [
            'Your saved personal protein goal is $proteinTarget g/day.',
            '${todayGrams.toStringAsFixed(0)} g of protein is recorded today; unlogged food is unknown.',
            if (low)
              'You selected ${appetiteLevel == 'very_low' ? 'very low' : 'low'} appetite.',
          ],
        ),
      );
    }

    final dailyWeights = _weights(weights, instant);
    final smoothed = <WeightTrendPoint>[];
    for (final point in dailyWeights) {
      final window = dailyWeights
          .where(
            (p) =>
                !p.day.isAfter(point.day) &&
                !p.day.isBefore(point.day.subtract(const Duration(days: 6))),
          )
          .toList();
      if (window.length >= 3) {
        smoothed.add(
          WeightTrendPoint(
            date: point.day,
            kg: _mean(window.map((p) => p.kg)),
            samples: window.length,
          ),
        );
      }
    }
    final recentWeights = dailyWeights
        .where(
          (point) =>
              !point.day.isBefore(today.subtract(const Duration(days: 27))),
        )
        .toList();
    double? pace;
    bool? plateau;
    if (recentWeights.length >= 4 &&
        today.difference(recentWeights.last.day).inDays <= 7 &&
        recentWeights.last.day.difference(recentWeights.first.day).inDays >=
            13) {
      final first = recentWeights
          .where(
            (point) =>
                point.day.difference(recentWeights.first.day).inDays <= 6,
          )
          .toList();
      final last = recentWeights
          .where(
            (point) => recentWeights.last.day.difference(point.day).inDays <= 6,
          )
          .toList();
      if (first.length >= 2 && last.length >= 2) {
        final firstMean = _mean(first.map((point) => point.kg)),
            lastMean = _mean(last.map((point) => point.kg));
        final elapsed =
            (_mean(
                  last.map(
                    (point) => point.day.millisecondsSinceEpoch.toDouble(),
                  ),
                ) -
                _mean(
                  first.map(
                    (point) => point.day.millisecondsSinceEpoch.toDouble(),
                  ),
                )) /
            Duration.millisecondsPerDay;
        if (elapsed >= 7) {
          pace = (firstMean - lastMean) / firstMean * 100 * 7 / elapsed;
        }
        if (recentWeights.length >= 14 &&
            recentWeights.last.day.difference(recentWeights.first.day).inDays >=
                21 &&
            first.length >= 3 &&
            last.length >= 3 &&
            today.difference(recentWeights.last.day).inDays <= 3) {
          plateau = ((lastMean - firstMean) / firstMean).abs() <= 0.0025;
          if (plateau) {
            suggestions.add(
              InsightSuggestion(
                title: 'Your recent weight averages are steady',
                description:
                    'This describes your logs; it does not identify a cause or mean your plan has failed. Keep the full picture in view, including strength and how you feel.',
                evidence: [
                  '${recentWeights.length} recorded weight days across ${recentWeights.last.day.difference(recentWeights.first.day).inDays + 1} calendar days.',
                  'Earlier and recent seven-day recorded averages differ by ${((lastMean - firstMean) / firstMean * 100).toStringAsFixed(2)}%.',
                ],
              ),
            );
          }
        }
      }
    }

    final energy = complete.where((row) => row.wearableEnergy != null).toList();
    int? readiness;
    final readinessEvidence = <String>[];
    if (week.length >= 7 &&
        today.difference(week.last.day).inDays <= 2 &&
        energy.length >= 6 &&
        stepTarget > 0) {
      final recentEnergy = energy.sublist(energy.length - 2),
          baselineEnergy = energy.sublist(0, energy.length - 2);
      final baseline = _median(
        baselineEnergy.map((row) => row.wearableEnergy!).toList(),
      );
      if (baseline > 0) {
        final energyRatio =
            _mean(recentEnergy.map((row) => row.wearableEnergy!)) / baseline;
        final stepRatio = _mean(
          week.map((row) => (row.steps / stepTarget).clamp(0, 1).toDouble()),
        );
        var weighted = stepRatio * 0.6, observedWeight = 0.6;
        if (byDay.length >= 3 && proteinTarget > 0) {
          weighted +=
              _mean(
                byDay.values.map(
                  (grams) => (grams / proteinTarget).clamp(0, 1).toDouble(),
                ),
              ) *
              0.25;
          observedWeight += 0.25;
        }
        final loggedWorkouts = workouts
            .where(
              (row) =>
                  ['completed', 'skipped'].contains(row['status']) &&
                  _inRecentWeek(
                    row['completed_at'] ?? row['started_at'],
                    instant,
                  ),
            )
            .toList();
        if (loggedWorkouts.isNotEmpty && weeklyWorkoutTarget > 0) {
          weighted +=
              (loggedWorkouts
                          .where((row) => row['status'] == 'completed')
                          .length /
                      weeklyWorkoutTarget)
                  .clamp(0, 1) *
              0.15;
          observedWeight += 0.15;
        }
        final penalty = ((energyRatio - 1.5) * 10).clamp(0, 15);
        readiness = (weighted / observedWeight * 100 - penalty).round().clamp(
          0,
          100,
        );
        readinessEvidence.addAll([
          'Seven completed days of actual step logs; ${(stepRatio * 100).round()}% average of your saved target.',
          '${energy.length} wearable active-energy days; recent average ${(energyRatio * 100).round()}% of your recorded baseline.',
          'A habit and relative-activity estimate, not a measure of muscle recovery or medical clearance.',
        ]);
      }
    }
    final pairs = activity
        .where(
          (row) =>
              row.day.isBefore(today) &&
              !row.day.isBefore(today.subtract(const Duration(days: 28))) &&
              row.wearableEnergy != null,
        )
        .toList();
    double? correlation;
    if (pairs.length >= 14 &&
        pairs.last.day.difference(pairs.first.day).inDays >= 13 &&
        today.difference(pairs.last.day).inDays <= 7) {
      correlation = _correlation(
        pairs.map((row) => row.steps.toDouble()).toList(),
        pairs.map((row) => row.wearableEnergy!).toList(),
      );
      if (correlation != null) {
        suggestions.add(
          InsightSuggestion(
            title: 'How your activity measures move together',
            description: correlation.abs() < 0.3
                ? 'Your recorded steps and active energy show little consistent linear association in this period. This does not establish cause or measure recovery.'
                : 'Your recorded steps and active energy tended to move ${correlation >= 0 ? 'together' : 'in opposite directions'} in this period. This association does not establish cause or measure recovery.',
            evidence: [
              '${pairs.length} paired days from health imports.',
              'Descriptive correlation: ${correlation.toStringAsFixed(2)} (range -1 to 1).',
            ],
          ),
        );
      }
    }
    return InsightsBundle(
      walkingTarget: walking,
      proteinTarget: proteinProposal,
      proteinDistribution: distribution,
      suggestions: suggestions,
      smoothedWeight: smoothed,
      weightPace: pace,
      plateau: plateau,
      readiness: readiness,
      readinessEvidence: readinessEvidence,
      energyStepCorrelation: correlation,
      correlationSamples: pairs.length,
    );
  }

  static TargetRecommendation? _walking(
    List<_Activity> week,
    DateTime today,
    int target,
  ) {
    if (week.length < 7 ||
        target < 500 ||
        target > 50000 ||
        today.difference(week.last.day).inDays > 2) {
      return null;
    }
    final met = week.where((row) => row.steps >= target).length;
    final mean = _mean(week.map((row) => row.steps.toDouble()));
    final evidence = [
      'Seven completed logged days; $met met your saved $target-step goal.',
      'Recorded average: ${mean.round()} steps/day.',
    ];
    final last = week.last, previous = week[week.length - 2];
    final recovery =
        last.day.difference(previous.day).inDays == 1 &&
        today.difference(last.day).inDays == 1 &&
        last.steps < target * 0.75 &&
        previous.steps < target * 0.75;
    if (recovery) {
      final suggested = math.max(500, (target * 0.9).ceil());
      if (suggested >= target) {
        return null;
      }
      return TargetRecommendation(
        currentTarget: target,
        suggestedTarget: suggested.toInt(),
        isRecovery: true,
        rationale:
            'Your last two recorded days were below your current goal. If a lighter restart feels manageable, try $suggested steps without trying to make up missed steps. Approve this change only if it suits you.',
        evidence: [
          ...evidence,
          'The two most recent recorded days were ${previous.steps} and ${last.steps} steps.',
        ],
      );
    }
    final lowEnergy = week.any(
      (row) => row.energyLevel != null && row.energyLevel! <= 2,
    );
    if (met >= 6 && mean >= target * 1.05 && !lowEnergy) {
      final suggested = math.min(
        50000,
        target + math.min(250, (target * 0.05).floor()),
      );
      if (suggested <= target) {
        return null;
      }
      return TargetRecommendation(
        currentTarget: target,
        suggestedTarget: suggested.toInt(),
        rationale:
            'You have consistently reached your saved goal. If your current walks feel comfortable, consider a small increase to $suggested steps. Keep the current goal if you prefer.',
        evidence: evidence,
      );
    }
    return null;
  }

  static TargetRecommendation? _proteinProposal(
    int? requested,
    int current,
    List<_Meal> meals,
    DateTime today,
  ) {
    if (requested == null ||
        current < 20 ||
        current > 300 ||
        requested < 20 ||
        requested > 300 ||
        requested == current ||
        (requested - current).abs() > current * 0.1) {
      return null;
    }
    final days = <DateTime, double>{};
    for (final meal in meals.where(
      (meal) => !meal.day.isBefore(today.subtract(const Duration(days: 13))),
    )) {
      days.update(meal.day, (v) => v + meal.grams, ifAbsent: () => meal.grams);
    }
    if (days.length < 7) {
      return null;
    }
    return TargetRecommendation(
      currentTarget: current,
      suggestedTarget: requested,
      rationale:
          'You requested a change to your personal habit goal from $current g to $requested g. This does not calculate your nutritional requirement from weight or prescribe an intake. Confirm only if it agrees with your personal or clinician-set plan.',
      evidence: [
        '${days.length} days contain protein logs in the last 14 days.',
        '${_mean(days.values).round()} g/day was recorded on those days; unlogged intake is unknown.',
        'The requested change is within 10% of your existing personal goal.',
      ],
    );
  }

  /// A small ingredient-level catalog, never a guarantee that a branded product
  /// is allergen-free. Unknown restrictions produce no named food suggestions.
  static List<String> safeProteinFoods({
    List<String> allergies = const [],
    List<String> dietaryPreferences = const [],
  }) {
    final avoided = <String>{};
    final aliases = <String, List<String>>{
      'milk': ['milk', 'dairy', 'lactose', 'casein', 'whey'],
      'egg': ['egg', 'eggs'],
      'soy': ['soy', 'soya', 'soybean', 'soybeans'],
      'peanut': ['peanut', 'peanuts'],
      'tree_nut': [
        'nut',
        'nuts',
        'almond',
        'almonds',
        'cashew',
        'cashews',
        'walnut',
        'walnuts',
      ],
      'fish': ['fish', 'salmon', 'tuna'],
      'shellfish': ['shellfish', 'shrimp', 'prawn', 'crab', 'lobster'],
      'wheat': ['wheat', 'gluten', 'celiac', 'coeliac'],
      'sesame': ['sesame', 'tahini'],
      'legume': ['legume', 'legumes', 'lentil', 'lentils', 'bean', 'beans'],
    };
    List<String> restrictions(List<String> values) => values
        .expand(
          (raw) => raw
              .trim()
              .toLowerCase()
              .replaceAll('_', ' ')
              .replaceAll('-', ' ')
              .split(RegExp(r'\s*(?:,|;|/|&|\band\b|\bor\b)\s*')),
        )
        .where((term) => term.isNotEmpty)
        .toList();
    for (final text in restrictions(allergies)) {
      if (['none', 'no allergies'].contains(text)) continue;
      final matches = aliases.entries.where(
        (entry) =>
            entry.value.contains(text) ||
            entry.key.replaceAll('_', ' ') == text ||
            entry.key == 'tree_nut' && text == 'tree nuts',
      );
      if (matches.isEmpty) return const [];
      avoided.addAll(matches.map((entry) => entry.key));
    }
    var vegan = false, vegetarian = false, pescatarian = false;
    for (final text in restrictions(dietaryPreferences)) {
      if ([
        'none',
        'omnivore',
        'no preference',
        'no restrictions',
        'balanced',
      ].contains(text)) {
        continue;
      }
      if (['vegan', 'plant based'].contains(text)) {
        vegan = true;
        continue;
      }
      if (text == 'vegetarian') {
        vegetarian = true;
        continue;
      }
      if (text == 'pescatarian') {
        pescatarian = true;
        continue;
      }
      if (['dairy free', 'lactose free'].contains(text)) {
        avoided.add('milk');
        continue;
      }
      if (text == 'egg free') {
        avoided.add('egg');
        continue;
      }
      if (text == 'soy free') {
        avoided.add('soy');
        continue;
      }
      if (['gluten free', 'wheat free'].contains(text)) {
        avoided.add('wheat');
        continue;
      }
      return const [];
    }
    final options =
        <
          ({
            String name,
            Set<String> allergens,
            bool vegan,
            bool vegetarian,
            bool pescatarian,
          })
        >[
          (
            name: 'plain Greek yogurt',
            allergens: {'milk'},
            vegan: false,
            vegetarian: true,
            pescatarian: true,
          ),
          (
            name: 'eggs',
            allergens: {'egg'},
            vegan: false,
            vegetarian: true,
            pescatarian: true,
          ),
          (
            name: 'plain tofu',
            allergens: {'soy', 'legume'},
            vegan: true,
            vegetarian: true,
            pescatarian: true,
          ),
          (
            name: 'lentils',
            allergens: {'legume'},
            vegan: true,
            vegetarian: true,
            pescatarian: true,
          ),
          (
            name: 'plain chicken',
            allergens: {},
            vegan: false,
            vegetarian: false,
            pescatarian: false,
          ),
          (
            name: 'plain fish',
            allergens: {'fish'},
            vegan: false,
            vegetarian: false,
            pescatarian: true,
          ),
        ];
    return List.unmodifiable(
      options
          .where(
            (food) =>
                food.allergens.intersection(avoided).isEmpty &&
                (!vegan || food.vegan) &&
                (!vegetarian || food.vegetarian) &&
                (!pescatarian || food.pescatarian),
          )
          .map((food) => food.name),
    );
  }
}

class _Activity {
  const _Activity(
    this.day,
    this.steps,
    this.wearableEnergy,
    this.energyLevel,
    this.manual,
    this.order,
  );
  final DateTime day;
  final int steps;
  final double? wearableEnergy;
  final int? energyLevel;
  final bool manual;
  final DateTime order;
}

class _Meal {
  const _Meal(this.day, this.grams, this.type);
  final DateTime day;
  final double grams;
  final String type;
}

class _Weight {
  const _Weight(this.day, this.kg);
  final DateTime day;
  final double kg;
}

DateTime _day(DateTime date) => DateTime.utc(date.year, date.month, date.day);
DateTime? _parseDay(dynamic value, DateTime now) {
  final raw = value?.toString() ?? '';
  final parsed = DateTime.tryParse(raw);
  if (parsed == null) {
    return null;
  }
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) {
    return _day(parsed);
  }
  return _day(now.isUtc ? parsed.toUtc() : parsed.toLocal());
}

DateTime? _parseInstant(dynamic value) =>
    DateTime.tryParse(value?.toString() ?? '');
double? _number(dynamic value) {
  final n = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
  return n != null && n.isFinite ? n : null;
}

double _sum(Iterable<double> values) => values.fold(0, (a, b) => a + b);
double _mean(Iterable<double> values) => _sum(values) / values.length;
double _median(List<double> values) {
  final sorted = [...values]..sort();
  final n = sorted.length;
  return n.isOdd ? sorted[n ~/ 2] : (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2;
}

List<_Activity> _activities(List<Map<String, dynamic>> rows, DateTime now) {
  final byDay = <DateTime, _Activity>{};
  for (final row in rows) {
    final day = _parseDay(row['date'], now), steps = _number(row['steps']);
    if (day == null ||
        day.isAfter(_day(now)) ||
        steps == null ||
        steps < 0 ||
        steps > 200000 ||
        steps != steps.roundToDouble()) {
      continue;
    }
    final energy = _number(row['active_energy_kcal']);
    final level = _number(row['energy_level']);
    final wearable = ['apple_health', 'health_connect'].contains(row['source']);
    final entry = _Activity(
      day,
      steps.toInt(),
      wearable && energy != null && energy > 0 && energy <= 50000
          ? energy
          : null,
      level != null && level >= 1 && level <= 5 ? level.toInt() : null,
      row['source'] == 'manual',
      _parseInstant(row['updated_at'] ?? row['created_at']) ?? day,
    );
    final old = byDay[day];
    if (old == null ||
        (entry.manual && !old.manual) ||
        (entry.manual == old.manual && !entry.order.isBefore(old.order))) {
      byDay[day] = entry;
    }
  }
  return byDay.values.toList()..sort((a, b) => a.day.compareTo(b.day));
}

List<_Meal> _meals(List<Map<String, dynamic>> rows, DateTime now) {
  final result = <_Meal>[], ids = <String>{};
  for (final row in rows) {
    final id = row['id']?.toString();
    if (id != null && !ids.add(id)) {
      continue;
    }
    final at = _parseInstant(row['recorded_at']),
        day = _parseDay(row['recorded_at'], now),
        grams = _number(row['protein_g']);
    if (at == null ||
        at.isAfter(now) ||
        day == null ||
        grams == null ||
        grams <= 0 ||
        grams > 300) {
      continue;
    }
    final type = row['meal_type']?.toString() ?? 'snack';
    result.add(
      _Meal(
        day,
        grams,
        ['breakfast', 'lunch', 'dinner', 'snack'].contains(type)
            ? type
            : 'other',
      ),
    );
  }
  return result;
}

List<_Weight> _weights(List<Map<String, dynamic>> rows, DateTime now) {
  final byDay = <DateTime, List<double>>{}, external = <String>{};
  for (final row in rows) {
    if (row['external_id'] != null &&
        !external.add('${row['source']}:${row['external_id']}')) {
      continue;
    }
    final at = _parseInstant(row['recorded_at']),
        day = _parseDay(row['recorded_at'], now),
        kg = _number(row['weight_kg']);
    if (at == null ||
        at.isAfter(now) ||
        day == null ||
        kg == null ||
        kg < 20 ||
        kg > 500) {
      continue;
    }
    byDay.putIfAbsent(day, () => []).add(kg);
  }
  return byDay.entries
      .map((entry) => _Weight(entry.key, _median(entry.value)))
      .toList()
    ..sort((a, b) => a.day.compareTo(b.day));
}

bool _inRecentWeek(dynamic value, DateTime now) {
  final at = _parseInstant(value);
  return at != null &&
      !at.isAfter(now) &&
      !at.isBefore(now.subtract(const Duration(days: 7)));
}

double? _correlation(List<double> x, List<double> y) {
  final mx = _mean(x), my = _mean(y);
  double numerator = 0, xx = 0, yy = 0;
  for (var i = 0; i < x.length; i++) {
    final dx = x[i] - mx, dy = y[i] - my;
    numerator += dx * dy;
    xx += dx * dx;
    yy += dy * dy;
  }
  if (xx <= 0 || yy <= 0) {
    return null;
  }
  return (numerator / math.sqrt(xx * yy)).clamp(-1, 1).toDouble();
}
