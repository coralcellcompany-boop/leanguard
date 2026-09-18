/// Immutable schema-aligned domain entities. All stored weight/load is kilograms,
/// measurements are centimeters, and instants serialize in UTC.
abstract class OwnedEntity {
  const OwnedEntity({
    required this.id,
    required this.userId,
    required this.createdAt,
  });
  final String id;
  final String userId;
  final DateTime createdAt;
  String get table;
  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'created_at': createdAt.toUtc().toIso8601String(),
  };
  static OwnedEntity fromTable(String table, Map<String, dynamic> json) =>
      switch (table) {
        'user_profiles' => UserProfile.fromJson(json),
        'goal_profiles' => GoalProfile.fromJson(json),
        'health_connections' => HealthConnection.fromJson(json),
        'medication_support_preferences' =>
          MedicationSupportPreferences.fromJson(json),
        'strength_plans' => StrengthPlan.fromJson(json),
        'workouts' => Workout.fromJson(json),
        'exercises' => Exercise.fromJson(json),
        'workout_exercises' => WorkoutExercise.fromJson(json),
        'workout_sets' => WorkoutSet.fromJson(json),
        'daily_targets' => DailyTarget.fromJson(json),
        'daily_activities' => DailyActivity.fromJson(json),
        'protein_entries' => ProteinEntry.fromJson(json),
        'weight_entries' => WeightEntry.fromJson(json),
        'body_measurements' => BodyMeasurement.fromJson(json),
        'weekly_insights' => WeeklyInsight.fromJson(json),
        'coach_conversations' => CoachConversation.fromJson(json),
        'coach_messages' => CoachMessage.fromJson(json),
        'reminder_preferences' => ReminderPreference.fromJson(json),
        'subscription_entitlements' => SubscriptionEntitlement.fromJson(json),
        'consent_records' => ConsentRecord.fromJson(json),
        _ => throw ArgumentError.value(table, 'table', 'Unknown entity table'),
      };
}

String _string(Map<String, dynamic> json, String key, [String? fallback]) {
  final value = json[key];
  if (value == null && fallback != null) return fallback;
  if (value is! String) throw FormatException('$key must be text');
  return value;
}

double _number(Map<String, dynamic> json, String key, [double? fallback]) {
  final value = json[key];
  if (value == null && fallback != null) return fallback;
  final result = value is num
      ? value.toDouble()
      : double.tryParse(value?.toString() ?? '');
  if (result == null || !result.isFinite) {
    throw FormatException('$key must be a finite number');
  }
  return result;
}

int _integer(Map<String, dynamic> json, String key, [int? fallback]) {
  final value = _number(json, key, fallback?.toDouble());
  if (value != value.roundToDouble()) {
    throw FormatException('$key must be an integer');
  }
  return value.toInt();
}

bool _boolean(Map<String, dynamic> json, String key, [bool? fallback]) {
  final value = json[key];
  if (value == null && fallback != null) return fallback;
  if (value is! bool) throw FormatException('$key must be a boolean');
  return value;
}

DateTime _date(Map<String, dynamic> json, String key) {
  final raw = _string(json, key);
  final value = DateTime.tryParse(
    RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw) ? '${raw}T00:00:00Z' : raw,
  );
  if (value == null) throw FormatException('$key must be an ISO date');
  return value.toUtc();
}

List<String> _strings(Map<String, dynamic> json, String key) =>
    List<String>.unmodifiable((json[key] as List? ?? const []).cast<String>());
List<int> _ints(Map<String, dynamic> json, String key, List<int> fallback) =>
    List<int>.unmodifiable((json[key] as List? ?? fallback).cast<int>());
Map<String, dynamic> _object(Map<String, dynamic> json, String key) =>
    Map<String, dynamic>.unmodifiable(
      Map<String, dynamic>.from(json[key] as Map),
    );

class UserProfile extends OwnedEntity {
  UserProfile({
    required super.id,
    required super.userId,
    required super.createdAt,
    this.displayName = '',
    this.units = 'metric',
    this.timeZone = 'UTC',
    this.onboardingCompleted = false,
    this.analyticsEnabled = false,
    this.crashReportingEnabled = false,
    this.coachingTone = 'supportive',
    this.avatarPath,
    this.updatedAt,
  });
  final String displayName;
  final String units;
  final String timeZone;
  final bool onboardingCompleted;
  final bool analyticsEnabled;
  final bool crashReportingEnabled;
  final String coachingTone;
  final String? avatarPath;
  final DateTime? updatedAt;
  @override
  String get table => 'user_profiles';
  factory UserProfile.fromJson(Map<String, dynamic> json) => UserProfile(
    id: _string(json, 'id'),
    userId: _string(json, 'user_id'),
    createdAt: _date(json, 'created_at'),
    displayName: _string(json, 'display_name', ''),
    units: _string(json, 'units', 'metric'),
    timeZone: _string(json, 'time_zone', 'UTC'),
    onboardingCompleted: _boolean(json, 'onboarding_completed', false),
    analyticsEnabled: _boolean(json, 'analytics_enabled', false),
    crashReportingEnabled: _boolean(json, 'crash_reporting_enabled', false),
    coachingTone: _string(json, 'coaching_tone', 'supportive'),
    avatarPath: json['avatar_path'] == null
        ? null
        : _string(json, 'avatar_path'),
    updatedAt: json['updated_at'] == null ? null : _date(json, 'updated_at'),
  );
  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'display_name': displayName,
    'units': units,
    'time_zone': timeZone,
    'onboarding_completed': onboardingCompleted,
    'analytics_enabled': analyticsEnabled,
    'crash_reporting_enabled': crashReportingEnabled,
    'coaching_tone': coachingTone,
    'avatar_path': avatarPath,
    if (updatedAt != null) 'updated_at': updatedAt!.toUtc().toIso8601String(),
  };
}

class GoalProfile extends OwnedEntity {
  GoalProfile({
    required super.id,
    required super.userId,
    required super.createdAt,
    this.goal = 'lose_weight',
    List<String> goals = const [],
    this.targetWeightKg,
    this.workoutsPerWeek = 3,
    this.proteinTargetG = 120,
    this.stepTarget = 7000,
    List<String> equipment = const [],
    List<String> dietaryPreferences = const [],
    List<String> allergies = const [],
    List<String> limitations = const [],
    List<String> exercisePreferences = const [],
    List<int> trainingDays = const [1, 3, 5],
    this.sessionMinutes = 35,
    this.updatedAt,
  }) : goals = List.unmodifiable(goals),
       equipment = List.unmodifiable(equipment),
       dietaryPreferences = List.unmodifiable(dietaryPreferences),
       allergies = List.unmodifiable(allergies),
       limitations = List.unmodifiable(limitations),
       exercisePreferences = List.unmodifiable(exercisePreferences),
       trainingDays = List.unmodifiable(trainingDays);
  final String goal;
  final List<String> goals;
  final double? targetWeightKg;
  final int workoutsPerWeek;
  final int proteinTargetG;
  final int stepTarget;
  final List<String> equipment;
  final List<String> dietaryPreferences;
  final List<String> allergies;
  final List<String> limitations;
  final List<String> exercisePreferences;
  final List<int> trainingDays;
  final int sessionMinutes;
  final DateTime? updatedAt;
  @override
  String get table => 'goal_profiles';
  factory GoalProfile.fromJson(Map<String, dynamic> json) => GoalProfile(
    id: _string(json, 'id'),
    userId: _string(json, 'user_id'),
    createdAt: _date(json, 'created_at'),
    goal: _string(json, 'goal', 'lose_weight'),
    goals: _strings(json, 'goals'),
    targetWeightKg: json['target_weight_kg'] == null
        ? null
        : _number(json, 'target_weight_kg'),
    workoutsPerWeek: _integer(json, 'workouts_per_week', 3),
    proteinTargetG: _integer(json, 'protein_target_g', 120),
    stepTarget: _integer(json, 'step_target', 7000),
    equipment: _strings(json, 'equipment'),
    dietaryPreferences: _strings(json, 'dietary_preferences'),
    allergies: _strings(json, 'allergies'),
    limitations: _strings(json, 'limitations'),
    exercisePreferences: _strings(json, 'exercise_preferences'),
    trainingDays: _ints(json, 'training_days', const [1, 3, 5]),
    sessionMinutes: _integer(json, 'session_minutes', 35),
    updatedAt: json['updated_at'] == null ? null : _date(json, 'updated_at'),
  );
  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'goal': goal,
    'goals': goals,
    'target_weight_kg': targetWeightKg,
    'workouts_per_week': workoutsPerWeek,
    'protein_target_g': proteinTargetG,
    'step_target': stepTarget,
    'equipment': equipment,
    'dietary_preferences': dietaryPreferences,
    'allergies': allergies,
    'limitations': limitations,
    'exercise_preferences': exercisePreferences,
    'training_days': trainingDays,
    'session_minutes': sessionMinutes,
    if (updatedAt != null) 'updated_at': updatedAt!.toUtc().toIso8601String(),
  };
}

class HealthConnection extends OwnedEntity {
  HealthConnection({
    required super.id,
    required super.userId,
    required super.createdAt,
    required this.provider,
    this.status = 'disconnected',
    List<String> permissions = const [],
    this.lastSyncedAt,
  }) : permissions = List.unmodifiable(permissions);
  final String provider;
  final String status;
  final List<String> permissions;
  final DateTime? lastSyncedAt;
  @override
  String get table => 'health_connections';
  factory HealthConnection.fromJson(Map<String, dynamic> json) =>
      HealthConnection(
        id: _string(json, 'id'),
        userId: _string(json, 'user_id'),
        createdAt: _date(json, 'created_at'),
        provider: _string(json, 'provider'),
        status: _string(json, 'status', 'disconnected'),
        permissions: _strings(json, 'permissions'),
        lastSyncedAt: json['last_synced_at'] == null
            ? null
            : _date(json, 'last_synced_at'),
      );
  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'provider': provider,
    'status': status,
    'permissions': permissions,
    'last_synced_at': lastSyncedAt?.toUtc().toIso8601String(),
  };
}

class MedicationSupportPreferences extends OwnedEntity {
  MedicationSupportPreferences({
    required super.id,
    required super.userId,
    required super.createdAt,
    this.enabled = false,
    this.clinicianSupervised = false,
    this.appetiteLevel = 'normal',
    this.hydrationReminders = false,
    this.checkInsEnabled = false,
  });
  final bool enabled;
  final bool clinicianSupervised;
  final String appetiteLevel;
  final bool hydrationReminders;
  final bool checkInsEnabled;
  @override
  String get table => 'medication_support_preferences';
  factory MedicationSupportPreferences.fromJson(Map<String, dynamic> json) =>
      MedicationSupportPreferences(
        id: _string(json, 'id'),
        userId: _string(json, 'user_id'),
        createdAt: _date(json, 'created_at'),
        enabled: _boolean(json, 'enabled', false),
        clinicianSupervised: _boolean(json, 'clinician_supervised', false),
        appetiteLevel: _string(json, 'appetite_level', 'normal'),
        hydrationReminders: _boolean(json, 'hydration_reminders', false),
        checkInsEnabled: _boolean(json, 'check_ins_enabled', false),
      );
  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'enabled': enabled,
    'clinician_supervised': clinicianSupervised,
    'appetite_level': appetiteLevel,
    'hydration_reminders': hydrationReminders,
    'check_ins_enabled': checkInsEnabled,
  };
}

class StrengthPlan extends OwnedEntity {
  StrengthPlan({
    required super.id,
    required super.userId,
    required super.createdAt,
    required this.name,
    this.description = '',
    this.isActive = true,
    this.version = 1,
    this.source = 'starter',
    List<Map<String, dynamic>> schedule = const [],
    this.updatedAt,
  }) : schedule = List.unmodifiable(schedule);
  final String name;
  final String description;
  final bool isActive;
  final int version;
  final String source;
  final List<Map<String, dynamic>> schedule;
  final DateTime? updatedAt;
  @override
  String get table => 'strength_plans';
  factory StrengthPlan.fromJson(Map<String, dynamic> json) => StrengthPlan(
    id: _string(json, 'id'),
    userId: _string(json, 'user_id'),
    createdAt: _date(json, 'created_at'),
    name: _string(json, 'name'),
    description: _string(json, 'description', ''),
    isActive: _boolean(json, 'is_active', true),
    version: _integer(json, 'version', 1),
    source: _string(json, 'source', 'starter'),
    schedule: (json['schedule'] as List? ?? const [])
        .map((row) => Map<String, dynamic>.from(row as Map))
        .toList(),
    updatedAt: json['updated_at'] == null ? null : _date(json, 'updated_at'),
  );
  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'name': name,
    'description': description,
    'is_active': isActive,
    'version': version,
    'source': source,
    'schedule': schedule,
    if (updatedAt != null) 'updated_at': updatedAt!.toUtc().toIso8601String(),
  };
}

class Workout extends OwnedEntity {
  Workout({
    required super.id,
    required super.userId,
    required super.createdAt,
    required this.name,
    this.planId,
    this.status = 'planned',
    this.scheduledDate,
    this.startedAt,
    this.completedAt,
    this.durationSeconds = 0,
    this.notes = '',
  });
  final String name;
  final String? planId;
  final String status;
  final DateTime? scheduledDate;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final int durationSeconds;
  final String notes;
  @override
  String get table => 'workouts';
  factory Workout.fromJson(Map<String, dynamic> json) => Workout(
    id: _string(json, 'id'),
    userId: _string(json, 'user_id'),
    createdAt: _date(json, 'created_at'),
    name: _string(json, 'name'),
    planId: json['plan_id'] == null ? null : _string(json, 'plan_id'),
    status: _string(json, 'status', 'planned'),
    scheduledDate: json['scheduled_date'] == null
        ? null
        : _date(json, 'scheduled_date'),
    startedAt: json['started_at'] == null ? null : _date(json, 'started_at'),
    completedAt: json['completed_at'] == null
        ? null
        : _date(json, 'completed_at'),
    durationSeconds: _integer(json, 'duration_seconds', 0),
    notes: _string(json, 'notes', ''),
  );
  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'name': name,
    'plan_id': planId,
    'status': status,
    'scheduled_date': scheduledDate?.toUtc().toIso8601String().substring(0, 10),
    'started_at': startedAt?.toUtc().toIso8601String(),
    'completed_at': completedAt?.toUtc().toIso8601String(),
    'duration_seconds': durationSeconds,
    'notes': notes,
  };
}

class Exercise extends OwnedEntity {
  Exercise({
    required super.id,
    required super.userId,
    required super.createdAt,
    required this.name,
    this.muscleGroup = 'full_body',
    this.equipment = 'bodyweight',
    List<String> instructions = const [],
    this.imageUrl,
  }) : instructions = List.unmodifiable(instructions);
  final String name;
  final String muscleGroup;
  final String equipment;
  final List<String> instructions;
  final String? imageUrl;
  @override
  String get table => 'exercises';
  factory Exercise.fromJson(Map<String, dynamic> json) => Exercise(
    id: _string(json, 'id'),
    userId: _string(json, 'user_id'),
    createdAt: _date(json, 'created_at'),
    name: _string(json, 'name'),
    muscleGroup: _string(json, 'muscle_group', 'full_body'),
    equipment: _string(json, 'equipment', 'bodyweight'),
    instructions: _strings(json, 'instructions'),
    imageUrl: json['image_url'] == null ? null : _string(json, 'image_url'),
  );
  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'name': name,
    'muscle_group': muscleGroup,
    'equipment': equipment,
    'instructions': instructions,
    'image_url': imageUrl,
  };
}

class WorkoutExercise extends OwnedEntity {
  WorkoutExercise({
    required super.id,
    required super.userId,
    required super.createdAt,
    required this.workoutId,
    required this.exerciseId,
    this.position = 0,
    this.targetSets = 3,
    this.targetReps = 10,
    this.targetWeightKg = 0,
    this.restSeconds = 90,
    this.status = 'planned',
  });
  final String workoutId;
  final String exerciseId;
  final int position;
  final int targetSets;
  final int targetReps;
  final double targetWeightKg;
  final int restSeconds;
  final String status;
  @override
  String get table => 'workout_exercises';
  factory WorkoutExercise.fromJson(Map<String, dynamic> json) =>
      WorkoutExercise(
        id: _string(json, 'id'),
        userId: _string(json, 'user_id'),
        createdAt: _date(json, 'created_at'),
        workoutId: _string(json, 'workout_id'),
        exerciseId: _string(json, 'exercise_id'),
        position: _integer(json, 'position', 0),
        targetSets: _integer(json, 'target_sets', 3),
        targetReps: _integer(json, 'target_reps', 10),
        targetWeightKg: _number(json, 'target_weight_kg', 0),
        restSeconds: _integer(json, 'rest_seconds', 90),
        status: _string(json, 'status', 'planned'),
      );
  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'workout_id': workoutId,
    'exercise_id': exerciseId,
    'position': position,
    'target_sets': targetSets,
    'target_reps': targetReps,
    'target_weight_kg': targetWeightKg,
    'rest_seconds': restSeconds,
    'status': status,
  };
}

class WorkoutSet extends OwnedEntity {
  WorkoutSet({
    required super.id,
    required super.userId,
    required super.createdAt,
    required this.workoutExerciseId,
    required this.setNumber,
    required this.reps,
    this.weightKg = 0,
    this.completed = true,
    this.completedAt,
    this.rpe,
  });
  final String workoutExerciseId;
  final int setNumber;
  final int reps;
  final double weightKg;
  final bool completed;
  final DateTime? completedAt;
  final double? rpe;
  @override
  String get table => 'workout_sets';
  factory WorkoutSet.fromJson(Map<String, dynamic> json) => WorkoutSet(
    id: _string(json, 'id'),
    userId: _string(json, 'user_id'),
    createdAt: _date(json, 'created_at'),
    workoutExerciseId: _string(json, 'workout_exercise_id'),
    setNumber: _integer(json, 'set_number'),
    reps: _integer(json, 'reps'),
    weightKg: _number(json, 'weight_kg', 0),
    completed: _boolean(json, 'completed', true),
    completedAt: json['completed_at'] == null
        ? null
        : _date(json, 'completed_at'),
    rpe: json['rpe'] == null ? null : _number(json, 'rpe'),
  );
  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'workout_exercise_id': workoutExerciseId,
    'set_number': setNumber,
    'reps': reps,
    'weight_kg': weightKg,
    'completed': completed,
    'completed_at': completedAt?.toUtc().toIso8601String(),
    'rpe': rpe,
  };
}

class DailyTarget extends OwnedEntity {
  DailyTarget({
    required super.id,
    required super.userId,
    required super.createdAt,
    required this.date,
    this.steps = 7000,
    this.proteinG = 120,
  });
  final DateTime date;
  final int steps;
  final int proteinG;
  @override
  String get table => 'daily_targets';
  factory DailyTarget.fromJson(Map<String, dynamic> json) => DailyTarget(
    id: _string(json, 'id'),
    userId: _string(json, 'user_id'),
    createdAt: _date(json, 'created_at'),
    date: _date(json, 'date'),
    steps: _integer(json, 'steps', 7000),
    proteinG: _integer(json, 'protein_g', 120),
  );
  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'date': date.toUtc().toIso8601String().substring(0, 10),
    'steps': steps,
    'protein_g': proteinG,
  };
}

class DailyActivity extends OwnedEntity {
  DailyActivity({
    required super.id,
    required super.userId,
    required super.createdAt,
    required this.date,
    this.steps = 0,
    this.activeEnergyKcal = 0,
    this.readinessScore,
    this.energyLevel,
    this.source = 'manual',
  });
  final DateTime date;
  final int steps;
  final double activeEnergyKcal;
  final int? readinessScore;
  final int? energyLevel;
  final String source;
  @override
  String get table => 'daily_activities';
  factory DailyActivity.fromJson(Map<String, dynamic> json) => DailyActivity(
    id: _string(json, 'id'),
    userId: _string(json, 'user_id'),
    createdAt: _date(json, 'created_at'),
    date: _date(json, 'date'),
    steps: _integer(json, 'steps', 0),
    activeEnergyKcal: _number(json, 'active_energy_kcal', 0),
    readinessScore: json['readiness_score'] == null
        ? null
        : _integer(json, 'readiness_score'),
    energyLevel: json['energy_level'] == null
        ? null
        : _integer(json, 'energy_level'),
    source: _string(json, 'source', 'manual'),
  );
  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'date': date.toUtc().toIso8601String().substring(0, 10),
    'steps': steps,
    'active_energy_kcal': activeEnergyKcal,
    'readiness_score': readinessScore,
    'energy_level': energyLevel,
    'source': source,
  };
}

class ProteinEntry extends OwnedEntity {
  ProteinEntry({
    required super.id,
    required super.userId,
    required super.createdAt,
    required this.name,
    required this.proteinG,
    this.mealType = 'snack',
    required this.recordedAt,
  });
  final String name;
  final double proteinG;
  final String mealType;
  final DateTime recordedAt;
  @override
  String get table => 'protein_entries';
  factory ProteinEntry.fromJson(Map<String, dynamic> json) => ProteinEntry(
    id: _string(json, 'id'),
    userId: _string(json, 'user_id'),
    createdAt: _date(json, 'created_at'),
    name: _string(json, 'name'),
    proteinG: _number(json, 'protein_g'),
    mealType: _string(json, 'meal_type', 'snack'),
    recordedAt: _date(json, 'recorded_at'),
  );
  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'name': name,
    'protein_g': proteinG,
    'meal_type': mealType,
    'recorded_at': recordedAt.toUtc().toIso8601String(),
  };
}

class WeightEntry extends OwnedEntity {
  WeightEntry({
    required super.id,
    required super.userId,
    required super.createdAt,
    required this.weightKg,
    required this.recordedAt,
    this.source = 'manual',
    this.externalId,
  });
  final double weightKg;
  final DateTime recordedAt;
  final String source;
  final String? externalId;
  @override
  String get table => 'weight_entries';
  factory WeightEntry.fromJson(Map<String, dynamic> json) => WeightEntry(
    id: _string(json, 'id'),
    userId: _string(json, 'user_id'),
    createdAt: _date(json, 'created_at'),
    weightKg: _number(json, 'weight_kg'),
    recordedAt: _date(json, 'recorded_at'),
    source: _string(json, 'source', 'manual'),
    externalId: json['external_id'] == null
        ? null
        : _string(json, 'external_id'),
  );
  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'weight_kg': weightKg,
    'recorded_at': recordedAt.toUtc().toIso8601String(),
    'source': source,
    'external_id': externalId,
  };
}

class BodyMeasurement extends OwnedEntity {
  BodyMeasurement({
    required super.id,
    required super.userId,
    required super.createdAt,
    required this.recordedAt,
    this.waistCm,
    this.chestCm,
    this.hipsCm,
    this.armCm,
    this.thighCm,
  });
  final DateTime recordedAt;
  final double? waistCm;
  final double? chestCm;
  final double? hipsCm;
  final double? armCm;
  final double? thighCm;
  @override
  String get table => 'body_measurements';
  factory BodyMeasurement.fromJson(Map<String, dynamic> json) =>
      BodyMeasurement(
        id: _string(json, 'id'),
        userId: _string(json, 'user_id'),
        createdAt: _date(json, 'created_at'),
        recordedAt: _date(json, 'recorded_at'),
        waistCm: json['waist_cm'] == null ? null : _number(json, 'waist_cm'),
        chestCm: json['chest_cm'] == null ? null : _number(json, 'chest_cm'),
        hipsCm: json['hips_cm'] == null ? null : _number(json, 'hips_cm'),
        armCm: json['arm_cm'] == null ? null : _number(json, 'arm_cm'),
        thighCm: json['thigh_cm'] == null ? null : _number(json, 'thigh_cm'),
      );
  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'recorded_at': recordedAt.toUtc().toIso8601String(),
    'waist_cm': waistCm,
    'chest_cm': chestCm,
    'hips_cm': hipsCm,
    'arm_cm': armCm,
    'thigh_cm': thighCm,
  };
}

class WeeklyInsight extends OwnedEntity {
  WeeklyInsight({
    required super.id,
    required super.userId,
    required super.createdAt,
    required this.weekStart,
    required this.snapshotHash,
    required this.promptVersion,
    required Map<String, dynamic> content,
  }) : content = Map<String, dynamic>.unmodifiable(content);
  final DateTime weekStart;
  final String snapshotHash;
  final String promptVersion;
  final Map<String, dynamic> content;
  @override
  String get table => 'weekly_insights';
  factory WeeklyInsight.fromJson(Map<String, dynamic> json) => WeeklyInsight(
    id: _string(json, 'id'),
    userId: _string(json, 'user_id'),
    createdAt: _date(json, 'created_at'),
    weekStart: _date(json, 'week_start'),
    snapshotHash: _string(json, 'snapshot_hash'),
    promptVersion: _string(json, 'prompt_version'),
    content: _object(json, 'content'),
  );
  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'week_start': weekStart.toUtc().toIso8601String().substring(0, 10),
    'snapshot_hash': snapshotHash,
    'prompt_version': promptVersion,
    'content': content,
  };
}

class CoachConversation extends OwnedEntity {
  CoachConversation({
    required super.id,
    required super.userId,
    required super.createdAt,
    this.title = 'Lean Coach',
  });
  final String title;
  @override
  String get table => 'coach_conversations';
  factory CoachConversation.fromJson(Map<String, dynamic> json) =>
      CoachConversation(
        id: _string(json, 'id'),
        userId: _string(json, 'user_id'),
        createdAt: _date(json, 'created_at'),
        title: _string(json, 'title', 'Lean Coach'),
      );
  @override
  Map<String, dynamic> toJson() => {...super.toJson(), 'title': title};
}

class CoachMessage extends OwnedEntity {
  CoachMessage({
    required super.id,
    required super.userId,
    required super.createdAt,
    required this.conversationId,
    required this.role,
    required this.content,
    Map<String, dynamic>? structuredContent,
    this.safetyClassification,
    this.promptVersion,
  }) : structuredContent = structuredContent == null
           ? null
           : Map<String, dynamic>.unmodifiable(structuredContent);
  final String conversationId;
  final String role;
  final String content;
  final Map<String, dynamic>? structuredContent;
  final String? safetyClassification;
  final String? promptVersion;
  @override
  String get table => 'coach_messages';
  factory CoachMessage.fromJson(Map<String, dynamic> json) => CoachMessage(
    id: _string(json, 'id'),
    userId: _string(json, 'user_id'),
    createdAt: _date(json, 'created_at'),
    conversationId: _string(json, 'conversation_id'),
    role: _string(json, 'role'),
    content: _string(json, 'content'),
    structuredContent: json['structured_content'] == null
        ? null
        : _object(json, 'structured_content'),
    safetyClassification: json['safety_classification'] == null
        ? null
        : _string(json, 'safety_classification'),
    promptVersion: json['prompt_version'] == null
        ? null
        : _string(json, 'prompt_version'),
  );
  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'conversation_id': conversationId,
    'role': role,
    'content': content,
    'structured_content': structuredContent,
    'safety_classification': safetyClassification,
    'prompt_version': promptVersion,
  };
}

class ReminderPreference extends OwnedEntity {
  ReminderPreference({
    required super.id,
    required super.userId,
    required super.createdAt,
    required this.kind,
    required this.title,
    this.timeOfDay = '09:00:00',
    List<int> daysOfWeek = const [1, 2, 3, 4, 5, 6, 7],
    this.enabled = true,
    this.smart = false,
    this.quietStart,
    this.quietEnd,
    this.timeZone = 'UTC',
    this.delivery = 'local',
  }) : daysOfWeek = List.unmodifiable(daysOfWeek);
  final String kind;
  final String title;
  final String timeOfDay;
  final List<int> daysOfWeek;
  final bool enabled;
  final bool smart;
  final String? quietStart;
  final String? quietEnd;
  final String timeZone;
  final String delivery;
  @override
  String get table => 'reminder_preferences';
  factory ReminderPreference.fromJson(Map<String, dynamic> json) =>
      ReminderPreference(
        id: _string(json, 'id'),
        userId: _string(json, 'user_id'),
        createdAt: _date(json, 'created_at'),
        kind: _string(json, 'kind'),
        title: _string(json, 'title'),
        timeOfDay: _string(json, 'time_of_day', '09:00:00'),
        daysOfWeek: _ints(json, 'days_of_week', const [1, 2, 3, 4, 5, 6, 7]),
        enabled: _boolean(json, 'enabled', true),
        smart: _boolean(json, 'smart', false),
        quietStart: json['quiet_start'] == null
            ? null
            : _string(json, 'quiet_start'),
        quietEnd: json['quiet_end'] == null ? null : _string(json, 'quiet_end'),
        timeZone: _string(json, 'time_zone', 'UTC'),
        delivery: _string(json, 'delivery', 'local'),
      );
  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'kind': kind,
    'title': title,
    'time_of_day': timeOfDay,
    'days_of_week': daysOfWeek,
    'enabled': enabled,
    'smart': smart,
    'quiet_start': quietStart,
    'quiet_end': quietEnd,
    'time_zone': timeZone,
    'delivery': delivery,
  };
}

class SubscriptionEntitlement extends OwnedEntity {
  SubscriptionEntitlement({
    required super.id,
    required super.userId,
    required super.createdAt,
    this.entitlementId = 'pro',
    this.isActive = false,
    this.productId,
    this.expiresAt,
    this.gracePeriodExpiresAt,
    this.status = 'expired',
    this.willRenew = false,
    this.managementUrl,
    this.isSandbox = false,
    required this.verifiedAt,
  });
  final String entitlementId;
  final bool isActive;
  final String? productId;
  final DateTime? expiresAt;
  final DateTime? gracePeriodExpiresAt;
  final String status;
  final bool willRenew;
  final String? managementUrl;
  final bool isSandbox;
  final DateTime verifiedAt;
  @override
  String get table => 'subscription_entitlements';
  factory SubscriptionEntitlement.fromJson(
    Map<String, dynamic> json,
  ) => SubscriptionEntitlement(
    id: _string(json, 'id'),
    userId: _string(json, 'user_id'),
    createdAt: _date(json, 'created_at'),
    entitlementId: _string(json, 'entitlement_id', 'pro'),
    isActive: _boolean(json, 'is_active', false),
    productId: json['product_id'] == null ? null : _string(json, 'product_id'),
    expiresAt: json['expires_at'] == null ? null : _date(json, 'expires_at'),
    gracePeriodExpiresAt: json['grace_period_expires_at'] == null
        ? null
        : _date(json, 'grace_period_expires_at'),
    status: _string(json, 'status', 'expired'),
    willRenew: _boolean(json, 'will_renew', false),
    managementUrl: json['management_url'] == null
        ? null
        : _string(json, 'management_url'),
    isSandbox: _boolean(json, 'is_sandbox', false),
    verifiedAt: _date(json, 'verified_at'),
  );
  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'entitlement_id': entitlementId,
    'is_active': isActive,
    'product_id': productId,
    'expires_at': expiresAt?.toUtc().toIso8601String(),
    'grace_period_expires_at': gracePeriodExpiresAt?.toUtc().toIso8601String(),
    'status': status,
    'will_renew': willRenew,
    'management_url': managementUrl,
    'is_sandbox': isSandbox,
    'verified_at': verifiedAt.toUtc().toIso8601String(),
  };
}

class ConsentRecord extends OwnedEntity {
  ConsentRecord({
    required super.id,
    required super.userId,
    required super.createdAt,
    required this.kind,
    required this.granted,
    required this.policyVersion,
  });
  final String kind;
  final bool granted;
  final String policyVersion;
  @override
  String get table => 'consent_records';
  factory ConsentRecord.fromJson(Map<String, dynamic> json) => ConsentRecord(
    id: _string(json, 'id'),
    userId: _string(json, 'user_id'),
    createdAt: _date(json, 'created_at'),
    kind: _string(json, 'kind'),
    granted: _boolean(json, 'granted'),
    policyVersion: _string(json, 'policy_version'),
  );
  @override
  Map<String, dynamic> toJson() => {
    ...super.toJson(),
    'kind': kind,
    'granted': granted,
    'policy_version': policyVersion,
  };
}

extension EntitlementAccess on SubscriptionEntitlement {
  bool hasAccessAt(DateTime now) {
    if (!isActive) return false;
    if (expiresAt == null) return true;
    final end =
        gracePeriodExpiresAt != null &&
            gracePeriodExpiresAt!.isAfter(expiresAt!)
        ? gracePeriodExpiresAt!
        : expiresAt!;
    return end.isAfter(now);
  }
}
