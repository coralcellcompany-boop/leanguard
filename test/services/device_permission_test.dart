import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';
import 'package:leanguard/core/services/health_service.dart';

class DeniedHealth extends Health {
  @override
  Future<void> configure() async {}
  @override
  Future<bool> requestAuthorization(
    List<HealthDataType> types, {
    List<HealthDataAccess>? permissions,
  }) async => false;
}

class UndisclosedHealth extends DeniedHealth {
  @override
  Future<int?> getTotalStepsInInterval(
    DateTime startTime,
    DateTime endTime, {
    bool includeManualEntry = true,
  }) async => 0;
  @override
  Future<List<HealthDataPoint>> getHealthDataFromTypes({
    required List<HealthDataType> types,
    Map<HealthDataType, HealthDataUnit>? preferredUnits,
    required DateTime startTime,
    required DateTime endTime,
    List<RecordingMethod> recordingMethodsToFilter = const [],
  }) async => [];
  @override
  Future<bool> requestAuthorization(
    List<HealthDataType> types, {
    List<HealthDataAccess>? permissions,
  }) async => true;
}

class StepsOnlyHealth extends UndisclosedHealth {
  @override
  Future<bool> isHealthConnectAvailable() async => true;
  @override
  Future<bool?> hasPermissions(
    List<HealthDataType> types, {
    List<HealthDataAccess>? permissions,
  }) async => types.every((type) => type == HealthDataType.STEPS);
  @override
  Future<int?> getTotalStepsInInterval(
    DateTime startTime,
    DateTime endTime, {
    bool includeManualEntry = true,
  }) async => 1400;
  @override
  Future<List<HealthDataPoint>> getHealthDataFromTypes({
    required List<HealthDataType> types,
    Map<HealthDataType, HealthDataUnit>? preferredUnits,
    required DateTime startTime,
    required DateTime endTime,
    List<RecordingMethod> recordingMethodsToFilter = const [],
  }) async => throw StateError('Denied scopes must not be queried.');
}

class FailedRevocationHealth extends StepsOnlyHealth {
  @override
  Future<void> revokePermissions() async => throw StateError('OS unavailable');
}

class DeferredWriteHealth extends UndisclosedHealth {
  final permission = Completer<bool>();
  final started = Completer<void>();
  @override
  Future<bool> requestAuthorization(
    List<HealthDataType> types, {
    List<HealthDataAccess>? permissions,
  }) {
    started.complete();
    return permission.future;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() => debugDefaultTargetPlatformOverride = null);
  test(
    'Android partial permissions preserve allowed step import in Pro',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final service = HealthService(health: StepsOnlyHealth());
      final snapshot = await service.readToday(pro: true);
      expect(snapshot.steps, 1400);
      expect(snapshot.latestWeightKg, isNull);
      expect(snapshot.activeEnergyKcal, isNull);
      expect(snapshot.workouts, isEmpty);
      expect(snapshot.access, HealthAccess.authorized);
    },
  );
  test('declined health permission does not claim connection', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final service = HealthService(health: DeniedHealth());
    expect(await service.requestAccess(), HealthAccess.denied);
    final snapshot = await service.readToday();
    expect(snapshot.steps, isNull);
    expect(snapshot.latestWeightKg, isNull);
    expect(snapshot.access, HealthAccess.denied);
  });
  test(
    'HealthKit completed permission sheet does not assert read access',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final service = HealthService(health: UndisclosedHealth());
      expect(await service.requestAccess(), HealthAccess.readAccessUnknown);
      final snapshot = await service.readToday();
      expect(snapshot.access, HealthAccess.readAccessUnknown);
      expect(snapshot.steps, isNull);
    },
  );
  test('unsupported desktop health remains unavailable', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final service = HealthService(health: DeniedHealth());
    expect(await service.requestAccess(), HealthAccess.unavailable);
  });
  test(
    'health writes require Pro and separate explicit sharing permission',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final service = HealthService(health: UndisclosedHealth());
      await service.requestAccess(pro: true);
      expect(
        service.writeStrengthWorkout(
          pro: true,
          start: DateTime(2026),
          end: DateTime(2026, 1, 1, 1),
        ),
        throwsStateError,
      );
      expect(await service.requestWorkoutWriteAccess(pro: false), isFalse);
    },
  );
  test(
    'failed OS revocation still clears account-scoped workout consent',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final service = HealthService(health: FailedRevocationHealth());
      expect(await service.requestWorkoutWriteAccess(pro: true), isTrue);
      await expectLater(service.disconnect(), throwsStateError);
      expect(service.access, HealthAccess.notRequested);
      await expectLater(
        service.writeStrengthWorkout(
          pro: true,
          start: DateTime(2026),
          end: DateTime(2026, 1, 1, 1),
        ),
        throwsStateError,
      );
    },
  );
  test(
    'write permission callback after disconnect cannot authorize next account',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final native = DeferredWriteHealth();
      final service = HealthService(health: native);
      final permission = service.requestWorkoutWriteAccess(pro: true);
      await native.started.future;
      await service.disconnect();
      native.permission.complete(true);
      expect(await permission, isFalse);
      await expectLater(
        service.writeStrengthWorkout(
          pro: true,
          start: DateTime(2026),
          end: DateTime(2026, 1, 1, 1),
        ),
        throwsStateError,
      );
    },
  );
}
