import 'package:flutter/foundation.dart';
import 'package:health/health.dart';
import 'package:permission_handler/permission_handler.dart';

enum HealthAccess {
  unavailable,
  notRequested,
  denied,
  authorized,
  readAccessUnknown,
}

class HealthSnapshot {
  const HealthSnapshot({
    required this.date,
    required this.access,
    this.steps,
    this.latestWeightKg,
    this.weightExternalId,
    this.weightRecordedAt,
    this.activeEnergyKcal,
    this.workouts = const [],
  });
  final DateTime date;
  final HealthAccess access;
  final int? steps;
  final double? latestWeightKg;
  final String? weightExternalId;
  final DateTime? weightRecordedAt;
  final double? activeEnergyKcal;
  final List<HealthWorkoutSummary> workouts;
  bool get hasData => steps != null || latestWeightKg != null;
}

class HealthWorkoutSummary {
  const HealthWorkoutSummary({
    required this.externalId,
    required this.start,
    required this.end,
    required this.type,
  });
  final String externalId;
  final DateTime start;
  final DateTime end;
  final String type;
}

/// Minimal base scope: steps and weight. Pro workout writes require a separate
/// explicit permission and are never silently enabled. No medication data, routes,
/// heart-rate collection or background sampling is requested.
class HealthService {
  HealthService({Health? health}) : _health = health ?? Health();
  final Health _health;
  bool _initialized = false;
  HealthAccess _access = HealthAccess.notRequested;
  HealthAccess get access => _access;
  bool get supported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  bool get isAppleHealth => defaultTargetPlatform == TargetPlatform.iOS;
  static const _types = [HealthDataType.STEPS, HealthDataType.WEIGHT];
  List<HealthDataType> _readTypes(bool pro) => [
    ..._types,
    if (pro) ...[HealthDataType.ACTIVE_ENERGY_BURNED, HealthDataType.WORKOUT],
  ];
  List<HealthDataAccess> _permissions(bool pro) =>
      List.filled(_readTypes(pro).length, HealthDataAccess.READ);
  bool _workoutWriteConsent = false;
  int _sessionGeneration = 0;

  Future<HealthAccess> initialize() async {
    if (!supported) return _access = HealthAccess.unavailable;
    if (!_initialized) {
      await _health.configure();
      _initialized = true;
    }
    if (defaultTargetPlatform == TargetPlatform.android &&
        !await _health.isHealthConnectAvailable()) {
      return _access = HealthAccess.unavailable;
    }
    return _access;
  }

  Future<HealthAccess> requestAccess({bool pro = false}) async {
    if (await initialize() == HealthAccess.unavailable) return _access;
    if (defaultTargetPlatform == TargetPlatform.android) {
      await Permission.activityRecognition.request();
    }
    final accepted = await _health.requestAuthorization(
      _readTypes(pro),
      permissions: _permissions(pro),
    );
    // HealthKit intentionally conceals read-denial. Do not label the account
    // connected solely because the system permission sheet finished.
    if (isAppleHealth) {
      return _access = accepted
          ? HealthAccess.readAccessUnknown
          : HealthAccess.denied;
    }
    final permitted =
        await _canRead(HealthDataType.STEPS) ||
        await _canRead(HealthDataType.WEIGHT);
    return _access = permitted ? HealthAccess.authorized : HealthAccess.denied;
  }

  Future<bool> _canRead(HealthDataType type) async =>
      isAppleHealth ||
      (await _health.hasPermissions(
            [type],
            permissions: [HealthDataAccess.READ],
          ) ??
          false);

  Future<HealthSnapshot> readToday({DateTime? now, bool pro = false}) async {
    final end = now ?? DateTime.now();
    final start = DateTime(end.year, end.month, end.day);
    if (await initialize() == HealthAccess.unavailable) {
      return HealthSnapshot(date: start, access: _access);
    }
    final stepsAllowed = await _canRead(HealthDataType.STEPS);
    final weightAllowed = await _canRead(HealthDataType.WEIGHT);
    if (!stepsAllowed && !weightAllowed) {
      return HealthSnapshot(date: start, access: _access = HealthAccess.denied);
    }
    if (_access == HealthAccess.denied && isAppleHealth) {
      return HealthSnapshot(date: start, access: _access);
    }
    final steps = stepsAllowed
        ? await _health.getTotalStepsInInterval(start, end)
        : null;
    final weights = weightAllowed
        ? await _health.getHealthDataFromTypes(
            types: [HealthDataType.WEIGHT],
            startTime: end.subtract(const Duration(days: 30)),
            endTime: end,
          )
        : <HealthDataPoint>[];
    weights.sort((a, b) => b.dateTo.compareTo(a.dateTo));
    final value = weights.isEmpty ? null : weights.first.value;
    final weight = value is NumericHealthValue
        ? value.numericValue.toDouble()
        : null;
    _access = isAppleHealth && (steps == null || steps == 0) && weight == null
        ? HealthAccess.readAccessUnknown
        : HealthAccess.authorized;
    double? energy;
    final workouts = <HealthWorkoutSummary>[];
    if (pro) {
      final proTypes = <HealthDataType>[];
      for (final type in [
        HealthDataType.ACTIVE_ENERGY_BURNED,
        HealthDataType.WORKOUT,
      ]) {
        if (await _canRead(type)) proTypes.add(type);
      }
      final records = _health.removeDuplicates(
        proTypes.isEmpty
            ? <HealthDataPoint>[]
            : await _health.getHealthDataFromTypes(
                types: proTypes,
                startTime: start,
                endTime: end,
              ),
      );
      for (final record in records) {
        if (record.type == HealthDataType.ACTIVE_ENERGY_BURNED &&
            record.value is NumericHealthValue) {
          energy =
              (energy ?? 0) +
              (record.value as NumericHealthValue).numericValue.toDouble();
        } else if (record.type == HealthDataType.WORKOUT) {
          workouts.add(
            HealthWorkoutSummary(
              externalId: record.uuid,
              start: record.dateFrom,
              end: record.dateTo,
              type: record.workoutSummary?.workoutType ?? 'workout',
            ),
          );
        }
      }
    }
    return HealthSnapshot(
      date: start,
      access: _access,
      steps: isAppleHealth && (steps == null || steps == 0) ? null : steps,
      latestWeightKg: weight,
      weightExternalId: weights.isEmpty ? null : weights.first.uuid,
      weightRecordedAt: weights.isEmpty ? null : weights.first.dateTo,
      activeEnergyKcal: energy,
      workouts: workouts,
    );
  }

  Future<bool> requestWorkoutWriteAccess({required bool pro}) async {
    final generation = _sessionGeneration;
    if (!pro ||
        await initialize() == HealthAccess.unavailable ||
        generation != _sessionGeneration) {
      return false;
    }
    final allowed = await _health.requestAuthorization(
      [HealthDataType.WORKOUT],
      permissions: [HealthDataAccess.READ_WRITE],
    );
    if (generation != _sessionGeneration) return false;
    return _workoutWriteConsent = allowed;
  }

  /// Caller keeps a persisted exported-at marker per workout to avoid duplicates.
  Future<bool> writeStrengthWorkout({
    required bool pro,
    required DateTime start,
    required DateTime end,
  }) async {
    if (!pro || !_workoutWriteConsent) {
      throw StateError('Enable workout sharing first.');
    }
    if (!end.isAfter(start)) {
      throw const FormatException('Workout end must follow its start.');
    }
    return _health.writeWorkoutData(
      activityType: HealthWorkoutActivityType.FUNCTIONAL_STRENGTH_TRAINING,
      start: start,
      end: end,
      title: 'LeanGuard strength workout',
      recordingMethod: RecordingMethod.manual,
    );
  }

  Future<void> installHealthConnect() async {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await _health.installHealthConnect();
    }
  }

  Future<void> disconnect() async {
    // iOS permissions can only be revoked in the Apple Health app. Callers
    // persist a disconnected preference and cease reads immediately.
    ++_sessionGeneration;
    _access = HealthAccess.notRequested;
    _workoutWriteConsent = false;
    if (_initialized && !isAppleHealth) await _health.revokePermissions();
  }

  Future<bool> openSettings() => openAppSettings();
}
