import 'dart:math' as math;

/// Access to existing user data is independent of subscription state.
enum ProFeature {
  readiness,
  personalizedPlan,
  smartRest,
  overload,
  adaptiveWalking,
  proteinSuggestions,
  longTermCharts,
  allMeasurements,
  advancedReview,
  adaptation,
  glpCoaching,
  advancedHealth,
  smartReminders,
  quietHours,
  reports,
  advancedPreferences,
}

abstract final class EntitlementPolicy {
  static bool allows(ProFeature feature, {required bool isPro}) => isPro;
  static int coachLimit(bool isPro) => isPro ? 100 : 3;
  static bool canAddReminder({required bool isPro, required int count}) =>
      isPro || count < 3;
  static bool canLogMeasurement(String type, bool isPro) =>
      type == 'waist' || isPro;
  static bool get canReadExistingData => true;
}

abstract final class ProgressMath {
  static double fraction(num current, num target) =>
      target <= 0 ? 0 : (current / target).clamp(0, 1).toDouble();
  static double estimatedOneRepMax(double kg, int reps) =>
      kg <= 0 || reps <= 0 ? 0 : kg * (1 + math.min(reps, 30) / 30);
  static double? weeklyLossPercent(List<Map<String, dynamic>> weights) {
    if (weights.length < 2) return null;
    final rows = [...weights]
      ..sort(
        (a, b) =>
            a['recorded_at'].toString().compareTo(b['recorded_at'].toString()),
      );
    final first = rows.first, last = rows.last;
    final days =
        DateTime.parse(
          last['recorded_at'],
        ).difference(DateTime.parse(first['recorded_at'])).inHours /
        24;
    final start = (first['weight_kg'] as num).toDouble();
    if (days < 7 || start <= 0) return null;
    return (start - (last['weight_kg'] as num)) / start * 100 * 7 / days;
  }

  static int consistency({required int completed, required int planned}) =>
      planned <= 0 ? 0 : (completed / planned * 100).round().clamp(0, 100);
  static int? readiness({
    required int observedDays,
    required double proteinRatio,
    required double stepsRatio,
    required double workoutRatio,
  }) => observedDays < 3
      ? null
      : ((proteinRatio.clamp(0, 1) * 35) +
                (stepsRatio.clamp(0, 1) * 25) +
                (workoutRatio.clamp(0, 1) * 40))
            .round();
  static bool rapidLossWithStrengthDecline({
    required double? weeklyLossPercent,
    required double? strengthChangePercent,
  }) =>
      weeklyLossPercent != null &&
      strengthChangePercent != null &&
      weeklyLossPercent > 1 &&
      strengthChangePercent < -5;
}

abstract final class InputRules {
  static String? email(String? value) =>
      value != null &&
          RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value.trim())
      ? null
      : 'Enter a valid email address.';
  static String? password(String? value) => value != null && value.length >= 12
      ? null
      : 'Use at least 12 characters.';
  static String? number(
    String? value, {
    required double min,
    required double max,
  }) {
    final n = double.tryParse(value ?? '');
    return n != null && n.isFinite && n >= min && n <= max
        ? null
        : 'Enter a number between $min and $max.';
  }
}

abstract final class CoachSafety {
  static String? localEscalation(String message) {
    if (RegExp(
      r'faint|passed out|chest pain|trouble breathing|severe weakness|dehydrat|cannot keep fluids|can.t keep fluids|severe pain',
      caseSensitive: false,
    ).hasMatch(message)) {
      return 'Stop exercising and seek medical care promptly. If symptoms are severe, sudden, or you feel in immediate danger, call local emergency services. LeanGuard cannot assess symptoms.';
    }
    if (RegExp(
      r'\bpain\b|\bdizzy\b|\bdizziness\b|vomit|palpitation|injury|persistent nausea|symptom|diagnos',
      caseSensitive: false,
    ).hasMatch(message)) {
      return 'Pause the activity and contact a qualified healthcare professional before continuing. I cannot diagnose pain or symptoms.';
    }
    if (RegExp(
      r'\b(dose|dosage|dosing|prescribe|prescription|titrate|titration)\b|(start|stop|skip|increase|decrease|change|switch|double|halve|adjust).{0,45}(ozempic|wegovy|mounjaro|zepbound|semaglutide|tirzepatide|medication|medicine|glp.?1)',
      caseSensitive: false,
    ).hasMatch(message)) {
      return 'Medication decisions belong with your prescribing clinician. I cannot advise starting, stopping, or changing a medication or dose. I can help you prepare questions for your clinician.';
    }
    return null;
  }
}
