import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/data/api_repository.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/config.dart';
import '../../../core/state.dart';
import '../../../core/theme.dart';
import '../../../core/widgets.dart';
import '../../../core/domain/policies.dart';

import '../../../core/services/health_service.dart';
import '../../../core/services/data_export_service.dart';

class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({
    super.key,
    this.forgot = false,
    this.recovery = false,
    this.reauthenticate = false,
  });
  final bool forgot, recovery, reauthenticate;
  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  final _form = GlobalKey<FormState>();
  final email = TextEditingController(),
      password = TextEditingController(),
      name = TextEditingController();
  bool signup = false, busy = false;
  String? message;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    name.dispose();
    super.dispose();
  }

  Future<void> submit([String? social]) async {
    if (social == null && !_form.currentState!.validate()) return;
    final auth = ref.read(authServiceProvider);
    if (auth == null) {
      setState(
        () => message = widget.reauthenticate
            ? 'Secure account verification is unavailable in this build.'
            : 'This build needs its Firebase configuration. You can explore the app in preview mode.',
      );
      return;
    }
    setState(() {
      busy = true;
      message = null;
    });
    try {
      if (social == 'apple') {
        if (widget.reauthenticate) {
          await auth.reauthenticateWithApple();
          if (mounted) context.pop(true);
        } else {
          await auth.signInWithApple();
        }
      } else if (social == 'google') {
        if (widget.reauthenticate) {
          await auth.reauthenticateWithGoogle();
          if (mounted) context.pop(true);
        } else {
          await auth.signInWithGoogle();
        }
      } else if (widget.forgot) {
        await auth.resetPassword(email.text);
        setState(
          () => message =
              'If an account exists, a password reset link has been sent.',
        );
      } else if (widget.recovery) {
        await auth.updatePassword(password.text);
        ref.read(appProvider.notifier).completeRecovery();
        if (mounted) context.go('/today');
      } else if (signup) {
        final result = await auth.signUp(
          email: email.text,
          password: password.text,
          name: name.text,
        );
        if (result.needsConfirmation) {
          setState(
            () => message =
                'Check your email to confirm your account, then sign in.',
          );
        }
      } else {
        if (widget.reauthenticate) {
          await auth.reauthenticateWithEmail(password.text);
        } else {
          await auth.signIn(email: email.text, password: password.text);
        }
        if (widget.reauthenticate && mounted) {
          context.pop(true);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(
        () => message = e is FirebaseAuthException
            ? (e.message ?? 'Sign-in could not finish.')
            : e is FormatException
            ? e.message
            : 'Sign-in could not be completed. Check your details and connection.',
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => LGPage(
    title: widget.reauthenticate
        ? 'Verify your identity'
        : widget.forgot
        ? 'Reset password'
        : widget.recovery
        ? 'Choose a new password'
        : signup
        ? 'Create your account'
        : 'Welcome back',
    dark: false,
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.shield_outlined, size: 52, color: Color(0xFF536E24)),
        const SizedBox(height: 20),
        Text(
          widget.reauthenticate
              ? 'Confirm access to your signed-in account.'
              : widget.forgot
              ? 'We’ll send you a secure reset link.'
              : 'Lose weight. Keep your muscle.',
          style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800),
        ),
        if (widget.reauthenticate) ...[
          const SizedBox(height: 12),
          Text(
            ref.watch(authServiceProvider)?.currentUser?.email ??
                'Use the same sign-in method as your current account.',
          ),
        ],
        const SizedBox(height: 24),
        Form(
          key: _form,
          child: Column(
            children: [
              if (signup && !widget.forgot)
                TextFormField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'Your name'),
                  textInputAction: TextInputAction.next,
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? 'Enter your name.' : null,
                ),
              if (!widget.recovery && !widget.reauthenticate) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: email,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                  autofillHints: const [AutofillHints.email],
                  validator: InputRules.email,
                ),
              ],
              if (!widget.forgot) ...[
                const SizedBox(height: 12),
                TextFormField(
                  controller: password,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Password'),
                  autofillHints: [
                    signup ? AutofillHints.newPassword : AutofillHints.password,
                  ],
                  validator: signup || widget.recovery
                      ? InputRules.password
                      : (v) => v == null || v.isEmpty
                            ? 'Enter your password.'
                            : null,
                  onFieldSubmitted: (_) => submit(),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (message != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(message!, key: const Key('auth-message')),
          ),
        LGButton(
          label: busy
              ? 'Please wait…'
              : widget.reauthenticate
              ? 'Verify identity'
              : widget.forgot
              ? 'Send reset link'
              : widget.recovery
              ? 'Update password'
              : signup
              ? 'Create account'
              : 'Sign in',
          onPressed: busy ? null : () => submit(),
        ),
        if (!widget.forgot && !widget.recovery) ...[
          LGButton(
            label: 'Continue with Apple',
            secondary: true,
            onPressed: busy ? null : () => submit('apple'),
          ),
          LGButton(
            label: 'Continue with Google',
            secondary: true,
            onPressed: busy ? null : () => submit('google'),
          ),
          if (!widget.reauthenticate)
            TextButton(
              onPressed: () => setState(() => signup = !signup),
              child: Text(
                signup
                    ? 'Already have an account? Sign in'
                    : 'New here? Create an account',
              ),
            ),
          if (!widget.reauthenticate)
            TextButton(
              onPressed: () => context.push('/forgot-password'),
              child: const Text('Forgot password?'),
            ),
        ],
        const SizedBox(height: 16),
        const Text(
          'By continuing, you agree to the Terms and Privacy Policy. LeanGuard provides wellness support, not medical advice.',
          textAlign: TextAlign.center,
        ),
        Wrap(
          alignment: WrapAlignment.center,
          children: [
            TextButton(
              onPressed: () => context.push('/terms'),
              child: const Text('Terms'),
            ),
            TextButton(
              onPressed: () => context.push('/privacy'),
              child: const Text('Privacy'),
            ),
          ],
        ),
        if (!AppConfig.configured && !widget.reauthenticate)
          LGButton(
            label: 'Explore local preview',
            secondary: true,
            onPressed: () async {
              await ref.read(appProvider.notifier).enterDemo();
              if (context.mounted) context.go('/goals');
            },
          ),
      ],
    ),
  );
}

class EntryScreen extends ConsumerStatefulWidget {
  const EntryScreen({super.key, required this.kind});
  final String kind;
  @override
  ConsumerState<EntryScreen> createState() => _EntryScreenState();
}

class _EntryScreenState extends ConsumerState<EntryScreen> {
  final form = GlobalKey<FormState>();
  final value = TextEditingController(), name = TextEditingController();
  String type = 'waist', mealType = 'breakfast';
  bool busy = false;
  String? error;
  DateTime date = DateTime.now();
  @override
  void dispose() {
    value.dispose();
    name.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      final c = ref.read(appProvider.notifier);
      final s = ref.read(appProvider);
      final n = double.parse(value.text);
      switch (widget.kind) {
        case 'weight':
          await c.addWeight(s.units == 'lb' ? n / 2.2046226218 : n, date: date);
        case 'measurement':
          await c.addMeasurement(type, s.units == 'lb' ? n * 2.54 : n);
        case 'meal':
          await c.addMeal(name.text, n, mealType);
        case 'steps':
          await c.logWalk(n.toInt());
      }
      if (mounted) context.pop();
    } catch (e) {
      setState(
        () => error = e is FormatException
            ? e.message
            : e is StateError
            ? e.message
            : 'Could not save this entry. Try again.',
      );
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final weight = widget.kind == 'weight',
        meal = widget.kind == 'meal',
        measurement = widget.kind == 'measurement';
    final title = weight
        ? 'Add weight'
        : meal
        ? 'Add protein meal'
        : measurement
        ? 'Add measurement'
        : 'Log steps';
    final unit = weight
        ? s.units
        : meal
        ? 'g protein'
        : measurement
        ? s.units == 'lb'
              ? 'in'
              : 'cm'
        : 'steps';
    return LGPage(
      title: title,
      dark: false,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            weight
                ? 'One data point, not a judgment.'
                : meal
                ? 'Build your protein habit.'
                : measurement
                ? 'Track changes beyond the scale.'
                : 'Every bit of movement counts.',
            style: const TextStyle(fontSize: 25, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 22),
          Form(
            key: form,
            child: Column(
              children: [
                if (meal) ...[
                  TextFormField(
                    controller: name,
                    decoration: const InputDecoration(
                      labelText: 'Meal or food',
                    ),
                    maxLength: 120,
                    validator: (v) => v == null || v.trim().isEmpty
                        ? 'Name your meal.'
                        : null,
                  ),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: mealType,
                    decoration: const InputDecoration(labelText: 'Meal'),
                    items: ['breakfast', 'lunch', 'dinner', 'snack']
                        .map((e) => DropdownMenuItem(value: e, child: Text(e)))
                        .toList(),
                    onChanged: (v) => setState(() => mealType = v!),
                  ),
                  const SizedBox(height: 12),
                ],
                if (measurement) ...[
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: type,
                    decoration: const InputDecoration(labelText: 'Measurement'),
                    items:
                        (s.isPro
                                ? ['waist', 'hips', 'chest', 'arm', 'thigh']
                                : ['waist'])
                            .map(
                              (e) => DropdownMenuItem(value: e, child: Text(e)),
                            )
                            .toList(),
                    onChanged: (v) => setState(() => type = v!),
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  controller: value,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(labelText: unit),
                  validator: (v) => InputRules.number(
                    v,
                    min: weight ? 20 : 1,
                    max: meal
                        ? 200
                        : widget.kind == 'steps'
                        ? 100000
                        : 1000,
                  ),
                ),
                if (weight)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Recorded date'),
                    subtitle: Text(date.toLocal().toString().substring(0, 10)),
                    trailing: const Icon(Icons.calendar_today_outlined),
                    onTap: () async {
                      final d = await showDatePicker(
                        context: context,
                        firstDate: DateTime(2000),
                        lastDate: DateTime.now(),
                        initialDate: date,
                      );
                      if (d != null) setState(() => date = d);
                    },
                  ),
              ],
            ),
          ),
          if (error != null)
            Text(error!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 16),
          LGButton(
            label: busy ? 'Saving…' : 'Save entry',
            onPressed: busy ? null : save,
          ),
          if (measurement && !s.isPro)
            TextButton(
              onPressed: () => context.push('/paywall'),
              child: const Text('Track all measurements with Pro'),
            ),
        ],
      ),
    );
  }
}

class HealthPermissionScreen extends ConsumerWidget {
  const HealthPermissionScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final c = ref.read(appProvider.notifier);
    final health = ref.read(healthServiceProvider);
    final status = s.healthAccess;
    return LGPage(
      title: 'Connect your health',
      dark: false,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.favorite_outline, size: 64),
          const SizedBox(height: 24),
          const Text(
            'Your health. Your choice.',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Text(
            'Import steps and weight from ${health.isAppleHealth ? 'Apple Health' : 'Health Connect'}. ${s.isPro ? 'You can also share workouts and active energy. ' : ''}We use only the data you choose to support your habits. You can keep logging manually.',
          ),
          const SizedBox(height: 18),
          const LGCard(
            child: Text(
              'Health data is never sold or used for advertising. AI access is a separate opt-in. You can revoke access in your device health settings.',
            ),
          ),
          if (status == HealthAccess.denied)
            const Text(
              'Permission was denied. Manual logging still works. You can review permissions in Settings.',
            ),
          if (status == HealthAccess.unavailable)
            const Text(
              'Health integration is unavailable on this device or preview build.',
            ),
          if (status == HealthAccess.readAccessUnknown)
            const Text(
              'No shared data yet. Apple Health does not disclose read-permission decisions. Review sharing in Apple Health.',
            ),
          if (status == HealthAccess.authorized)
            const Text('Health data is connected. You choose what to share.'),
          if (s.error != null) Text(s.error!),
          if (s.isPro && status == HealthAccess.authorized)
            LGButton(
              label: 'Enable background health refresh',
              secondary: true,
              onPressed: () async {
                final ok = await c.enableBackgroundHealth();
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        ok
                            ? 'Background refresh enabled. Timing is controlled by your device.'
                            : 'Background refresh is unavailable or permission was denied.',
                      ),
                    ),
                  );
                }
              },
            ),
          LGButton(
            label: 'Choose what to share',
            onPressed: () => c.connectHealth(),
          ),
          LGButton(
            label: 'Review device permissions',
            secondary: true,
            onPressed: () => health.openSettings(),
          ),
          LGButton(
            label: s.onboardingComplete ? 'Done' : 'Continue',
            onPressed: () async {
              await c.finishOnboarding();
              if (context.mounted) context.go('/today');
            },
          ),
          TextButton(
            onPressed: () async {
              await c.finishOnboarding();
              if (context.mounted) context.go('/today');
            },
            child: const Text('Continue with manual logging'),
          ),
          if (status == HealthAccess.authorized)
            TextButton(
              onPressed: () => c.disconnectHealth(),
              child: const Text('Disconnect health data'),
            ),
        ],
      ),
    );
  }
}

class NotificationPermissionScreen extends ConsumerStatefulWidget {
  const NotificationPermissionScreen({super.key});
  @override
  ConsumerState<NotificationPermissionScreen> createState() =>
      _NotificationPermissionScreenState();
}

class _NotificationPermissionScreenState
    extends ConsumerState<NotificationPermissionScreen> {
  String? result;
  @override
  Widget build(BuildContext context) => LGPage(
    title: 'Helpful reminders',
    dark: false,
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.notifications_outlined, size: 70),
        const SizedBox(height: 24),
        const Text(
          'A gentle nudge, on your terms.',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 16),
        const Text(
          'Get optional workout, protein and walking reminders. Notification previews never contain your weight, medication details or coaching messages.',
        ),
        const SizedBox(height: 20),
        if (result != null) Text(result!),
        LGButton(
          label: 'Allow notifications',
          onPressed: () async {
            final ok = await ref
                .read(appProvider.notifier)
                .enableNotifications();
            if (mounted) {
              setState(
                () => result = ok
                    ? 'Notifications enabled. Set your reminders below.'
                    : 'Notifications are unavailable or permission was denied. You can continue without them.',
              );
            }
          },
        ),
        LGButton(
          label: 'Set my reminders',
          secondary: true,
          onPressed: () => context.push('/reminders'),
        ),
        TextButton(
          onPressed: () => context.go('/today'),
          child: const Text('Not now'),
        ),
      ],
    ),
  );
}

class WorkoutSummaryScreen extends ConsumerStatefulWidget {
  const WorkoutSummaryScreen({super.key});
  @override
  ConsumerState<WorkoutSummaryScreen> createState() =>
      _WorkoutSummaryScreenState();
}

class _WorkoutSummaryScreenState extends ConsumerState<WorkoutSummaryScreen> {
  bool sharing = false;
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider);
    final summary = state.lastWorkoutSummary;
    final workout = state.workouts
        .where(
          (row) =>
              row['id'] == summary?['workout_id'] &&
              row['status'] == 'completed',
        )
        .firstOrNull;
    final shared = workout?['health_exported_at'] != null;
    return LGPage(
      title: 'Workout complete',
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.check_circle_outline, size: 90, color: LG.lime),
          const SizedBox(height: 24),
          Text(
            summary == null ? 'Your next strong step.' : 'You showed up.',
            style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Text(
            summary?['workout_name']?.toString() ??
                'Start a workout to see your summary.',
          ),
          if (summary != null) ...[
            LGCard(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _stat(
                    '${((summary['duration_seconds'] as num) / 60).floor()}',
                    'minutes',
                  ),
                  _stat('${summary['sets']}', 'sets'),
                  _stat('${summary['exercises']}', 'exercises'),
                ],
              ),
            ),
            LGCard(
              child: Text(
                '${(summary['volume_kg'] as num).toStringAsFixed(0)} kg total volume recorded',
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (state.isPro && !state.demo && summary != null)
            LGButton(
              label: shared
                  ? 'Shared with Health'
                  : sharing
                  ? 'Sharing workout…'
                  : 'Share workout with Health',
              secondary: true,
              onPressed: shared || sharing || workout == null
                  ? null
                  : () async {
                      setState(() => sharing = true);
                      try {
                        await ref
                            .read(appProvider.notifier)
                            .syncWorkoutToHealth();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Workout shared with your health app.',
                              ),
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                e is StateError
                                    ? e.message
                                    : 'Could not share. Review your health permissions.',
                              ),
                            ),
                          );
                        }
                      } finally {
                        if (mounted) setState(() => sharing = false);
                      }
                    },
            ),
          LGButton(
            label: 'Back to Today',
            onPressed: () => context.go('/today'),
          ),
          LGButton(
            label: 'View my progress',
            secondary: true,
            onPressed: () => context.go('/progress'),
          ),
        ],
      ),
    );
  }

  Widget _stat(String n, String label) => Column(
    children: [
      Text(
        n,
        style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
      ),
      Text(label),
    ],
  );
}

class ExerciseDetailsScreen extends ConsumerWidget {
  const ExerciseDetailsScreen({super.key, required this.id});
  final String id;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(appProvider);
    final exercise = s.exercises.where((e) => e['id'] == id).firstOrNull;
    final history = ref.read(appProvider.notifier).history(id);
    return LGPage(
      title: exercise?['name'] ?? 'Exercise details',
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Icon(Icons.fitness_center, size: 100, color: LG.lime),
          const SizedBox(height: 24),
          Text(
            exercise?['equipment'] ?? '',
            style: const TextStyle(color: LG.lime),
          ),
          const SectionTitle('Technique'),
          for (final instruction
              in (exercise?['instructions'] is List
                  ? exercise!['instructions']
                  : ['Move through a comfortable range with control.']))
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Text(instruction.toString()),
            ),
          const LGCard(
            child: Text(
              'Start with a comfortable load. Stop if you feel pain or dizziness. Ask a qualified trainer if you are unsure of your technique.',
            ),
          ),
          const SectionTitle('Your exercise history'),
          if (history.isEmpty)
            const Text('No sets yet. Your logged sets will appear here.'),
          for (final set in history.reversed)
            ListTile(
              title: Text('${set['weight_kg']} kg × ${set['reps']} reps'),
              subtitle: Text(
                set['completed_at']?.toString().substring(0, 10) ?? '',
              ),
            ),
        ],
      ),
    );
  }
}

class ProfileEditScreen extends ConsumerStatefulWidget {
  const ProfileEditScreen({super.key, this.targets = false});
  final bool targets;
  @override
  ConsumerState<ProfileEditScreen> createState() => _ProfileEditScreenState();
}

class _ProfileEditScreenState extends ConsumerState<ProfileEditScreen> {
  final form = GlobalKey<FormState>();
  final name = TextEditingController(),
      protein = TextEditingController(),
      steps = TextEditingController(),
      workouts = TextEditingController(),
      allergies = TextEditingController(),
      diet = TextEditingController();
  String units = 'kg';
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    final s = ref.read(appProvider);
    name.text = s.name;
    units = s.units;
    protein.text = '${s.proteinTarget}';
    steps.text = '${s.stepTarget}';
    workouts.text = '${s.goalProfile['workouts_per_week'] ?? 3}';
    allergies.text = (s.goalProfile['allergies'] as List? ?? []).join(', ');
    diet.text = (s.goalProfile['dietary_preferences'] as List? ?? []).join(
      ', ',
    );
  }

  @override
  void dispose() {
    for (final c in [name, protein, steps, workouts, allergies, diet]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() => busy = true);
    try {
      final c = ref.read(appProvider.notifier);
      if (widget.targets) {
        await c.saveTargets(
          protein: int.parse(protein.text),
          steps: int.parse(steps.text),
          workouts: int.parse(workouts.text),
          allergies: allergies.text
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList(),
          dietaryPreferences: diet.text
              .split(',')
              .map((e) => e.trim())
              .where((e) => e.isNotEmpty)
              .toList(),
        );
      } else {
        await c.saveProfile(name: name.text, units: units);
      }
      if (mounted) context.pop();
    } catch (e) {
      setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => LGPage(
    title: widget.targets ? 'Goals & targets' : 'Your profile',
    dark: false,
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        Form(
          key: form,
          child: Column(
            children: widget.targets
                ? [
                    field(protein, 'Daily protein (g)', 20, 300),
                    field(steps, 'Daily steps', 500, 50000),
                    field(workouts, 'Workouts per week', 1, 7),
                    TextFormField(
                      controller: allergies,
                      decoration: const InputDecoration(
                        labelText: 'Food allergies (comma-separated)',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: diet,
                      decoration: const InputDecoration(
                        labelText: 'Dietary preferences',
                      ),
                    ),
                  ]
                : [
                    TextFormField(
                      controller: name,
                      decoration: const InputDecoration(labelText: 'Name'),
                      maxLength: 80,
                      validator: (v) => v == null || v.trim().isEmpty
                          ? 'Enter your name.'
                          : null,
                    ),
                    DropdownButtonFormField(
                      isExpanded: true,
                      initialValue: units,
                      items: const [
                        DropdownMenuItem(
                          value: 'kg',
                          child: Text('Metric • kg and cm'),
                        ),
                        DropdownMenuItem(
                          value: 'lb',
                          child: Text('Imperial • lb and in'),
                        ),
                      ],
                      onChanged: (v) => setState(() => units = v!),
                    ),
                  ],
          ),
        ),
        const SizedBox(height: 16),
        if (widget.targets)
          const Text(
            'Targets are personal preferences, not a prescription. Discuss nutrition or exercise restrictions with your clinician.',
          ),
        if (error != null) Text(error!),
        LGButton(
          label: busy ? 'Saving…' : 'Save changes',
          onPressed: busy ? null : save,
        ),
      ],
    ),
  );
  Widget field(TextEditingController c, String label, double min, double max) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: TextFormField(
          controller: c,
          decoration: InputDecoration(labelText: label),
          keyboardType: TextInputType.number,
          validator: (v) => int.tryParse(v ?? '') == null
              ? 'Enter a whole number.'
              : InputRules.number(v, min: min, max: max),
        ),
      );
}

class PrivacyScreen extends ConsumerStatefulWidget {
  const PrivacyScreen({super.key, this.terms = false});
  final bool terms;
  @override
  ConsumerState<PrivacyScreen> createState() => _PrivacyScreenState();
}

class _PrivacyScreenState extends ConsumerState<PrivacyScreen> {
  bool busy = false;
  String? message;
  Future<void> run(Future<void> Function() action) async {
    setState(() => busy = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        if (e is BackendException && e.status == 401) {
          final verified = await context.push<bool>('/reauth');
          if (mounted) {
            setState(
              () => message = verified == true
                  ? 'Identity verified. You can retry your request.'
                  : 'Verification was canceled. Verify your identity to retry this request.',
            );
          }
        } else {
          setState(
            () => message =
                'That request could not be completed. Try again when connected.',
          );
        }
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> export() async {
    final repo = ref.read(repositoryProvider);
    if (repo.isDemo) {
      final bytes = Uint8List.fromList(utf8.encode(jsonEncode(repo.records)));
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile.fromData(bytes, mimeType: 'application/json')],
          fileNameOverrides: ['leanguard-preview.json'],
        ),
      );
    } else if (repo.remote != null) {
      await DataExportService(repo).exportAndShare(
        sharePositionOrigin: const Rect.fromLTWH(0, 0, 100, 100),
      );
    }
    if (mounted) setState(() => message = 'Your export is ready.');
  }

  Future<void> delete() async {
    final confirm = TextEditingController();
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permanently delete account?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'This deletes your LeanGuard account and logs. Store subscriptions must be cancelled separately in Apple or Google subscription settings. Type DELETE to continue.',
            ),
            TextField(
              controller: confirm,
              decoration: const InputDecoration(labelText: 'Confirmation'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep account'),
          ),
          TextButton(
            onPressed: () {
              if (confirm.text == 'DELETE') Navigator.pop(context, true);
            },
            child: const Text('Delete permanently'),
          ),
        ],
      ),
    );
    confirm.dispose();
    if (approved != true) return;
    await run(() async {
      await ref.read(appProvider.notifier).deleteAccount();
      if (mounted) context.go('/welcome');
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(appProvider);
    final c = ref.read(appProvider.notifier);
    return LGPage(
      title: widget.terms ? 'Terms & wellness safety' : 'Privacy & your data',
      dark: false,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            widget.terms
                ? 'Support for your habits.'
                : 'You control your information.',
            style: const TextStyle(fontSize: 28, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 16),
          Text(
            widget.terms
                ? 'LeanGuard provides general fitness and wellness support for adults. It does not diagnose symptoms, prescribe treatment, or replace professional medical advice. Medication decisions, including GLP-1 dosing, belong with your prescribing clinician. Pause exercise for pain or dizziness; seek urgent care for fainting, severe weakness, dehydration or other severe symptoms.'
                : 'Your logs are stored in your account with access controls and an encrypted on-device cache. Health connections and AI processing are optional. AI sends relevant recent logs to a server-side provider only after your consent. We do not sell health data or use it for advertising.',
          ),
          const SizedBox(height: 16),
          if (!widget.terms) ...[
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('AI processing'),
              subtitle: const Text(
                'Allow recent logs and questions to be processed for coaching.',
              ),
              value: c.hasConsent('ai_processing'),
              onChanged: busy
                  ? null
                  : (v) => run(() => c.recordConsent('ai_processing', v)),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Anonymous product analytics'),
              subtitle: const Text(
                'Allowlisted app events only. No health values or messages.',
              ),
              value: s.profile['analytics_enabled'] == true,
              onChanged: busy
                  ? null
                  : (v) => run(
                      () => c.setPrivacy(
                        analytics: v,
                        diagnostics:
                            s.profile['crash_reporting_enabled'] == true,
                      ),
                    ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Privacy-safe diagnostics'),
              subtitle: const Text(
                'Error types only; no screenshots or personal data.',
              ),
              value: s.profile['crash_reporting_enabled'] == true,
              onChanged: busy
                  ? null
                  : (v) => run(
                      () => c.setPrivacy(
                        analytics: s.profile['analytics_enabled'] == true,
                        diagnostics: v,
                      ),
                    ),
            ),
            LGButton(
              label: 'Export all my data',
              secondary: true,
              onPressed: busy ? null : () => run(export),
            ),
            LGButton(
              label: 'Manage store subscription',
              secondary: true,
              onPressed: () => c.manageSubscription(),
            ),
            TextButton(
              onPressed: busy ? null : delete,
              child: const Text(
                'Delete my account',
                style: TextStyle(color: Colors.red),
              ),
            ),
          ],
          if (message != null) Text(message!),
          LGButton(
            label: 'Open full ${widget.terms ? 'terms' : 'privacy policy'}',
            secondary: true,
            onPressed: () async {
              final url = widget.terms
                  ? AppConfig.termsUrl
                  : AppConfig.privacyUrl;
              if (url.isEmpty) {
                setState(
                  () => message =
                      'The full policy URL has not been configured for this build.',
                );
                return;
              }
              await launchUrl(
                Uri.parse(url),
                mode: LaunchMode.externalApplication,
              );
            },
          ),
        ],
      ),
    );
  }
}

class QuietHoursScreen extends ConsumerStatefulWidget {
  const QuietHoursScreen({super.key});
  @override
  ConsumerState<QuietHoursScreen> createState() => _QuietHoursScreenState();
}

class _QuietHoursScreenState extends ConsumerState<QuietHoursScreen> {
  int start = 21, end = 8;
  String? error;
  @override
  Widget build(BuildContext context) => LGPage(
    title: 'Quiet hours',
    dark: false,
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.bedtime_outlined, size: 54),
        const SizedBox(height: 16),
        const Text(
          'Your time to switch off.',
          style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 20),
        DropdownButtonFormField(
          isExpanded: true,
          initialValue: start,
          decoration: const InputDecoration(labelText: 'Start'),
          items: List.generate(
            24,
            (i) => DropdownMenuItem(
              value: i,
              child: Text('${i.toString().padLeft(2, '0')}:00'),
            ),
          ),
          onChanged: (v) => setState(() => start = v!),
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField(
          isExpanded: true,
          initialValue: end,
          decoration: const InputDecoration(labelText: 'End'),
          items: List.generate(
            24,
            (i) => DropdownMenuItem(
              value: i,
              child: Text('${i.toString().padLeft(2, '0')}:00'),
            ),
          ),
          onChanged: (v) => setState(() => end = v!),
        ),
        if (error != null) Text(error!),
        LGButton(
          label: 'Save quiet hours',
          onPressed: () async {
            try {
              await ref.read(appProvider.notifier).setQuietHours(start, end);
              if (context.mounted) context.pop();
            } catch (e) {
              setState(() => error = 'Quiet hours are included with Pro.');
            }
          },
        ),
      ],
    ),
  );
}

class ReminderEditScreen extends ConsumerStatefulWidget {
  const ReminderEditScreen({super.key, this.id});
  final String? id;
  @override
  ConsumerState<ReminderEditScreen> createState() => _ReminderEditScreenState();
}

class _ReminderEditScreenState extends ConsumerState<ReminderEditScreen> {
  final title = TextEditingController();
  String kind = 'workout';
  TimeOfDay time = const TimeOfDay(hour: 18, minute: 0);
  final days = <int>{1, 4, 6};
  bool smart = false, busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    final row = ref
        .read(appProvider)
        .reminders
        .where((r) => r['id'] == widget.id)
        .firstOrNull;
    if (row != null) {
      title.text = row['title'];
      kind = row['kind'];
      final p = (row['time_of_day'] as String).split(':');
      time = TimeOfDay(hour: int.parse(p[0]), minute: int.parse(p[1]));
      days
        ..clear()
        ..addAll(List<int>.from(row['days_of_week']));
      smart = row['smart'] == true;
    }
  }

  @override
  void dispose() {
    title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LGPage(
    title: 'Add a reminder',
    dark: false,
    child: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        TextField(
          controller: title,
          maxLength: 100,
          decoration: const InputDecoration(labelText: 'Reminder name'),
        ),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: kind,
          decoration: const InputDecoration(labelText: 'Habit'),
          items: const [
            'workout',
            'protein',
            'walking',
            'weight',
            'hydration',
            'weekly',
          ].map((k) => DropdownMenuItem(value: k, child: Text(k))).toList(),
          onChanged: (v) => setState(() => kind = v!),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Time'),
          subtitle: Text(time.format(context)),
          trailing: const Icon(Icons.schedule),
          onTap: () async {
            final picked = await showTimePicker(
              context: context,
              initialTime: time,
            );
            if (picked != null) setState(() => time = picked);
          },
        ),
        Wrap(
          spacing: 8,
          children: List.generate(
            7,
            (i) => FilterChip(
              label: Text(['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][i]),
              selected: days.contains(i + 1),
              onSelected: (on) => setState(() {
                on ? days.add(i + 1) : days.remove(i + 1);
              }),
            ),
          ),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Smart reminder · Pro'),
          subtitle: const Text(
            'Only nudge when this habit needs attention. Requires push notifications.',
          ),
          value: smart,
          onChanged: (v) {
            if (!ref.read(appProvider).isPro) {
              context.push('/paywall');
              return;
            }
            setState(() => smart = v);
          },
        ),
        const Text(
          'Delivery can be delayed by your device. Notifications never show health values.',
        ),
        if (error != null) Text(error!),
        LGButton(
          label: busy ? 'Saving…' : 'Save reminder',
          onPressed: busy
              ? null
              : () async {
                  setState(() => busy = true);
                  try {
                    await ref
                        .read(appProvider.notifier)
                        .saveReminder(
                          id: widget.id,
                          title: title.text,
                          kind: kind,
                          hour: time.hour,
                          minute: time.minute,
                          days: days.toList()..sort(),
                          smart: smart,
                        );
                    if (context.mounted) context.pop();
                  } catch (e) {
                    setState(
                      () => error = e is StateError
                          ? e.message
                          : e is FormatException
                          ? e.message
                          : 'Could not save. Try again.',
                    );
                  } finally {
                    if (mounted) setState(() => busy = false);
                  }
                },
        ),
      ],
    ),
  );
}
