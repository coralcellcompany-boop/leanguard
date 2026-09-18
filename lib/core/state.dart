import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'services/firebase_auth_service.dart';
import 'data/firebase_repository.dart';
import 'package:uuid/uuid.dart';
import 'config.dart';
import 'data/repository.dart';
import 'domain/policies.dart';
import 'services/subscription_service.dart';
import 'services/health_service.dart';
import 'services/notification_service.dart';
import 'services/privacy_service.dart';
import 'services/push_service.dart';
import 'services/data_export_service.dart';
import 'services/background_health_service.dart';
import 'services/report_service.dart';
import '../features/plan/domain/plan_builder.dart';

final repositoryProvider = Provider<LeanRepository>(
  (ref) => LeanRepository(
    store: const SecureLocalStore(),
    remote: AppConfig.configured ? FirebaseRepositoryRemote() : null,
  ),
);
final authServiceProvider = Provider<FirebaseAuthService?>(
  (ref) => AppConfig.configured
      ? FirebaseAuthService(firebase.FirebaseAuth.instance)
      : null,
);
final subscriptionServiceProvider = Provider<SubscriptionService>((ref) {
  final service = SubscriptionService();
  ref.onDispose(service.dispose);
  return service;
});
final healthServiceProvider = Provider<HealthService>((ref) => HealthService());
final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(),
);
final appProvider = StateNotifierProvider<AppController, AppState>(
  (ref) => AppController(
    ref.read(repositoryProvider),
    ref.read(subscriptionServiceProvider),
    ref.read(healthServiceProvider),
    ref.read(notificationServiceProvider),
    auth: ref.read(authServiceProvider),
  ),
);

class AppState {
  const AppState({
    this.initialized = false,
    this.busy = false,
    this.offline = false,
    this.demo = false,
    this.authenticated = false,
    this.error,
    this.records = const {},
    this.subscription = const SubscriptionStatus(),
    this.activeWorkout,
    this.lastWorkoutSummary,
    this.proposal,
    this.packages = const [],
    this.purchasing = false,
    this.purchaseMessage,
    this.trialEligible = false,
    this.healthAccess = HealthAccess.notRequested,
    this.passwordRecovery = false,
    this.coachUsed = 0,
  });
  final bool initialized,
      busy,
      offline,
      demo,
      authenticated,
      purchasing,
      trialEligible,
      passwordRecovery;
  final String? error, purchaseMessage;
  final Map<String, List<Json>> records;
  final SubscriptionStatus subscription;
  final Json? activeWorkout, lastWorkoutSummary, proposal;
  final List<Package> packages;
  final HealthAccess healthAccess;
  final int coachUsed;
  List<Json> rows(String table) => records[table] ?? [];
  Json get profile => rows('user_profiles').firstOrNull ?? {};
  Json get goalProfile => rows('goal_profiles').firstOrNull ?? {};
  bool get isPro => subscription.isPro;
  bool get onboardingComplete => profile['onboarding_completed'] == true;
  String get name => profile['display_name'] as String? ?? 'Your journey';
  String get units => profile['units'] == 'imperial' ? 'lb' : 'kg';
  List<String> get goals => List<String>.from(
    goalProfile['goals'] ?? ['Keep my muscle', 'Get stronger'],
  );
  bool get glpEnabled =>
      rows('medication_support_preferences').firstOrNull?['enabled'] == true;
  int get stepTarget => (goalProfile['step_target'] as num?)?.toInt() ?? 8000;
  int get proteinTarget =>
      (goalProfile['protein_target_g'] as num?)?.toInt() ?? 116;
  String get today => DateTime.now().toIso8601String().substring(0, 10);
  List<Json> get activities => rows('daily_activities');
  int get steps =>
      (activities.where((e) => e['date'] == today).firstOrNull?['steps']
              as num?)
          ?.toInt() ??
      0;
  List<Json> get meals => rows('protein_entries')
      .where((e) => _isToday(e['recorded_at']))
      .map(
        (e) => {
          ...e,
          'protein_grams': e['protein_g'],
          'logged_at': e['recorded_at'],
        },
      )
      .toList();
  double get proteinToday =>
      meals.fold(0, (a, b) => a + (b['protein_g'] as num).toDouble());
  List<Json> get weights => [...rows('weight_entries')]
    ..sort(
      (a, b) =>
          b['recorded_at'].toString().compareTo(a['recorded_at'].toString()),
    );
  List<Json> get measurements => [...rows('body_measurements')]
    ..sort(
      (a, b) =>
          b['recorded_at'].toString().compareTo(a['recorded_at'].toString()),
    );
  List<Json> get workouts => rows('workouts');
  int get completedWorkouts => workouts
      .where(
        (e) =>
            e['status'] == 'completed' &&
            DateTime.tryParse(
                  e['completed_at'] ?? '',
                )?.isAfter(DateTime.now().subtract(const Duration(days: 7))) ==
                true,
      )
      .length;
  int get consistency => ProgressMath.consistency(
    completed: completedWorkouts,
    planned: (goalProfile['workouts_per_week'] as int?) ?? 3,
  );
  int get readiness =>
      ProgressMath.readiness(
        observedDays: activities.map((e) => e['date']).toSet().length,
        proteinRatio: proteinToday / proteinTarget,
        stepsRatio: steps / stepTarget,
        workoutRatio: completedWorkouts / 3,
      ) ??
      0;
  List<Json> get messages => rows('coach_messages')
      .map(
        (e) => {
          ...e,
          if (e['structured_content'] is Map)
            ...Map<String, dynamic>.from(e['structured_content']),
        },
      )
      .toList();
  List<Json> get reminders => rows('reminder_preferences')
      .map(
        (e) => {
          ...e,
          'subtitle': e['smart'] == true
              ? 'When your target is incomplete'
              : e['time_of_day'] ?? '18:00',
        },
      )
      .toList();
  int get coachRemaining =>
      (EntitlementPolicy.coachLimit(isPro) - coachUsed).clamp(0, 100);
  List<Json> get exercises {
    final all = rows('exercises');
    final planned =
        rows(
          'workout_exercises',
        ).where((e) => e['workout_id'] == activeWorkout?['id']).toList()..sort(
          (a, b) => (a['position'] as int).compareTo(b['position'] as int),
        );
    if (activeWorkout != null && planned.isNotEmpty) {
      return planned
          .map(
            (p) => {
              ...all.firstWhere((e) => e['id'] == p['exercise_id']),
              'sets': p['target_sets'],
              'reps': p['target_reps'],
              'weight_kg': p['target_weight_kg'],
              'rest_seconds': p['rest_seconds'],
            },
          )
          .toList();
    }
    return all
        .map((e) => {...e, 'sets': 3, 'reps': 10, 'weight_kg': 0.0})
        .toList();
  }

  double? get strengthChangePercent {
    final exerciseIds = rows('exercises').map((e) => e['id']);
    final changes = <double>[];
    for (final exerciseId in exerciseIds) {
      final sessions = rows(
        'workout_exercises',
      ).where((e) => e['exercise_id'] == exerciseId).toList();
      final performances = <({String date, double score})>[];
      for (final session in sessions) {
        final sets = rows('workout_sets').where(
          (e) =>
              e['workout_exercise_id'] == session['id'] &&
              e['completed'] == true,
        );
        double best = 0;
        String date = '';
        for (final set in sets) {
          final score = ProgressMath.estimatedOneRepMax(
            (set['weight_kg'] as num).toDouble(),
            (set['reps'] as num).toInt(),
          );
          if (score > best) {
            best = score;
            date = set['completed_at'] ?? set['created_at'];
          }
        }
        if (best > 0) performances.add((date: date, score: best));
      }
      performances.sort((a, b) => a.date.compareTo(b.date));
      if (performances.length >= 2) {
        changes.add(
          (performances.last.score - performances.first.score) /
              performances.first.score *
              100,
        );
      }
    }
    return changes.isEmpty
        ? null
        : changes.reduce((a, b) => a + b) / changes.length;
  }

  bool get riskFlag => ProgressMath.rapidLossWithStrengthDecline(
    weeklyLossPercent: ProgressMath.weeklyLossPercent(
      weights
          .where(
            (e) => DateTime.parse(
              e['recorded_at'],
            ).isAfter(DateTime.now().subtract(const Duration(days: 28))),
          )
          .toList(),
    ),
    strengthChangePercent: strengthChangePercent,
  );

  bool _isToday(dynamic value) {
    final d = DateTime.tryParse(value?.toString() ?? '')?.toLocal();
    final now = DateTime.now();
    return d != null &&
        d.year == now.year &&
        d.month == now.month &&
        d.day == now.day;
  }

  AppState copy({
    bool? initialized,
    bool? busy,
    bool? offline,
    bool? demo,
    bool? authenticated,
    String? error,
    bool clearError = false,
    Map<String, List<Json>>? records,
    SubscriptionStatus? subscription,
    Json? activeWorkout,
    bool clearWorkout = false,
    Json? lastWorkoutSummary,
    Json? proposal,
    bool clearProposal = false,
    List<Package>? packages,
    bool? purchasing,
    String? purchaseMessage,
    bool? trialEligible,
    HealthAccess? healthAccess,
    bool? passwordRecovery,
    int? coachUsed,
  }) => AppState(
    initialized: initialized ?? this.initialized,
    busy: busy ?? this.busy,
    offline: offline ?? this.offline,
    demo: demo ?? this.demo,
    authenticated: authenticated ?? this.authenticated,
    error: clearError ? null : error ?? this.error,
    records: records ?? this.records,
    subscription: subscription ?? this.subscription,
    activeWorkout: clearWorkout ? null : activeWorkout ?? this.activeWorkout,
    lastWorkoutSummary: lastWorkoutSummary ?? this.lastWorkoutSummary,
    proposal: clearProposal ? null : proposal ?? this.proposal,
    packages: packages ?? this.packages,
    purchasing: purchasing ?? this.purchasing,
    purchaseMessage: purchaseMessage ?? this.purchaseMessage,
    trialEligible: trialEligible ?? this.trialEligible,
    healthAccess: healthAccess ?? this.healthAccess,
    passwordRecovery: passwordRecovery ?? this.passwordRecovery,
    coachUsed: coachUsed ?? this.coachUsed,
  );
}

class AppController extends StateNotifier<AppState> {
  AppController(
    this.repository,
    this.subscriptions,
    this.health,
    this.notifications, {
    this.auth,
  }) : super(const AppState());
  final FirebaseAuthService? auth;
  final LeanRepository repository;
  final SubscriptionService subscriptions;
  final HealthService health;
  final NotificationService notifications;
  final privacy = PrivacyService(dsn: AppConfig.sentryDsn);
  PushService? _push;
  String? _openingUser;
  String? _conversationId;
  final backgroundHealth = BackgroundHealthService();
  void Function(String)? _notificationTap;
  void Function(String)? get onNotificationTap => _notificationTap;
  set onNotificationTap(void Function(String)? value) {
    _notificationTap = value;
    notifications.setTapHandler(value);
    _push?.setTapHandler(value);
  }

  int _healthEpoch = 0;
  int _accountEpoch = 0;
  Future<void> _notificationScheduling = Future<void>.value();
  StreamSubscription<firebase.User?>? _auth;
  StreamSubscription<SubscriptionStatus>? _subscription;
  Future<void>? _syncing;
  static const _uuid = Uuid();
  String id() => _uuid.v4();
  Json row(Json data) => {
    'user_id': repository.userId,
    'id': id(),
    'created_at': DateTime.now().toUtc().toIso8601String(),
    ...data,
  };
  String get now => DateTime.now().toUtc().toIso8601String();
  void _emit() {
    if (mounted) state = state.copy(records: Map.of(repository.records));
  }

  void clearError() => state = state.copy(clearError: true);
  void reportError(Object error) {
    state = state.copy(
      error: _safeError(error),
      busy: false,
      purchasing: false,
    );
    unawaited(
      privacy.report(error, StackTrace.current).catchError((Object _) {}),
    );
  }

  String _safeError(Object error) {
    if (error is firebase.FirebaseAuthException) {
      return error.message ?? 'Sign-in could not be completed.';
    }
    if (error is FormatException) return error.message;
    if (error is StateError) return error.message;
    if (error is BackendException && error.status == 429) {
      return 'Your coaching allowance is used. Your logs remain available.';
    }
    return 'We could not complete that request. Check your connection and try again.';
  }

  Future<void> initialize() async {
    if (state.initialized) return;
    _subscription = subscriptions.changes.listen((s) {
      if (mounted &&
          state.authenticated &&
          !state.demo &&
          repository.userId == auth?.currentUser?.uid &&
          subscriptions.activeUserId == repository.userId) {
        final changed = state.isPro != s.isPro;
        state = state.copy(subscription: s);
        if (!s.isPro) {
          unawaited(backgroundHealth.disable().catchError((Object _) {}));
        }
        if (changed) unawaited(rescheduleNotifications());
      }
    });
    bool accepted(firebase.User user) =>
        !user.providerData.any((p) => p.providerId == 'password') ||
        user.emailVerified;
    if (auth != null) {
      _auth = auth!.userChanges.listen((user) async {
        if (!mounted) return;
        if (user != null && accepted(user) && repository.userId != user.uid) {
          try {
            await _openUser(user.uid, user.displayName);
          } catch (e) {
            if (mounted && auth?.currentUser?.uid == user.uid) {
              reportError(e);
              state = state.copy(initialized: true);
            }
          }
        }
        if ((user == null || !accepted(user)) &&
            !state.demo &&
            state.authenticated) {
          await signOut();
        }
      });
      final user = auth!.currentUser;
      if (user != null && accepted(user)) {
        try {
          await _openUser(user.uid, user.displayName);
        } catch (e) {
          if (mounted && auth?.currentUser?.uid == user.uid) reportError(e);
        }
      }
    }
    if (mounted) state = state.copy(initialized: true);
  }

  Future<void> _openUser(String userId, String? name) async {
    if (_openingUser == userId) return;
    final epoch = ++_accountEpoch;
    bool current() =>
        mounted &&
        _accountEpoch == epoch &&
        repository.userId == userId &&
        auth?.currentUser?.uid == userId;
    _openingUser = userId;
    _syncing = null;
    try {
      _conversationId = null;
      await repository.open(userId);
      if (!current()) return;
      state = AppState(
        initialized: true,
        authenticated: true,
        records: Map.of(repository.records),
        passwordRecovery: state.passwordRecovery,
      );
      await refresh();
      if (!current()) return;
      if (state.offline && repository.rows('user_profiles').isEmpty) {
        _openingUser = null;
        return;
      }
      if (repository.rows('user_profiles').isEmpty) {
        await _put(
          'user_profiles',
          row({
            'display_name': name ?? 'You',
            'units': 'metric',
            'time_zone': 'UTC',
            'onboarding_completed': false,
          }),
        );
      }
      await _ensureStarter();
      if (!current()) return;
      try {
        await subscriptions.configure(
          iosApiKey: AppConfig.revenueCatIos,
          androidApiKey: AppConfig.revenueCatAndroid,
          userId: userId,
        );
        if (!current()) return;
        if (subscriptions.isConfigured) {
          await repository.invoke('sync-entitlement');
        }
      } catch (e) {
        if (current()) reportError(e);
      }
      if (!current()) return;
      await _restoreWorkout();
      if (!current()) return;
      await privacy.setConsent(
        analytics: state.profile['analytics_enabled'] == true,
        diagnostics: state.profile['crash_reporting_enabled'] == true,
      );
      if (!current()) return;
      await privacy.track(AnalyticsEvent.appOpened);
      if (current()) await rescheduleNotifications();
    } finally {
      if (_openingUser == userId) _openingUser = null;
    }
  }

  Future<void> enterDemo() async {
    if (state.authenticated || auth?.currentUser != null) {
      await signOut();
    }
    _accountEpoch++;
    _healthEpoch++;
    await repository.open('preview');
    state = AppState(
      initialized: true,
      demo: true,
      records: Map.of(repository.records),
    );
    if (repository.rows('user_profiles').isEmpty) {
      await _put(
        'user_profiles',
        row({
          'display_name': 'Explorer',
          'units': 'metric',
          'onboarding_completed': false,
        }),
      );
    }
    await _ensureStarter();
    await _restoreWorkout();
  }

  Future<void> _put(String table, Json data) async {
    final owner = repository.userId;
    await repository.put(table, data);
    if (repository.userId != owner || !mounted) {
      throw StateError('Your account changed during this action.');
    }
    _emit();
  }

  Future<void> saveRecord(String table, Json data) async {
    await _put(table, row(data));
    unawaited(refresh());
  }

  Future<void> _singleton(String table, Json values) async => _put(table, {
    ...(repository.rows(table).firstOrNull ?? row({})),
    ...values,
  });
  Future<void> refresh() async {
    if (_syncing != null) return _syncing;
    final completer = Completer<void>();
    _syncing = completer.future;
    final syncingUser = repository.userId;
    try {
      await repository.sync();
      if (repository.userId == syncingUser && mounted) {
        _emit();
        state = state.copy(
          offline: false,
          clearError: state.error?.startsWith('Saved on this device.') == true,
        );
      }
    } catch (e) {
      if (repository.userId == syncingUser && mounted) {
        state = state.copy(
          offline: true,
          error:
              'Saved on this device. Sync is unavailable; tap Retry when connected.',
        );
      }
    } finally {
      if (identical(_syncing, completer.future)) _syncing = null;
      completer.complete();
    }
  }

  Future<void> setGoals(List<String> values) async {
    if (values.isEmpty) {
      throw const FormatException('Choose at least one goal.');
    }
    await _singleton('goal_profiles', {
      'goal': 'lose_weight',
      'goals': values,
      'protein_target_g': state.proteinTarget,
      'step_target': state.stepTarget,
      'workouts_per_week': 3,
    });
  }

  Future<void> setGlp(bool enabled) async {
    await _singleton('medication_support_preferences', {
      'enabled': enabled,
      'clinician_supervised': enabled,
      'appetite_level': 'normal',
    });
    unawaited(refresh());
  }

  Future<void> finishOnboarding() async {
    if (!state.demo) await notifications.initialize(onTap: onNotificationTap);
    await _singleton('user_profiles', {
      'onboarding_completed': true,
      'time_zone': state.demo ? 'UTC' : notifications.timezone,
    });
    await recordConsent('terms', true);
    await recordConsent('privacy', true);
    await privacy.track(AnalyticsEvent.onboardingCompleted);
    unawaited(refresh());
  }

  Future<void> saveProfile({
    required String name,
    required String units,
  }) async {
    if (name.trim().isEmpty || name.length > 80) {
      throw const FormatException('Enter a name up to 80 characters.');
    }
    await _singleton('user_profiles', {
      'display_name': name.trim(),
      'units': units == 'lb' ? 'imperial' : 'metric',
    });
    unawaited(refresh());
  }

  Future<void> saveTargets({
    required int protein,
    required int steps,
    required int workouts,
    List<String>? equipment,
    List<String>? allergies,
    List<String>? dietaryPreferences,
  }) async {
    if (protein < 20 ||
        protein > 300 ||
        steps < 500 ||
        steps > 50000 ||
        workouts < 1 ||
        workouts > 7) {
      throw const FormatException('Check your targets.');
    }
    await _singleton('goal_profiles', {
      'goal': 'lose_weight',
      'protein_target_g': protein,
      'step_target': steps,
      'workouts_per_week': workouts,
      'equipment': ?equipment,
      'allergies': ?allergies,
      'dietary_preferences': ?dietaryPreferences,
    });
    unawaited(refresh());
  }

  Future<void> addWeight(double kg, {DateTime? date}) async {
    if (!kg.isFinite || kg < 20 || kg > 400) {
      throw const FormatException('Enter a weight from 20 to 400 kg.');
    }
    await saveRecord('weight_entries', {
      'weight_kg': kg,
      'recorded_at': (date ?? DateTime.now()).toUtc().toIso8601String(),
      'source': 'manual',
    });
  }

  Future<void> addMeal(String name, double grams, String type) async {
    if (name.trim().isEmpty ||
        name.length > 120 ||
        !grams.isFinite ||
        grams <= 0 ||
        grams > 200) {
      throw const FormatException('Enter a meal and protein from 1 to 200 g.');
    }
    await saveRecord('protein_entries', {
      'name': name.trim(),
      'protein_g': grams,
      'meal_type': type,
      'recorded_at': now,
    });
  }

  Future<void> addMeasurement(String type, double cm) async {
    if (!EntitlementPolicy.canLogMeasurement(type, state.isPro)) {
      throw StateError(
        'This measurement requires Pro. Existing records remain available.',
      );
    }
    final min = ['arm', 'thigh'].contains(type) ? 10 : 20;
    final max = type == 'arm'
        ? 100
        : type == 'thigh'
        ? 150
        : 300;
    if (!cm.isFinite || cm < min || cm > max) {
      throw FormatException('Enter a measurement from $min to $max cm.');
    }
    if (!['waist', 'hips', 'chest', 'arm', 'thigh'].contains(type)) {
      throw const FormatException('Choose a measurement.');
    }
    await saveRecord('body_measurements', {
      '${type}_cm': cm,
      'recorded_at': now,
    });
  }

  Future<void> logWalk(int steps) async {
    if (steps < 0 || steps > 100000) {
      throw const FormatException('Enter steps from 0 to 100,000.');
    }
    final current = state.activities
        .where((e) => e['date'] == state.today)
        .firstOrNull;
    await _put('daily_activities', {
      ...(current ?? row({})),
      'date': state.today,
      'steps': steps,
      'source': 'manual',
    });
    unawaited(refresh());
  }

  Future<void> addWalkSteps(int steps) async => logWalk(state.steps + steps);
  Future<void> _ensureStarter() async {
    if (repository.rows('exercises').isEmpty) {
      for (final exercise in [
        [
          'Chest press',
          'chest',
          'Dumbbell',
          'Lie on a stable bench. Keep feet planted. Lower with control. Stop if you feel pain.',
        ],
        [
          'One-arm row',
          'back',
          'Dumbbell',
          'Support yourself on a stable bench. Pull your elbow toward your hip without twisting.',
        ],
        [
          'Goblet squat',
          'legs',
          'Dumbbell',
          'Hold a comfortable weight at your chest. Sit between your hips through a comfortable range.',
        ],
        [
          'Shoulder press',
          'shoulders',
          'Dumbbell',
          'Brace gently and press through a comfortable range. Avoid arching your lower back.',
        ],
        [
          'Romanian deadlift',
          'legs',
          'Dumbbell',
          'Keep a soft bend in your knees. Hinge at your hips with a neutral back.',
        ],
        [
          'Wall push-up',
          'chest',
          'Bodyweight',
          'Place your hands on a stable wall. Bend your elbows through a comfortable range and press away slowly.',
        ],
        [
          'Chair squat',
          'legs',
          'Bodyweight',
          'Use a stable chair against a wall. Sit down with control and stand up using support as needed.',
        ],
        [
          'Glute bridge',
          'legs',
          'Bodyweight',
          'Lie on your back with feet planted. Lift your hips comfortably without arching your back.',
        ],
        [
          'Prone W raise',
          'back',
          'Bodyweight',
          'Lie comfortably face down and gently lift your arms in a W position. Keep the movement small and stop for discomfort.',
        ],
        [
          'Band row',
          'back',
          'Band',
          'Secure the band to a stable anchor. Pull with controlled motion and inspect the band before use.',
        ],
        [
          'Band chest press',
          'chest',
          'Band',
          'Use a secure anchor at chest height. Press forward through a comfortable range.',
        ],
        [
          'Band squat',
          'legs',
          'Band',
          'Stand securely on an intact band and squat through a comfortable range with control.',
        ],
        [
          'Machine chest press',
          'chest',
          'Machine',
          'Adjust the seat to a comfortable height. Press the handles without locking your elbows.',
        ],
        [
          'Machine leg press',
          'legs',
          'Machine',
          'Ask a qualified trainer to show the seat adjustment. Use a comfortable range without locking your knees.',
        ],
        [
          'Seated cable row',
          'back',
          'Machine',
          'Sit tall and pull the handles toward your body with controlled movement.',
        ],
        [
          'Dead bug',
          'core',
          'Bodyweight',
          'Lie on your back. Slowly extend opposite arm and leg while breathing comfortably.',
        ],
      ]) {
        await _put(
          'exercises',
          row({
            'name': exercise[0],
            'muscle_group': exercise[1],
            'equipment': exercise[2],
            'instructions': [exercise[3]],
          }),
        );
      }
    }
    if (repository.rows('strength_plans').isEmpty) {
      await _put(
        'strength_plans',
        row({
          'name': 'Muscle retention foundation',
          'description':
              'A starter 3-day plan. Start with a comfortable load and controlled repetitions.',
          'is_active': true,
          'version': 1,
          'source': 'starter',
          'schedule': [
            {'day': 1, 'name': 'Lower body'},
            {'day': 4, 'name': 'Upper body'},
            {'day': 6, 'name': 'Full body'},
          ],
        }),
      );
    }
    await _ensurePlannedWorkouts();
  }

  Future<void> _ensurePlannedWorkouts() async {
    final plan = repository
        .rows('strength_plans')
        .where((e) => e['is_active'] == true)
        .firstOrNull;
    if (plan == null) return;
    final personalized =
        plan['source'] == 'manual' || plan['source'] == 'coach';
    final profile = state.goalProfile;
    final blueprint = PlanBuilder.build(
      library: repository.rows('exercises'),
      equipment: List<String>.from(profile['equipment'] ?? []),
      days: List<int>.from(profile['training_days'] ?? [1, 4, 6]),
      minutes: (profile['session_minutes'] as int?) ?? 35,
      personalized: personalized,
      preferredExercises: List<String>.from(
        profile['exercise_preferences'] ?? [],
      ),
    );
    for (final session in blueprint) {
      if (repository
          .rows('workouts')
          .any(
            (w) =>
                w['plan_id'] == plan['id'] &&
                w['name'] == session.name &&
                w['status'] == 'planned',
          )) {
        continue;
      }
      final workout = row({
        'plan_id': plan['id'],
        'name': session.name,
        'status': 'planned',
        'duration_seconds': 0,
        'scheduled_date': session.date.toIso8601String().substring(0, 10),
      });
      await _put('workouts', workout);
      for (final entry in session.exerciseIds.indexed) {
        final last = history(entry.$2).lastOrNull;
        await _put(
          'workout_exercises',
          row({
            'workout_id': workout['id'],
            'exercise_id': entry.$2,
            'position': entry.$1,
            'target_sets': session.sets,
            'target_reps': last?['reps'] ?? 10,
            'target_weight_kg': last?['weight_kg'] ?? 0,
            'rest_seconds': 90,
            'status': 'planned',
          }),
        );
      }
    }
  }

  Future<void> startWorkout([String title = 'Upper body']) async {
    if (state.activeWorkout != null) return;
    await _ensureStarter();
    final planned = repository
        .rows('workouts')
        .where((e) => e['name'] == title && e['status'] == 'planned')
        .firstOrNull;
    if (planned == null) {
      throw StateError(
        'No planned workout is available. Refresh your plan and try again.',
      );
    }
    await _put('workouts', {
      ...planned,
      'status': 'in_progress',
      'started_at': now,
    });
    await _restoreWorkout();
    unawaited(refresh());
  }

  Future<void> _restoreWorkout() async {
    final workout = repository
        .rows('workouts')
        .where((e) => e['status'] == 'in_progress')
        .lastOrNull;
    if (workout == null) return;
    final ex =
        repository
            .rows('workout_exercises')
            .where((e) => e['workout_id'] == workout['id'])
            .toList()
          ..sort(
            (a, b) => (a['position'] as int).compareTo(b['position'] as int),
          );
    final sets = repository
        .rows('workout_sets')
        .where((s) => ex.any((e) => e['id'] == s['workout_exercise_id']))
        .toList();
    final index = ex.indexWhere((e) => e['status'] == 'planned');
    final currentIndex = index < 0 ? ex.length : index;
    final currentId = currentIndex < ex.length ? ex[currentIndex]['id'] : null;
    state = state.copy(
      activeWorkout: {
        ...workout,
        'exercise_index': currentIndex,
        'set_number':
            sets.where((s) => s['workout_exercise_id'] == currentId).length + 1,
        'sets': sets,
        'skipped': ex
            .where((e) => e['status'] == 'skipped')
            .map((e) => e['exercise_id'])
            .toList(),
      },
    );
  }

  Future<void> logSet({
    required String exerciseId,
    required int setNumber,
    required int reps,
    required double weightKg,
  }) async {
    if (state.activeWorkout == null) throw StateError('Start a workout first.');
    if (reps < 1 ||
        reps > 100 ||
        weightKg < 0 ||
        weightKg > 500 ||
        !weightKg.isFinite ||
        setNumber < 1 ||
        setNumber > 20) {
      throw const FormatException('Check the reps and weight.');
    }
    final exercise = repository
        .rows('workout_exercises')
        .firstWhere(
          (e) =>
              e['workout_id'] == state.activeWorkout!['id'] &&
              e['exercise_id'] == exerciseId,
        );
    final existing = repository
        .rows('workout_sets')
        .where(
          (s) =>
              s['workout_exercise_id'] == exercise['id'] &&
              s['set_number'] == setNumber,
        )
        .firstOrNull;
    await _put('workout_sets', {
      ...(existing ?? row({})),
      'workout_exercise_id': exercise['id'],
      'set_number': setNumber,
      'reps': reps,
      'weight_kg': weightKg,
      'completed': true,
      'completed_at': now,
    });
    if (setNumber >= (exercise['target_sets'] as int)) {
      await _put('workout_exercises', {...exercise, 'status': 'completed'});
    }
    await _restoreWorkout();
    unawaited(refresh());
  }

  Future<void> skipExercise(String exerciseId) async {
    final exercise = repository
        .rows('workout_exercises')
        .firstWhere(
          (e) =>
              e['workout_id'] == state.activeWorkout?['id'] &&
              e['exercise_id'] == exerciseId,
        );
    await _put('workout_exercises', {...exercise, 'status': 'skipped'});
    await _restoreWorkout();
    unawaited(refresh());
  }

  Future<void> finishWorkout() async {
    final active = state.activeWorkout;
    if (active == null) return;
    final workout = repository
        .rows('workouts')
        .firstWhere((e) => e['id'] == active['id']);
    final sets = List<Json>.from(active['sets'] ?? []);
    final seconds = DateTime.now()
        .difference(DateTime.parse(workout['started_at']))
        .inSeconds
        .clamp(0, 86400);
    await _put('workouts', {
      ...workout,
      'status': sets.isEmpty ? 'skipped' : 'completed',
      'completed_at': now,
      'duration_seconds': seconds,
    });
    for (final ex
        in repository
            .rows('workout_exercises')
            .where(
              (e) =>
                  e['workout_id'] == workout['id'] && e['status'] == 'planned',
            )
            .toList()) {
      await _put('workout_exercises', {...ex, 'status': 'skipped'});
    }
    state = state.copy(
      clearWorkout: true,
      lastWorkoutSummary: {
        'workout_id': workout['id'],
        'status': sets.isEmpty ? 'skipped' : 'completed',
        'workout_name': workout['name'],
        'duration_seconds': seconds,
        'sets': sets.length,
        'volume_kg': sets.fold<double>(
          0,
          (v, s) => v + (s['weight_kg'] as num) * (s['reps'] as num),
        ),
        'exercises': repository
            .rows('workout_exercises')
            .where(
              (e) =>
                  e['workout_id'] == workout['id'] &&
                  e['status'] == 'completed',
            )
            .length,
      },
    );
    await _ensurePlannedWorkouts();
    unawaited(refresh());
  }

  List<Json> history(String exerciseId) {
    final ids = repository
        .rows('workout_exercises')
        .where((e) => e['exercise_id'] == exerciseId)
        .map((e) => e['id'])
        .toSet();
    return repository
        .rows('workout_sets')
        .where((e) => ids.contains(e['workout_exercise_id']))
        .toList();
  }

  Future<void> askCoach(String message, {String kind = 'question'}) async {
    if (state.busy) return;
    if (message.trim().isEmpty || message.length > 2000) {
      throw const FormatException('Ask a question up to 2,000 characters.');
    }
    final coachOwner = repository.userId;
    state = state.copy(busy: true, clearError: true);
    try {
      final local = CoachSafety.localEscalation(message);
      if (local != null || state.demo) {
        await repository.put(
          'coach_messages',
          row({'role': 'user', 'content': message}),
          queue: false,
        );
        await repository.put(
          'coach_messages',
          row({
            'role': 'assistant',
            'content':
                local ??
                'Preview mode does not contact AI. Connect an account to get coaching based on your own logs. For now, focus on a comfortable workout, your protein target, and regular movement.',
          }),
          queue: false,
        );
        _emit();
        return;
      }
      if (kind == 'adaptation' && !state.isPro) {
        throw StateError('Plan adaptation is a Pro feature.');
      }
      if (!hasConsent('ai_processing')) {
        throw StateError(
          'Enable AI processing in Privacy settings before asking the coach.',
        );
      }
      await refresh();
      final result = await repository.invoke('coach', {
        'message': message.trim(),
        'kind': kind,
        if (_conversationId != null) 'conversation_id': _conversationId,
      });
      _conversationId = result['conversation_id'] as String?;
      final text =
          result['summary']?.toString() ??
          'Coaching is temporarily unavailable. Keep your current plan and try again later.';
      final messages = repository.rows('coach_messages');
      if (result['messages'] == null) {
        await repository.put(
          'coach_messages',
          row({'role': 'user', 'content': message}),
          queue: false,
        );
        await repository.put(
          'coach_messages',
          row({
            'role': 'assistant',
            'content': text,
            'evidence': result['evidence'] ?? [],
            'actions': result['actions'] ?? [],
            'safety': result['safety'],
          }),
          queue: false,
        );
      } else {
        repository.records['coach_messages'] = [
          ...messages,
          ...List<Json>.from(result['messages']),
        ];
      }
      state = state.copy(
        proposal: result['proposal'] is Map
            ? Json.from(result['proposal'])
            : null,
        coachUsed:
            (kind == 'question' || state.isPro) && result['remaining'] is num
            ? EntitlementPolicy.coachLimit(state.isPro) -
                  (result['remaining'] as num).toInt()
            : state.coachUsed,
      );
      _emit();
    } catch (e) {
      if (repository.userId != coachOwner || !mounted) return;
      reportError(e);
      await repository.put(
        'coach_messages',
        row({
          'role': 'assistant',
          'content':
              'Coaching is unavailable right now. Your plan is unchanged. You can still log workouts, meals, steps and weight. Try again when connected.',
          'fallback': true,
        }),
        queue: false,
      );
      _emit();
    } finally {
      if (repository.userId == coachOwner && mounted) {
        state = state.copy(busy: false);
      }
    }
  }

  Future<void> approveProposal() async {
    final proposal = state.proposal;
    if (proposal == null) return;
    await repository.invoke('approve-plan', {
      'proposal_id': proposal['id'],
      'approved': true,
    });
    state = state.copy(clearProposal: true);
    await refresh();
  }

  Future<void> dismissProposal() async {
    if (state.proposal != null && !state.demo) {
      await repository.invoke('approve-plan', {
        'proposal_id': state.proposal!['id'],
        'approved': false,
      });
    }
    state = state.copy(clearProposal: true);
  }

  Future<void> loadOfferings() async {
    try {
      final offerings = await subscriptions.offerings();
      final packages = offerings.current?.availablePackages ?? <Package>[];
      state = state.copy(packages: packages);
      final annual = packages
          .where((p) => p.packageType == PackageType.annual)
          .firstOrNull;
      if (annual != null) {
        final eligibility = await subscriptions.trialEligibility([
          annual.storeProduct.identifier,
        ]);
        state = state.copy(
          trialEligible:
              eligibility[annual.storeProduct.identifier]?.status ==
                  IntroEligibilityStatus.introEligibilityStatusEligible &&
              annual.storeProduct.introductoryPrice?.price == 0 &&
              ((annual.storeProduct.introductoryPrice?.periodNumberOfUnits ==
                          7 &&
                      annual.storeProduct.introductoryPrice?.periodUnit ==
                          PeriodUnit.day) ||
                  (annual.storeProduct.introductoryPrice?.periodNumberOfUnits ==
                          1 &&
                      annual.storeProduct.introductoryPrice?.periodUnit ==
                          PeriodUnit.week)),
        );
      }
    } catch (e) {
      state = state.copy(purchaseMessage: _safeError(e));
    }
  }

  Future<void> purchase(bool annual) async {
    if (state.purchasing) return;
    state = state.copy(purchasing: true);
    try {
      final package = state.packages
          .where(
            (p) =>
                p.packageType ==
                (annual ? PackageType.annual : PackageType.monthly),
          )
          .firstOrNull;
      if (package == null) {
        throw StateError('Store products are unavailable. Please try again.');
      }
      final status = await subscriptions.purchase(package);
      state = state.copy(
        subscription: status,
        purchaseMessage: status.isPro
            ? 'LeanGuard Pro is active.'
            : 'The purchase is pending store confirmation.',
      );
      if (status.isPro) await repository.invoke('sync-entitlement');
    } catch (e) {
      reportError(e);
    } finally {
      state = state.copy(purchasing: false);
    }
  }

  Future<void> restorePurchases() async {
    state = state.copy(purchasing: true);
    try {
      final status = await subscriptions.restore();
      state = state.copy(
        subscription: status,
        purchaseMessage: status.isPro
            ? 'Your Pro subscription is restored.'
            : 'No active Pro subscription was found for this store account.',
      );
      await repository.invoke('sync-entitlement');
    } catch (e) {
      reportError(e);
    } finally {
      state = state.copy(purchasing: false);
    }
  }

  Future<void> manageSubscription() async {
    try {
      await subscriptions.manageSubscription();
    } catch (e) {
      reportError(e);
    }
  }

  Future<void> recordConsent(String purpose, bool granted) async {
    await _put(
      'consent_records',
      row({
        'kind': purpose,
        'granted': granted,
        'policy_version': '2026-09-18',
      }),
    );
    unawaited(refresh());
  }

  Future<void> toggleReminder(String reminderId, bool enabled) async {
    final existing = repository
        .rows('reminder_preferences')
        .where((e) => e['id'] == reminderId || e['kind'] == reminderId)
        .firstOrNull;
    if (enabled &&
        !state.isPro &&
        state.reminders
                .where(
                  (e) => e['enabled'] == true && e['id'] != (existing?['id']),
                )
                .length >=
            3) {
      throw StateError('The Free plan includes three fixed reminders.');
    }
    final kind = existing?['kind'] ?? reminderId;
    if (!state.demo) await notifications.initialize(onTap: onNotificationTap);
    if (enabled && kind == 'walking' && !state.isPro) {
      throw StateError('Smart walking nudges require Pro.');
    }
    if (enabled && kind == 'walking' && !await enableRemoteReminders()) {
      throw StateError(
        'Smart reminders need push notifications. Check permission and Firebase setup.',
      );
    }
    await _put('reminder_preferences', {
      ...(existing ?? row({})),
      'kind': kind,
      'title':
          existing?['title'] ??
          {
            'workout': 'Workout reminder',
            'protein': 'Protein check-in',
            'walking': 'Walking nudge',
            'weekly': 'Weekly review',
          }[kind] ??
          'Reminder',
      'time_of_day':
          existing?['time_of_day'] ??
          (kind == 'protein' ? '14:00:00' : '18:00:00'),
      'days_of_week':
          existing?['days_of_week'] ??
          (kind == 'workout'
              ? [1, 4, 6]
              : kind == 'weekly'
              ? [7]
              : [1, 2, 3, 4, 5, 6, 7]),
      if (state.reminders.firstOrNull?['quiet_start'] != null &&
          existing == null) ...{
        'quiet_start': state.reminders.first['quiet_start'],
        'quiet_end': state.reminders.first['quiet_end'],
      },
      'enabled': enabled,
      'smart': kind == 'walking',
      'time_zone': state.demo ? 'UTC' : notifications.timezone,
      'delivery': kind == 'walking' ? 'push' : 'local',
    });
    await rescheduleNotifications();
    unawaited(refresh());
  }

  Future<bool> enableNotifications() async {
    if (state.demo) return false;
    await notifications.initialize(onTap: onNotificationTap);
    final allowed = await notifications.requestPermission();
    await recordConsent('notifications', allowed);
    if (allowed) await rescheduleNotifications();
    return allowed;
  }

  Future<void> rescheduleNotifications() {
    _notificationScheduling = _notificationScheduling.then(
      (_) => _scheduleCurrentNotifications(),
    );
    return _notificationScheduling;
  }

  Future<void> _scheduleCurrentNotifications() async {
    if (!mounted || state.demo || !state.authenticated) return;
    final owner = repository.userId;
    bool current() =>
        mounted &&
        state.authenticated &&
        !state.demo &&
        repository.userId == owner;
    try {
      await notifications.initialize(onTap: onNotificationTap);
      if (!current()) return;
      await notifications.cancelAll();
      if (!current()) return;
      int minute(String value) {
        final p = value.split(':');
        return int.parse(p[0]) * 60 + int.parse(p[1]);
      }

      for (final entry
          in state.reminders
              .where(
                (e) =>
                    e['enabled'] == true &&
                    e['smart'] != true &&
                    e['delivery'] != 'push',
              )
              .take(state.isPro ? state.reminders.length : 3)
              .indexed) {
        if (!current()) return;
        final r = entry.$2,
            parts = (entry.$2['time_of_day'] as String).split(':');
        await notifications.scheduleWeekly(
          id: entry.$1 + 1,
          daysOfWeek: List<int>.from(
            r['days_of_week'] ?? [1, 2, 3, 4, 5, 6, 7],
          ),
          hour: int.parse(parts[0]),
          minute: int.parse(parts[1]),
          title: r['title'],
          body:
              'A small step for your routine. Open LeanGuard when you are ready.',
          quietHours: QuietHours(
            enabled: state.isPro && r['quiet_start'] != null,
            startMinute: minute(r['quiet_start'] ?? '21:00'),
            endMinute: minute(r['quiet_end'] ?? '08:00'),
          ),
          route: '/today',
        );
      }
    } catch (e) {
      if (current()) reportError(e);
    }
  }

  Future<void> setQuietHours(int start, int end) async {
    if (!state.isPro) throw StateError('Quiet hours require Pro.');
    if (state.reminders.isEmpty) await toggleReminder('workout', false);
    for (final r in state.reminders) {
      final raw = repository
          .rows('reminder_preferences')
          .firstWhere((e) => e['id'] == r['id']);
      await _put('reminder_preferences', {
        ...raw,
        'quiet_start': '${start.toString().padLeft(2, '0')}:00:00',
        'quiet_end': '${end.toString().padLeft(2, '0')}:00:00',
      });
    }
    await rescheduleNotifications();
    unawaited(refresh());
  }

  Future<void> connectHealth() async {
    final owner = repository.userId;
    final epoch = ++_healthEpoch;
    if (state.demo) {
      state = state.copy(healthAccess: HealthAccess.unavailable);
      return;
    }
    try {
      final access = await health.requestAccess(pro: state.isPro);
      if (!mounted || owner != repository.userId || epoch != _healthEpoch) {
        return;
      }
      state = state.copy(healthAccess: access);
      await recordConsent(
        'health_data',
        access != HealthAccess.denied && access != HealthAccess.unavailable,
      );
      await syncHealth();
    } catch (e) {
      reportError(e);
    }
  }

  Future<void> syncHealth() async {
    if (!hasConsent('health_data') || state.demo) return;
    final owner = repository.userId, epoch = _healthEpoch;
    final snapshot = await health.readToday(pro: state.isPro);
    if (!mounted ||
        repository.userId != owner ||
        epoch != _healthEpoch ||
        !hasConsent('health_data') ||
        state.demo) {
      return;
    }
    state = state.copy(healthAccess: snapshot.access);
    final provider = health.isAppleHealth ? 'apple_health' : 'health_connect';
    final connection = repository
        .rows('health_connections')
        .where((e) => e['provider'] == provider)
        .firstOrNull;
    await _put('health_connections', {
      ...(connection ?? row({})),
      'provider': provider,
      'status': snapshot.access == HealthAccess.authorized
          ? 'connected'
          : snapshot.access == HealthAccess.denied
          ? 'denied'
          : snapshot.access == HealthAccess.unavailable
          ? 'unavailable'
          : 'disconnected',
      'permissions': [
        'steps',
        'weight',
        if (state.isPro) ...['workouts', 'active_energy'],
      ],
      'last_synced_at': now,
    });
    if (snapshot.steps != null || snapshot.latestWeightKg != null) {
      await refresh();
      if (repository.userId != owner ||
          epoch != _healthEpoch ||
          !hasConsent('health_data')) {
        return;
      }
      final response = await repository.invoke('syncHealthActivity', {
        'date': state.today,
        'steps': snapshot.steps,
        'active_energy': state.isPro ? snapshot.activeEnergyKcal : null,
        'source': provider,
        if (snapshot.latestWeightKg != null &&
            snapshot.weightExternalId != null &&
            snapshot.weightRecordedAt != null)
          'weight': {
            'kg': snapshot.latestWeightKg,
            'external_id': snapshot.weightExternalId,
            'recorded_at': snapshot.weightRecordedAt!.toUtc().toIso8601String(),
          },
      });
      if (repository.userId != owner || epoch != _healthEpoch) return;
      if (response['activity'] is Map) {
        await repository.put(
          'daily_activities',
          Json.from(response['activity']),
          queue: false,
        );
      }
    }
    unawaited(refresh());
  }

  Future<void> disconnectHealth() async {
    _healthEpoch++;
    await backgroundHealth.disable();
    await health.disconnect();
    await recordConsent('health_data', false);
    for (final connection in repository.rows('health_connections').toList()) {
      await _put('health_connections', {
        ...connection,
        'status': 'disconnected',
      });
    }
    state = state.copy(healthAccess: HealthAccess.notRequested);
    unawaited(refresh());
  }

  bool hasConsent(String kind) =>
      repository
          .rows('consent_records')
          .where((e) => e['kind'] == kind)
          .lastOrNull?['granted'] ==
      true;
  Future<void> setPrivacy({
    required bool analytics,
    required bool diagnostics,
  }) async {
    await _singleton('user_profiles', {
      'analytics_enabled': analytics,
      'crash_reporting_enabled': diagnostics,
    });
    await recordConsent('analytics', analytics);
    await recordConsent('crash_reporting', diagnostics);
    await privacy.setConsent(analytics: analytics, diagnostics: diagnostics);
  }

  void completeRecovery() => state = state.copy(passwordRecovery: false);
  Future<void> onResume() async {
    if (state.demo) {
      await refresh();
      return;
    }
    if (!state.authenticated) return;
    await refresh();
    try {
      if (subscriptions.isConfigured) await subscriptions.refresh();
      await syncHealth();
      await maybeProactiveInsight();
    } catch (e) {
      reportError(e);
    }
  }

  Future<void> maybeProactiveInsight() async {
    if (!state.isPro ||
        state.demo ||
        state.busy ||
        !hasConsent('ai_processing') ||
        state.activeWorkout != null ||
        state.workouts.every((w) => w['status'] != 'completed')) {
      return;
    }
    final now = DateTime.now();
    final weekStart = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    if (state
        .rows('weekly_insights')
        .any((w) => !DateTime.parse(w['created_at']).isBefore(weekStart))) {
      return;
    }
    await askCoach(
      'Review my recent logged routines and up to three next actions.',
      kind: 'weekly',
    );
    await refresh();
  }

  Future<void> saveReminder({
    String? id,
    required String title,
    required String kind,
    required int hour,
    required int minute,
    required List<int> days,
    bool smart = false,
  }) async {
    if (title.trim().isEmpty ||
        title.length > 100 ||
        hour < 0 ||
        hour > 23 ||
        minute < 0 ||
        minute > 59 ||
        days.isEmpty ||
        days.any((d) => d < 1 || d > 7)) {
      throw const FormatException('Choose a reminder name, time and days.');
    }
    if (!EntitlementPolicy.canAddReminder(
      isPro: state.isPro,
      count: state.reminders
          .where((r) => r['enabled'] == true && r['id'] != id)
          .length,
    )) {
      throw StateError('Free includes three fixed reminders.');
    }
    if (smart && !state.isPro) throw StateError('Smart reminders require Pro.');
    if (smart && !await enableRemoteReminders()) {
      throw StateError(
        'Push notifications must be enabled for smart reminders.',
      );
    }
    if (!state.demo) await notifications.initialize(onTap: onNotificationTap);
    final quiet = state.reminders
        .where((r) => r['quiet_start'] != null)
        .firstOrNull;
    await _put('reminder_preferences', {
      ...(id == null
          ? row({})
          : repository
                .rows('reminder_preferences')
                .firstWhere((r) => r['id'] == id)),
      'title': title.trim(),
      'kind': kind,
      'time_of_day':
          '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:00',
      'days_of_week': days,
      'enabled': true,
      'smart': smart,
      'delivery': smart ? 'push' : 'local',
      'time_zone': state.demo ? 'UTC' : notifications.timezone,
      if (quiet != null) ...{
        'quiet_start': quiet['quiet_start'],
        'quiet_end': quiet['quiet_end'],
      },
    });
    await rescheduleNotifications();
    unawaited(refresh());
  }

  Future<bool> enableRemoteReminders() async {
    if (state.demo || auth?.currentUser == null) return false;
    _push ??= PushService(auth!.auth, FirebaseFirestore.instance);
    final granted = await _push!.enable(onTap: onNotificationTap);
    if (granted) await recordConsent('notifications', true);
    return granted;
  }

  Future<bool> enableBackgroundHealth() async {
    if (state.demo || !hasConsent('health_data')) return false;
    return backgroundHealth.enable(
      userId: repository.userId!,
      pro: state.isPro,
    );
  }

  final Set<String> _workoutHealthExports = {};

  Future<void> syncWorkoutToHealth() async {
    final owner = repository.userId;
    final epoch = _healthEpoch;
    final workoutId = state.lastWorkoutSummary?['workout_id'];
    if (!state.isPro) {
      throw StateError('Workout sharing requires Pro.');
    }
    if (state.demo ||
        !state.authenticated ||
        owner == null ||
        auth?.currentUser?.uid != owner) {
      throw StateError('Sign in to share a workout with your health app.');
    }
    if (workoutId is! String || workoutId.isEmpty) {
      throw StateError('This summary has no saved workout to share.');
    }
    Json currentWorkout() {
      final workout = repository
          .rows('workouts')
          .where(
            (row) =>
                row['id'] == workoutId &&
                row['user_id'] == owner &&
                row['status'] == 'completed',
          )
          .firstOrNull;
      if (workout == null) {
        throw StateError('This completed workout is no longer available.');
      }
      return workout;
    }

    void checkSession() {
      if (!mounted ||
          repository.userId != owner ||
          _healthEpoch != epoch ||
          auth?.currentUser?.uid != owner ||
          !state.authenticated ||
          state.demo) {
        throw StateError('Your account changed. Workout sharing was stopped.');
      }
      if (!state.isPro) {
        throw StateError('Pro access changed. Workout sharing was stopped.');
      }
    }

    final workout = currentWorkout();
    if (workout['health_exported_at'] != null) return;
    final start = DateTime.tryParse('${workout['started_at']}');
    final end = DateTime.tryParse('${workout['completed_at']}');
    if (start == null || end == null || !end.isAfter(start)) {
      throw StateError('This workout needs valid start and completion times.');
    }
    final key = '$owner/$workoutId';
    if (!_workoutHealthExports.add(key)) {
      throw StateError('This workout is already being shared.');
    }
    try {
      final allowed = await health.requestWorkoutWriteAccess(pro: true);
      checkSession();
      if (!allowed) {
        throw StateError('Workout sharing permission was not granted.');
      }
      if (currentWorkout()['health_exported_at'] != null) return;
      final written = await health.writeStrengthWorkout(
        pro: true,
        start: start,
        end: end,
      );
      checkSession();
      if (!written) {
        throw StateError(
          'Your health app did not save this workout. Try again.',
        );
      }
      // Native Health and our cache cannot share a transaction. A process crash
      // after the native write but before this marker persists can leave an
      // unconfirmed export; never retry workout exports automatically.
      await _put('workouts', {...currentWorkout(), 'health_exported_at': now});
      unawaited(refresh());
    } finally {
      _workoutHealthExports.remove(key);
    }
  }

  Future<void> deleteAccount() async {
    final owner = repository.userId;
    final epoch = _accountEpoch;
    bool current() =>
        mounted && repository.userId == owner && _accountEpoch == epoch;
    if (owner == null) throw StateError('Sign in first.');
    await _push?.disable();
    if (!current()) {
      throw StateError('Your account changed. Confirm deletion again.');
    }
    if (!state.demo) {
      if (auth?.currentUser == null) throw StateError('Sign in first.');
      await DataExportService(repository).deleteAccount(confirmation: 'DELETE');
    }
    if (current()) await signOut();
  }

  Future<void> signOut() async {
    _accountEpoch++;
    _healthEpoch++;
    state = state.copy(
      subscription: const SubscriptionStatus(),
      authenticated: false,
    );
    for (final cleanup in [
      () => backgroundHealth.disable(),
      () => health.disconnect(),
      () => _push?.disable() ?? Future<void>.value(),
      () => _notificationScheduling,
      () => notifications.cancelAll(),
      () => subscriptions.signOut(),
      () => privacy.setConsent(analytics: false, diagnostics: false),
    ]) {
      try {
        await cleanup();
      } catch (_) {}
    }
    try {
      await auth?.signOut();
    } finally {
      await repository.eraseLocal();
      _conversationId = null;
      _openingUser = null;
      state = const AppState(initialized: true);
    }
  }

  Future<void> saveEquipment(List<String> equipment) async {
    await _singleton('goal_profiles', {'equipment': equipment});
    await _rebuildFuturePlan(personalized: state.isPro);
    unawaited(refresh());
  }

  Future<void> savePersonalization({
    required int minutes,
    required List<int> days,
    required List<String> limitations,
    required List<String> preferences,
    required String tone,
  }) async {
    if (!state.isPro) {
      throw StateError('Advanced personalization requires Pro.');
    }
    if (minutes < 10 ||
        minutes > 180 ||
        days.isEmpty ||
        days.any((d) => d < 1 || d > 7)) {
      throw const FormatException('Choose a session length and training days.');
    }
    await _singleton('goal_profiles', {
      'session_minutes': minutes,
      'training_days': days.toSet().toList(),
      'limitations': limitations,
      'exercise_preferences': preferences,
    });
    await _singleton('user_profiles', {'coaching_tone': tone});
    await _singleton('goal_profiles', {
      'workouts_per_week': days.toSet().length,
    });
    await _rebuildFuturePlan(personalized: true);
    unawaited(refresh());
  }

  Future<void> _rebuildFuturePlan({required bool personalized}) async {
    final plan = repository
        .rows('strength_plans')
        .where((p) => p['is_active'] == true)
        .firstOrNull;
    if (plan == null) return;
    for (final w
        in repository
            .rows('workouts')
            .where(
              (w) => w['status'] == 'planned' && w['plan_id'] == plan['id'],
            )
            .toList()) {
      await _put('workouts', {
        ...w,
        'status': 'skipped',
        'notes': 'Replaced when you saved plan preferences.',
      });
    }
    await _put('strength_plans', {
      ...plan,
      'name': personalized
          ? 'Your muscle retention plan'
          : 'Muscle retention foundation',
      'source': personalized ? 'manual' : 'starter',
      'version': (plan['version'] as int) + 1,
      'schedule': List<int>.from(
        state.goalProfile['training_days'] ?? [1, 4, 6],
      ).map((d) => {'day': d}).toList(),
    });
    await _ensurePlannedWorkouts();
  }

  Future<void> applyAdaptiveTarget({int? steps, int? protein}) async {
    if (!state.isPro) throw StateError('Adaptive targets require Pro.');
    await saveTargets(
      protein: protein ?? state.proteinTarget,
      steps: steps ?? state.stepTarget,
      workouts: (state.goalProfile['workouts_per_week'] as int?) ?? 3,
    );
    final current = repository
        .rows('daily_targets')
        .where((r) => r['date'] == state.today)
        .firstOrNull;
    await _put('daily_targets', {
      ...(current ?? row({})),
      'date': state.today,
      'protein_g': state.proteinTarget,
      'steps': state.stepTarget,
    });
    unawaited(refresh());
  }

  Future<void> substituteExercise(
    String workoutExerciseId,
    String exerciseId,
  ) async {
    if (!state.isPro) throw StateError('Exercise substitutions require Pro.');
    final planned = repository
        .rows('workout_exercises')
        .firstWhere((e) => e['id'] == workoutExerciseId);
    final workout = repository
        .rows('workouts')
        .firstWhere((e) => e['id'] == planned['workout_id']);
    if (workout['status'] != 'planned') {
      throw StateError('Only future workouts can be changed.');
    }
    if (!repository.rows('exercises').any((e) => e['id'] == exerciseId)) {
      throw StateError('Choose an exercise from your library.');
    }
    await _put('workout_exercises', {
      ...planned,
      'exercise_id': exerciseId,
      'target_weight_kg': 0,
    });
    final plan = repository
        .rows('strength_plans')
        .firstWhere((e) => e['id'] == workout['plan_id']);
    await _put('strength_plans', {
      ...plan,
      'version': (plan['version'] as int) + 1,
    });
    unawaited(refresh());
  }

  Future<void> saveGlpCheckIn(
    String appetite,
    int energy,
    bool hydration,
  ) async {
    if (!state.isPro) {
      throw StateError('Appetite and energy check-ins require Pro.');
    }
    if (!['normal', 'low', 'very_low'].contains(appetite) ||
        energy < 1 ||
        energy > 5) {
      throw const FormatException('Choose appetite and energy levels.');
    }
    await _singleton('medication_support_preferences', {
      'appetite_level': appetite,
      'hydration_reminders': hydration,
      'check_ins_enabled': true,
    });
    final activity = state.activities
        .where((e) => e['date'] == state.today)
        .firstOrNull;
    await _put('daily_activities', {
      ...(activity ?? row({'steps': 0, 'source': 'manual'})),
      'date': state.today,
      'energy_level': energy,
    });
    if (hydration) {
      await toggleReminder('hydration', true);
    } else {
      final reminder = state.reminders
          .where((e) => e['kind'] == 'hydration')
          .firstOrNull;
      if (reminder != null) await toggleReminder(reminder['id'], false);
    }
    unawaited(refresh());
  }

  Future<void> exportReport({
    String format = 'csv',
    int days = 30,
    bool clinician = false,
  }) async {
    if (!state.isPro) {
      throw StateError(
        'PDF and CSV reports require Pro. Export all your raw data from Privacy on any plan.',
      );
    }
    if (!['pdf', 'csv'].contains(format)) {
      throw const FormatException('Choose PDF or CSV.');
    }
    await ReportService().export(
      repository.records,
      format: format,
      days: days,
      clinician: clinician,
    );
  }

  @override
  void dispose() {
    _auth?.cancel();
    _subscription?.cancel();
    super.dispose();
  }
}
