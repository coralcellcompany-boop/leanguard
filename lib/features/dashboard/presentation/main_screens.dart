import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/state.dart';
import 'design.dart';

String _number(num value) =>
    value.toStringAsFixed(value == value.roundToDouble() ? 0 : 1);
double _num(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
String _weight(double kg, String units) =>
    '${(units == 'lb' ? kg * 2.2046226218 : kg).toStringAsFixed(1)} $units';
String _date(dynamic value) {
  final date = DateTime.tryParse('$value');
  return date == null
      ? 'Not recorded'
      : '${['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][date.month - 1]} ${date.day}';
}

bool _today(dynamic value) {
  final date = DateTime.tryParse('$value')?.toLocal();
  final today = DateTime.now();
  return date != null &&
      date.year == today.year &&
      date.month == today.month &&
      date.day == today.day;
}

class TodayScreen extends ConsumerWidget {
  const TodayScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final now = DateTime.now();
    final name = state.name.trim().isEmpty
        ? 'you'
        : state.name.split(' ').first;
    final workoutDone = state.workouts.any(
      (w) => w['status'] == 'completed' && _today(w['started_at']),
    );
    final remainingProtein = math.max(
      0,
      state.proteinTarget - state.proteinToday,
    );
    final hasReadinessBaseline =
        state.activities.map((row) => row['date']).toSet().length >= 3;
    final reviews = [...state.rows('weekly_insights')]
      ..sort(
        (a, b) => '${b['week_start'] ?? b['created_at']}'.compareTo(
          '${a['week_start'] ?? a['created_at']}',
        ),
      );
    final recentContent = reviews.isEmpty ? null : reviews.first['content'];
    final recentSummary = recentContent is Map
        ? recentContent['summary']?.toString()
        : null;
    final upcoming =
        state.workouts.where((row) => row['status'] == 'planned').toList()
          ..sort(
            (a, b) => '${a['scheduled_date'] ?? ''}'.compareTo(
              '${b['scheduled_date'] ?? ''}',
            ),
          );
    final nextWorkout = state.activeWorkout ?? upcoming.firstOrNull;
    final nextTitle = '${nextWorkout?['name'] ?? 'Upper body'}';
    final nextMinutes = state.isPro
        ? (_num(state.goalProfile['session_minutes']) == 0
              ? 35
              : _num(state.goalProfile['session_minutes']).round())
        : 35;
    final nextExerciseCount = state
        .rows('workout_exercises')
        .where((row) => row['workout_id'] == nextWorkout?['id'])
        .length;
    return ScreenFrame(
      title: 'LeanGuard',
      tab: 0,
      actions: [
        IconButton(
          tooltip: 'Your profile',
          onPressed: () => context.go('/settings'),
          icon: CircleAvatar(
            radius: 17,
            backgroundColor: const Color(0xFF252D22),
            child: Text(
              name.substring(0, 1).toUpperCase(),
              style: const TextStyle(
                color: lime,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    eyebrow(
                      '${['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][now.weekday - 1]}, ${_date(now.toIso8601String())}',
                    ),
                    gap(5),
                    heading('Stay strong, $name.', size: 27),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Reminders',
                onPressed: () => context.push('/reminders'),
                icon: const Icon(Icons.notifications_none_rounded),
              ),
            ],
          ),
          gap(22),
          DesignCard(
            gradient: const LinearGradient(
              colors: [Color(0xFF20271E), Color(0xFF181D18)],
            ),
            onTap: state.isPro
                ? () => context.push('/coach')
                : () => context.push('/paywall'),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      eyebrow(
                        state.isPro
                            ? 'Today’s readiness'
                            : 'Your daily foundation',
                      ),
                      gap(7),
                      Text(
                        state.isPro
                            ? (!hasReadinessBaseline
                                  ? 'Building your baseline'
                                  : state.readiness >= 70
                                  ? 'Ready to build consistency'
                                  : 'A gentler day counts, too')
                            : 'Protect what makes you strong',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 15,
                        ),
                      ),
                      gap(5),
                      subtext(
                        state.isPro
                            ? (hasReadinessBaseline
                                  ? 'A habit signal from your recent logs.'
                                  : 'Log a few days to see your habit-based readiness.')
                            : 'Strength, protein and movement. One day at a time.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                state.isPro
                    ? RingStat(
                        value: state.readiness / 100,
                        label: hasReadinessBaseline
                            ? '${state.readiness}'
                            : '—',
                        caption: '/100',
                        size: 64,
                      )
                    : iconBox(
                        Icons.shield_outlined,
                        color: const Color(0xFF303F25),
                        foreground: lime,
                      ),
              ],
            ),
          ),
          gap(20),
          _WeekRow(workouts: state.workouts),
          if (state.isPro && state.riskFlag) ...[
            gap(18),
            DesignCard(
              color: const Color(0xFF30281D),
              border: const Color(0xFF735535),
              onTap: () => context.go('/coach'),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.info_outline_rounded, color: orange),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'A pattern worth reviewing',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: paper,
                          ),
                        ),
                        gap(6),
                        subtext(
                          'Your recent logs show faster weight loss alongside declining strength. Keep your plan steady and review these changes with your clinician.',
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          section('Today’s targets', trailing: subtext('3 habits')),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _TargetCard(
                  'Strength',
                  workoutDone ? 'Session complete' : nextTitle,
                  RingStat(
                    value: workoutDone ? 1 : 0,
                    label: workoutDone ? '✓' : '$nextMinutes',
                    caption: 'min',
                  ),
                  () => _startWorkout(context, ref, nextTitle),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _TargetCard(
                  'Protein',
                  '${_number(remainingProtein)}g to go',
                  RingStat(
                    value:
                        state.proteinToday / math.max(state.proteinTarget, 1),
                    label: _number(state.proteinToday),
                    caption: 'of ${state.proteinTarget}g',
                    color: orange,
                  ),
                  () => context.push('/protein'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _TargetCard(
                  'Steps',
                  '${math.max(0, state.stepTarget - state.steps)} to go',
                  RingStat(
                    value: state.steps / math.max(state.stepTarget, 1),
                    label: state.steps >= 1000
                        ? '${(state.steps / 1000).toStringAsFixed(1)}k'
                        : '${state.steps}',
                    caption: 'of ${_number(state.stepTarget / 1000)}k',
                    color: blue,
                  ),
                  () => context.push('/walking'),
                ),
              ),
            ],
          ),
          gap(20),
          _InsightCard(
            title: recentSummary != null
                ? 'Your latest weekly review'
                : state.isPro
                ? 'Your plan, explained.'
                : 'Your weekly check-in is here',
            body:
                recentSummary ??
                'Review your logged strength, weight, activity and protein with Lean Coach.',
            onTap: () => context.go('/coach'),
          ),
          section(
            'Up next',
            trailing: TextButton(
              onPressed: () => context.go('/plan'),
              child: const Text('View plan'),
            ),
          ),
          DesignCard(
            color: paper,
            onTap: () => _startWorkout(context, ref, nextTitle),
            child: Row(
              children: [
                Container(
                  width: 72,
                  height: 86,
                  decoration: BoxDecoration(
                    color: const Color(0xFFCBE86A),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.fitness_center_rounded,
                        size: 30,
                        color: ink,
                      ),
                      gap(10),
                      FittedBox(child: eyebrow('Strength', color: ink)),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      eyebrow(
                        'Strength · $nextMinutes min',
                        color: const Color(0xFF747B75),
                      ),
                      gap(6),
                      heading(nextTitle, size: 19, color: ink),
                      gap(6),
                      subtext(
                        '${nextExerciseCount == 0 ? state.exercises.length : nextExerciseCount} exercises',
                        color: const Color(0xFF747B75),
                      ),
                    ],
                  ),
                ),
                const CircleAvatar(
                  radius: 17,
                  backgroundColor: ink,
                  child: Icon(
                    Icons.arrow_forward_rounded,
                    color: paper,
                    size: 18,
                  ),
                ),
              ],
            ),
          ),
          gap(14),
          TextButton.icon(
            onPressed: () => context.push('/add-weight'),
            icon: const Icon(Icons.add_rounded),
            label: const Text('Log today’s weight'),
          ),
        ],
      ),
    );
  }
}

Future<void> _startWorkout(
  BuildContext context,
  WidgetRef ref, [
  String title = 'Upper body',
]) async {
  if (ref.read(appProvider).activeWorkout == null) {
    await ref.read(appProvider.notifier).startWorkout(title);
  }
  if (context.mounted) context.push('/workout');
}

class _TargetCard extends StatelessWidget {
  const _TargetCard(this.title, this.subtitle, this.ring, this.onTap);
  final String title, subtitle;
  final Widget ring;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => DesignCard(
    padding: 10,
    onTap: onTap,
    child: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(4),
          child: FittedBox(child: ring),
        ),
        gap(13),
        Text(
          title,
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
        ),
        gap(4),
        Text(
          subtitle,
          maxLines: 2,
          textAlign: TextAlign.center,
          style: const TextStyle(color: muted, fontSize: 10),
        ),
      ],
    ),
  );
}

class _WeekRow extends StatelessWidget {
  const _WeekRow({required this.workouts});
  final List<Map<String, dynamic>> workouts;
  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final monday = DateTime(
      now.year,
      now.month,
      now.day,
    ).subtract(Duration(days: now.weekday - 1));
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: List.generate(7, (i) {
        final date = monday.add(Duration(days: i));
        final done = workouts.any((w) {
          final recorded = DateTime.tryParse('${w['started_at']}')?.toLocal();
          return w['status'] == 'completed' &&
              recorded?.year == date.year &&
              recorded?.month == date.month &&
              recorded?.day == date.day;
        });
        final today = i == now.weekday - 1;
        return Column(
          children: [
            Text(
              ['M', 'T', 'W', 'T', 'F', 'S', 'S'][i],
              style: const TextStyle(color: muted, fontSize: 10),
            ),
            gap(8),
            Container(
              width: 31,
              height: 31,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: today
                    ? lime
                    : done
                    ? const Color(0xFF2B3525)
                    : Colors.transparent,
              ),
              child: done
                  ? Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: today ? ink : lime,
                    )
                  : Text(
                      '${date.day}',
                      style: TextStyle(
                        color: today ? ink : muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
            ),
          ],
        );
      }),
    );
  }
}

class _InsightCard extends StatelessWidget {
  const _InsightCard({
    required this.title,
    required this.body,
    required this.onTap,
  });
  final String title, body;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => DesignCard(
    border: const Color(0xFF3B4932),
    gradient: const LinearGradient(
      colors: [Color(0xFF222B1F), Color(0xFF192019)],
    ),
    onTap: onTap,
    child: Row(
      children: [
        iconBox(Icons.auto_awesome_rounded),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              eyebrow('Lean Coach insight', color: lime),
              gap(5),
              Text(
                title,
                style: const TextStyle(
                  color: paper,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
              gap(5),
              subtext(body),
            ],
          ),
        ),
        const Icon(Icons.chevron_right_rounded, color: paper),
      ],
    ),
  );
}

class PlanScreen extends ConsumerWidget {
  const PlanScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final activePlan = state
        .rows('strength_plans')
        .where((plan) => plan['is_active'] == true)
        .firstOrNull;
    final planned =
        state.workouts
            .where(
              (workout) =>
                  workout['status'] == 'planned' ||
                  workout['status'] == 'in_progress',
            )
            .toList()
          ..sort(
            (a, b) => '${a['scheduled_date'] ?? ''}'.compareTo(
              '${b['scheduled_date'] ?? ''}',
            ),
          );
    final completed = state.workouts
        .where(
          (workout) =>
              workout['status'] == 'completed' &&
              (activePlan == null || workout['plan_id'] == activePlan['id']),
        )
        .length;
    final trainingDays = List<int>.from(
      state.goalProfile['training_days'] ?? [1, 4, 6],
    );
    final frequency = state.isPro ? math.max(1, trainingDays.length) : 3;
    final minutes = state.isPro
        ? (_num(state.goalProfile['session_minutes']) == 0
              ? 35
              : _num(state.goalProfile['session_minutes']).round())
        : 35;
    final durationLabel = state.isPro ? '$minutes min' : '35–40 min';
    final slots = planned.map((workout) {
      final date = DateTime.tryParse('${workout['scheduled_date']}');
      return (
        date == null
            ? 'NEXT'
            : ['MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT', 'SUN'][date.weekday -
                  1],
        '${workout['name'] ?? 'Strength session'}',
        workout['status'] == 'in_progress'
            ? 'In progress · Resume session'
            : '$durationLabel · ${date == null ? 'Start when ready' : _date(date.toIso8601String())}',
        workout['status'] == 'in_progress',
      );
    }).toList();
    return ScreenFrame(
      title: 'Strength plan',
      tab: 1,
      actions: [
        IconButton(
          tooltip: 'Plan preferences',
          onPressed: () => context.push('/personalization'),
          icon: const Icon(Icons.tune_rounded),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DesignCard(
            gradient: const LinearGradient(
              colors: [Color(0xFF283723), Color(0xFF171D18)],
            ),
            border: const Color(0xFF34452E),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                eyebrow(
                  state.isPro
                      ? 'Your personalized plan'
                      : 'Your starter 4-week plan',
                  color: lime,
                ),
                gap(10),
                heading(
                  '${activePlan?['name'] ?? 'Muscle retention foundation'}',
                  size: 30,
                ),
                gap(20),
                if ('${activePlan?['description'] ?? ''}'.isNotEmpty) ...[
                  subtext('${activePlan!['description']}'),
                  gap(16),
                ],
                Wrap(
                  spacing: 20,
                  runSpacing: 8,
                  children: [
                    _Meta(
                      Icons.calendar_today_outlined,
                      '$frequency days/week',
                    ),
                    _Meta(Icons.timer_outlined, durationLabel),
                  ],
                ),
                gap(20),
                ClipRRect(
                  borderRadius: BorderRadius.circular(5),
                  child: LinearProgressIndicator(
                    value: (completed / (frequency * 4)).clamp(0, 1),
                    color: lime,
                    backgroundColor: const Color(0xFF343B34),
                    minHeight: 6,
                  ),
                ),
                gap(9),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: subtext(
                        'Week ${math.min(4, completed ~/ frequency + 1)} of 4',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Flexible(child: subtext('$completed workouts logged')),
                  ],
                ),
              ],
            ),
          ),
          section(
            'Upcoming sessions',
            trailing: const Icon(
              Icons.calendar_month_outlined,
              size: 18,
              color: muted,
            ),
          ),
          if (slots.isEmpty)
            DesignCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your next session starts here.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  gap(8),
                  subtext(
                    'Start a session or review your training preferences.',
                  ),
                  gap(14),
                  PrimaryAction(
                    'Start a strength session',
                    onPressed: () => _startWorkout(context, ref),
                  ),
                ],
              ),
            ),
          for (final entry in slots)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: DesignCard(
                border: entry.$4 || entry == slots.first
                    ? const Color(0xFF627D3B)
                    : null,
                color: entry.$4 || entry == slots.first
                    ? const Color(0xFF20271D)
                    : null,
                onTap: () => _startWorkout(context, ref, entry.$2),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFF2C3428),
                        borderRadius: BorderRadius.circular(11),
                      ),
                      child: Text(
                        entry.$1,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            entry.$2,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          gap(4),
                          subtext(entry.$3),
                        ],
                      ),
                    ),
                    const Icon(Icons.play_circle_fill_rounded, color: lime),
                  ],
                ),
              ),
            ),
          gap(7),
          DesignCard(
            color: const Color(0xFF29241B),
            border: const Color(0xFF4B412B),
            onTap: () => context.push(state.isPro ? '/coach' : '/paywall'),
            child: Row(
              children: [
                iconBox(
                  Icons.bolt_rounded,
                  color: const Color(0xFF4A3D25),
                  foreground: orange,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      eyebrow('Progressive overload', color: orange),
                      gap(5),
                      const Text(
                        'Make your next step a smart one',
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                      gap(5),
                      subtext(
                        state.isPro
                            ? 'Review conservative changes with your coach.'
                            : 'Personalized progression with Pro.',
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, size: 18),
              ],
            ),
          ),
          section('Plan focus'),
          DesignCard(
            child: Column(
              children: [
                const _FocusRow(
                  Icons.fitness_center_rounded,
                  'Preserve strength',
                  'High',
                ),
                const Divider(),
                const _FocusRow(
                  Icons.monitor_heart_outlined,
                  'Manage fatigue',
                  'Balanced',
                ),
                const Divider(),
                _FocusRow(
                  Icons.timer_outlined,
                  'Weekly sessions',
                  '$frequency sessions',
                ),
              ],
            ),
          ),
          section('Exercise library'),
          for (final exercise in state.exercises)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.fitness_center_rounded, color: lime),
              title: Text('${exercise['name']}'),
              subtitle: Text(
                '${exercise['sets']} sets · ${exercise['reps']} reps',
                style: const TextStyle(color: muted),
              ),
              trailing: const Icon(Icons.chevron_right_rounded),
              onTap: () => context.push('/exercise/${exercise['id']}'),
            ),
        ],
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta(this.icon, this.text);
  final IconData icon;
  final String text;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 16, color: muted),
      const SizedBox(width: 6),
      Text(text, style: const TextStyle(color: muted, fontSize: 12)),
    ],
  );
}

class _FocusRow extends StatelessWidget {
  const _FocusRow(this.icon, this.text, this.value);
  final IconData icon;
  final String text, value;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 5),
    child: Row(
      children: [
        Icon(icon, size: 20),
        const SizedBox(width: 11),
        Expanded(child: Text(text, style: const TextStyle(fontSize: 13))),
        Text(value, style: const TextStyle(fontSize: 12, color: muted)),
      ],
    ),
  );
}

class WalkingScreen extends ConsumerWidget {
  const WalkingScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final left = math.max(0, state.stepTarget - state.steps);
    return ScreenFrame(
      title: 'Walking',
      dark: false,
      tab: 0,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Column(
              children: [
                gap(18),
                eyebrow('Today', color: const Color(0xFF697268)),
                gap(8),
                heading('${state.steps}', size: 56),
                gap(6),
                subtext(
                  'of ${state.stepTarget} steps',
                  color: const Color(0xFF777E77),
                ),
                gap(24),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: (state.steps / math.max(1, state.stepTarget)).clamp(
                      0,
                      1,
                    ),
                    minHeight: 10,
                    color: blue,
                    backgroundColor: const Color(0xFFDDE1D9),
                  ),
                ),
                gap(14),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.directions_walk_rounded,
                      size: 18,
                      color: Color(0xFF657078),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: subtext(
                        '$left steps left · about ${(left / 110).ceil()} min',
                        color: const Color(0xFF657078),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          section('This week'),
          DesignCard(
            child: Column(
              children: [
                SizedBox(
                  height: 128,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisAlignment: MainAxisAlignment.spaceAround,
                    children: List.generate(7, (index) {
                      final now = DateTime.now();
                      final date = DateTime(now.year, now.month, now.day)
                          .subtract(Duration(days: now.weekday - 1))
                          .add(Duration(days: index));
                      final isToday = index == now.weekday - 1;
                      final day = date.toIso8601String().substring(0, 10);
                      final logged = state.activities.where(
                        (a) => a['date'] == day,
                      );
                      final value = logged.isEmpty
                          ? 0
                          : _num(logged.first['steps']).round();
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          if (isToday)
                            Text(
                              '$value',
                              style: const TextStyle(fontSize: 10),
                            ),
                          gap(5),
                          Container(
                            width: 15,
                            height: math.max(
                              4,
                              92 *
                                  (value / math.max(state.stepTarget, 1)).clamp(
                                    0,
                                    1,
                                  ),
                            ),
                            decoration: BoxDecoration(
                              color: isToday ? blue : const Color(0xFFDDE1D9),
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          gap(8),
                          Text(
                            ['M', 'T', 'W', 'T', 'F', 'S', 'S'][index],
                            style: const TextStyle(
                              fontSize: 11,
                              color: Color(0xFF747B75),
                            ),
                          ),
                        ],
                      );
                    }),
                  ),
                ),
                gap(12),
                subtext(
                  'Connect health data to keep your activity up to date.',
                  color: const Color(0xFF747B75),
                ),
              ],
            ),
          ),
          gap(16),
          DesignCard(
            color: const Color(0xFFE5F4F5),
            border: const Color(0xFFE5F4F5),
            onTap: state.isPro
                ? () => context.push('/adaptive-insights')
                : () => context.push('/paywall'),
            child: Row(
              children: [
                iconBox(
                  Icons.my_location_rounded,
                  color: const Color(0xFFC6ECF2),
                  foreground: const Color(0xFF15546C),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        state.isPro
                            ? 'Your target can adapt'
                            : 'Make movement a daily habit',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      gap(5),
                      subtext(
                        state.isPro
                            ? 'Review gradual changes with your coach as consistency improves.'
                            : 'A fixed daily target is included. Unlock adaptive suggestions with Pro.',
                        color: const Color(0xFF687174),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          section('Quick walks'),
          for (final minutes in [10, 20])
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: DesignCard(
                onTap: () => _walk(context, ref, minutes),
                child: Row(
                  children: [
                    Container(
                      width: 46,
                      height: 46,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: const Color(0xFFD5F2F7),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '$minutes',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 20,
                          color: Color(0xFF1E5263),
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            minutes == 10 ? 'Movement break' : 'Brisk walk',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          gap(4),
                          subtext(
                            '$minutes minutes · log your steps after',
                            color: const Color(0xFF747B75),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_rounded, size: 19),
                  ],
                ),
              ),
            ),
          gap(10),
          PrimaryAction(
            'Connect health data',
            dark: true,
            onPressed: () => context.push('/health-permission'),
          ),
        ],
      ),
    );
  }

  Future<void> _walk(BuildContext context, WidgetRef ref, int minutes) async {
    final steps = await showDialog<int>(
      context: context,
      builder: (context) => _WalkLogDialog(minutes: minutes),
    );
    if (steps != null) {
      await ref.read(appProvider.notifier).addWalkSteps(steps);
      if (context.mounted) showMessage(context, '$steps steps logged.');
    }
  }
}

class _WalkLogDialog extends StatefulWidget {
  const _WalkLogDialog({required this.minutes});
  final int minutes;
  @override
  State<_WalkLogDialog> createState() => _WalkLogDialogState();
}

class _WalkLogDialogState extends State<_WalkLogDialog> {
  final controller = TextEditingController();
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${widget.minutes}-minute walk'),
    content: Form(
      key: form,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'After your walk, enter the steps you completed. Health imports will reconcile your daily total.',
          ),
          gap(16),
          TextFormField(
            controller: controller,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Steps completed',
              hintText: '1100',
            ),
            validator: (input) {
              final value = int.tryParse(input ?? '');
              return value != null && value > 0 && value <= 100000
                  ? null
                  : 'Enter 1–100,000 steps.';
            },
          ),
        ],
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('Cancel'),
      ),
      TextButton(
        onPressed: () {
          if (form.currentState!.validate()) {
            Navigator.pop(context, int.parse(controller.text));
          }
        },
        child: const Text('Log walk'),
      ),
    ],
  );
}

class ProteinScreen extends ConsumerWidget {
  const ProteinScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final grams = state.proteinToday;
    final ratio = grams / math.max(state.proteinTarget, 1);
    final meals = state.meals
        .where((m) => _today(m['logged_at'] ?? m['created_at']))
        .toList();
    return ScreenFrame(
      title: 'Protein',
      dark: false,
      tab: 0,
      actions: [
        IconButton(
          tooltip: 'Protein target',
          onPressed: () => context.push('/targets'),
          icon: const Icon(Icons.tune_rounded),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DesignCard(
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      eyebrow(
                        'Today’s protein',
                        color: const Color(0xFF8E6849),
                      ),
                      gap(12),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: _number(grams),
                              style: const TextStyle(
                                fontSize: 48,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -1.7,
                              ),
                            ),
                            const TextSpan(
                              text: 'g',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                      subtext(
                        'of ${state.proteinTarget}g target',
                        color: const Color(0xFF777E77),
                      ),
                    ],
                  ),
                ),
                RingStat(
                  value: ratio,
                  label: '${(ratio * 100).round()}%',
                  caption: 'complete',
                  color: orange,
                  size: 100,
                ),
              ],
            ),
          ),
          gap(12),
          DesignCard(
            color: const Color(0xFFFFF2E6),
            border: const Color(0xFFFFF2E6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_number(math.max(0, state.proteinTarget - grams))}g left today',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                gap(4),
                subtext(
                  'Build your day around satisfying, protein-first meals.',
                  color: const Color(0xFF8B6F5B),
                ),
              ],
            ),
          ),
          section(
            'Meals',
            trailing: TextButton.icon(
              onPressed: () => context.push('/add-meal'),
              icon: const Icon(Icons.add_rounded, size: 17),
              label: const Text('Add'),
            ),
          ),
          DesignCard(
            child: Column(
              children: [
                if (meals.isEmpty) ...[
                  const Icon(
                    Icons.restaurant_outlined,
                    size: 36,
                    color: Color(0xFFA2AA9A),
                  ),
                  gap(12),
                  const Text(
                    'Your first meal starts here.',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  gap(5),
                  subtext(
                    'Add a meal and its protein to track today’s target.',
                    color: const Color(0xFF747B75),
                  ),
                  gap(14),
                ],
                for (final meal in meals) ...[
                  Row(
                    children: [
                      iconBox(
                        Icons.restaurant_rounded,
                        color: const Color(0xFFF2F2EC),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${meal['name'] ?? meal['meal_name'] ?? 'Meal'}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            gap(4),
                            subtext(
                              '${meal['meal_type'] ?? 'Logged meal'}',
                              color: const Color(0xFF7A817A),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${_number(_num(meal['protein_grams'] ?? meal['protein_g']))}g',
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                ],
                InkWell(
                  onTap: () => context.push('/add-meal'),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        iconBox(
                          Icons.add_rounded,
                          color: const Color(0xFFE4E7DF),
                        ),
                        const SizedBox(width: 12),
                        const Text(
                          'Add a meal',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          gap(18),
          DesignCard(
            color: const Color(0xFFEDF0E8),
            onTap: () =>
                context.push(state.isPro ? '/adaptive-insights' : '/paywall'),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.restaurant_outlined, color: Color(0xFF6A813D)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      eyebrow(
                        state.isPro
                            ? 'Protein-first ideas'
                            : 'Protein planner · Pro',
                        color: const Color(0xFF627547),
                      ),
                      gap(6),
                      subtext(
                        state.isPro
                            ? 'Get meal ideas around your remaining target, preferences and appetite.'
                            : 'Personalized meal suggestions and protein distribution insights.',
                        color: const Color(0xFF58634D),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ProgressScreen extends ConsumerStatefulWidget {
  const ProgressScreen({super.key});
  @override
  ConsumerState<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends ConsumerState<ProgressScreen> {
  String period = '4W';
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider);
    final all = [...state.weights]
      ..sort((a, b) => '${a['recorded_at']}'.compareTo('${b['recorded_at']}'));
    final days = {'4W': 28, '3M': 90, '6M': 180, '1Y': 365}[period]!;
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final entries = all
        .where(
          (w) =>
              DateTime.tryParse('${w['recorded_at']}')?.isAfter(cutoff) ?? true,
        )
        .toList();
    final values = entries.map((w) => _num(w['weight_kg'])).toList();
    final chartValues = state.isPro
        ? List<double>.generate(values.length, (index) {
            final window = values.sublist(math.max(0, index - 2), index + 1);
            return window.reduce((a, b) => a + b) / window.length;
          })
        : values;
    final latest = all.isEmpty ? null : _num(all.last['weight_kg']);
    final change = values.length < 2 ? null : values.last - values.first;
    return ScreenFrame(
      title: 'Progress',
      tab: 2,
      actions: [
        IconButton(
          tooltip: 'Add weight',
          onPressed: () => context.push('/add-weight'),
          icon: const Icon(Icons.add_rounded),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFF242824),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(
              children: [
                for (final tab in ['4W', '3M', '6M', '1Y'])
                  Expanded(
                    child: TextButton(
                      style: TextButton.styleFrom(
                        backgroundColor: period == tab
                            ? const Color(0xFF3A4235)
                            : Colors.transparent,
                        foregroundColor: period == tab ? lime : muted,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(9),
                        ),
                      ),
                      onPressed: () => tab == '4W' || state.isPro
                          ? setState(() => period = tab)
                          : context.push('/paywall'),
                      child: Text(tab),
                    ),
                  ),
              ],
            ),
          ),
          gap(16),
          DesignCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          eyebrow('Body weight'),
                          gap(7),
                          heading(
                            latest == null
                                ? 'No entries yet'
                                : _weight(latest, state.units),
                            size: 29,
                          ),
                        ],
                      ),
                    ),
                    if (change != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF25301F),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Text(
                          '${change > 0 ? '+' : ''}${_weight(change, state.units)}',
                          style: const TextStyle(color: lime, fontSize: 12),
                        ),
                      ),
                  ],
                ),
                gap(9),
                TrendChart(chartValues),
                if (state.isPro && values.length >= 2) ...[
                  gap(6),
                  const Text(
                    'Smoothed trend · 3-entry average',
                    style: TextStyle(fontSize: 10, color: muted),
                  ),
                  gap(8),
                ],
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    subtext(
                      entries.isEmpty
                          ? 'Start today'
                          : _date(entries.first['recorded_at']),
                    ),
                    subtext(
                      entries.isEmpty ? '' : _date(entries.last['recorded_at']),
                    ),
                  ],
                ),
              ],
            ),
          ),
          gap(12),
          Row(
            children: [
              Expanded(
                child: DesignCard(
                  onTap: () => context.push('/measurements'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      eyebrow('Measurements'),
                      gap(10),
                      heading('Waist', size: 23),
                      gap(6),
                      const Text(
                        'View your check-ins',
                        style: TextStyle(color: lime, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DesignCard(
                  onTap: () => _workoutHistory(context, state.workouts),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      eyebrow('Strength'),
                      gap(10),
                      heading(
                        state.isPro
                            ? (state.strengthChangePercent == null
                                  ? '—'
                                  : '${state.strengthChangePercent! >= 0 ? '+' : ''}${state.strengthChangePercent!.toStringAsFixed(1)}%')
                            : '${state.completedWorkouts}',
                        size: 23,
                      ),
                      gap(6),
                      Text(
                        state.isPro
                            ? (state.strengthChangePercent == null
                                  ? 'Log comparable sessions'
                                  : 'From comparable sessions')
                            : 'Workouts completed',
                        style: TextStyle(color: lime, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          section('Weekly check-in'),
          DesignCard(
            child: Column(
              children: [
                _check(
                  'Weight entries',
                  '${entries.length} logged',
                  'Keep a routine',
                ),
                const Divider(),
                _check(
                  'Strength sessions',
                  '${state.completedWorkouts} completed',
                  'Keep building',
                ),
                const Divider(),
                _check(
                  'Consistency',
                  '${_number(state.consistency)}%',
                  'Your habits matter',
                ),
              ],
            ),
          ),
          gap(18),
          _InsightCard(
            title: 'See the bigger picture.',
            body: 'Review strength retention and your next week’s actions.',
            onTap: () => context.go('/coach'),
          ),
          gap(14),
          Row(
            children: [
              Expanded(
                child: TextButton.icon(
                  onPressed: () => context.push('/add-weight'),
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Add weight'),
                ),
              ),
              Expanded(
                child: TextButton.icon(
                  onPressed: () => _weightHistory(context, all, state.units),
                  icon: const Icon(Icons.history_rounded),
                  label: const Text('All your entries'),
                ),
              ),
            ],
          ),
          Center(
            child: TextButton.icon(
              onPressed: () => context.push('/reports'),
              icon: const Icon(Icons.summarize_outlined),
              label: const Text('Your reports'),
            ),
          ),
          Center(
            child: TextButton.icon(
              onPressed: () =>
                  context.push(state.isPro ? '/adaptive-insights' : '/paywall'),
              icon: const Icon(Icons.insights_outlined),
              label: const Text('Adaptive insights'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _check(String title, String value, String label) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 7),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              eyebrow(title),
              gap(5),
              Text(value, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
        ),
        Text(label, style: const TextStyle(color: muted, fontSize: 10)),
      ],
    ),
  );
  void _weightHistory(
    BuildContext context,
    List<Map<String, dynamic>> entries,
    String units,
  ) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          heading('Your weight entries', size: 24),
          gap(),
          subtext('Your existing records are always yours to access.'),
          if (entries.isEmpty) ...[gap(), const Text('No entries yet.')],
          for (final w in entries.reversed)
            ListTile(
              title: Text(_weight(_num(w['weight_kg']), units)),
              subtitle: Text(_date(w['recorded_at'])),
            ),
        ],
      ),
    ),
  );
  void _workoutHistory(
    BuildContext context,
    List<Map<String, dynamic>> workouts,
  ) => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          heading('Workout history', size: 24),
          gap(),
          if (workouts.isEmpty)
            const Text('Your completed sessions will appear here.'),
          for (final workout in workouts.reversed)
            ListTile(
              leading: const Icon(Icons.fitness_center_rounded),
              title: Text(
                '${workout['name'] ?? workout['title'] ?? 'Strength workout'}',
              ),
              subtitle: Text(
                '${_date(workout['started_at'])} · ${workout['status']}',
              ),
            ),
        ],
      ),
    ),
  );
}

class MeasurementsScreen extends ConsumerWidget {
  const MeasurementsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final entries = [...state.measurements]
      ..sort((a, b) => '${a['recorded_at']}'.compareTo('${b['recorded_at']}'));
    String value(String key) {
      for (final entry in entries.reversed) {
        final raw =
            entry['${key}_cm'] ??
            (entry['type'] == key ? entry['value'] : null);
        if (raw != null) {
          final cm = _num(raw);
          return state.units == 'lb'
              ? '${(cm / 2.54).toStringAsFixed(1)} in'
              : '${cm.toStringAsFixed(1)} cm';
        }
      }
      return '—';
    }

    return ScreenFrame(
      title: 'Measurements',
      dark: false,
      back: true,
      actions: [
        IconButton(
          tooltip: 'Add measurements',
          onPressed: () => context.push('/add-measurement'),
          icon: const Icon(Icons.add_rounded),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DesignCard(
            color: const Color(0xFFE4E7DF),
            border: const Color(0xFFE4E7DF),
            padding: 13,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.calendar_today_outlined,
                  size: 17,
                  color: Color(0xFF626A63),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    entries.isEmpty
                        ? 'Your first check-in'
                        : 'Latest · ${_date(entries.last['recorded_at'])}',
                    style: const TextStyle(
                      color: Color(0xFF626A63),
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
          gap(14),
          Container(
            height: 240,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              gradient: const RadialGradient(
                colors: [Color(0xFFE1E9D8), Color(0xFFEFF1EB)],
              ),
            ),
            child: Stack(
              children: [
                const Center(
                  child: Icon(
                    Icons.accessibility_new_rounded,
                    size: 226,
                    color: Color(0xFFB1BFAB),
                  ),
                ),
                Positioned(
                  left: 18,
                  top: 70,
                  child: _mapLabel('Chest', value('chest')),
                ),
                Positioned(
                  right: 20,
                  top: 125,
                  child: _mapLabel('Waist', value('waist')),
                ),
                Positioned(
                  left: 24,
                  top: 173,
                  child: _mapLabel('Hips', value('hips')),
                ),
              ],
            ),
          ),
          section('Latest measurements'),
          DesignCard(
            child: Column(
              children: [
                for (final item in [
                  ('Waist', 'waist'),
                  ('Hips', 'hips'),
                  ('Chest', 'chest'),
                  ('Arm', 'arm'),
                  ('Thigh', 'thigh'),
                ]) ...[
                  InkWell(
                    onTap: () => context.push(
                      item.$2 == 'waist' || state.isPro
                          ? '/add-measurement'
                          : '/paywall',
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.$1,
                              style: const TextStyle(
                                color: Color(0xFF727A72),
                                fontSize: 13,
                              ),
                            ),
                          ),
                          Text(
                            value(item.$2),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(width: 20),
                          Icon(
                            item.$2 != 'waist' && !state.isPro
                                ? Icons.lock_outline_rounded
                                : Icons.chevron_right_rounded,
                            size: 18,
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (item.$2 != 'thigh') const Divider(height: 1),
                ],
              ],
            ),
          ),
          gap(18),
          PrimaryAction(
            'Add measurements',
            dark: true,
            icon: Icons.add_rounded,
            onPressed: () => context.push('/add-measurement'),
          ),
          gap(14),
          Center(
            child: TextButton.icon(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                showDragHandle: true,
                builder: (context) => SafeArea(
                  child: ListView(
                    padding: const EdgeInsets.all(20),
                    children: [
                      heading('All saved measurements', size: 23),
                      gap(),
                      if (entries.isEmpty) const Text('No measurements yet.'),
                      for (final entry in entries.reversed)
                        ListTile(
                          title: Text(_date(entry['recorded_at'])),
                          subtitle: Text(
                            entry.entries
                                .where(
                                  (e) =>
                                      e.key.endsWith('_cm') && e.value != null,
                                )
                                .map(
                                  (e) =>
                                      '${e.key.replaceAll('_cm', '')}: ${e.value} cm',
                                )
                                .join(' · '),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              icon: const Icon(Icons.history_rounded, size: 18),
              label: const Text('All saved measurements'),
            ),
          ),
          Center(
            child: subtext(
              'You control your health data in Privacy & data.',
              color: const Color(0xFF7D847E),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mapLabel(String title, String value) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        title,
        style: const TextStyle(color: Color(0xFF737B73), fontSize: 11),
      ),
      gap(3),
      Text(
        value,
        style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      ),
    ],
  );
}

class RemindersScreen extends ConsumerWidget {
  const RemindersScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    const reminders = [
      (
        'workout',
        'Workout reminder',
        'Mon, Thu, Sat · 6:00 PM',
        Icons.fitness_center_rounded,
      ),
      (
        'protein',
        'Protein check-in',
        'Daily · 2:00 PM',
        Icons.restaurant_outlined,
      ),
      (
        'walking',
        'Walking nudge',
        'When behind target · Pro',
        Icons.directions_walk_rounded,
      ),
      ('weekly', 'Weekly review', 'Sunday · 9:00 AM', Icons.show_chart_rounded),
    ];
    final defaultRows = <String, Map<String, dynamic>?>{
      for (final reminder in reminders)
        reminder.$1: state.reminders
            .where(
              (row) => row['kind'] == reminder.$1 || row['id'] == reminder.$1,
            )
            .firstOrNull,
    };
    final coveredIds = defaultRows.values
        .whereType<Map<String, dynamic>>()
        .map((row) => row['id'])
        .toSet();
    final extraRows = state.reminders
        .where((row) => !coveredIds.contains(row['id']))
        .toList();
    return ScreenFrame(
      title: 'Smart reminders',
      dark: false,
      back: true,
      actions: [
        IconButton(
          tooltip: 'Add reminder',
          onPressed: () => context.push(
            !state.isPro &&
                    state.reminders
                            .where((row) => row['enabled'] == true)
                            .length >=
                        3
                ? '/paywall'
                : '/reminder-edit',
          ),
          icon: const Icon(Icons.add_rounded),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DesignCard(
            color: const Color(0xFFE9F1DC),
            border: const Color(0xFFE9F1DC),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.notifications_none_rounded,
                  color: Color(0xFF4E672C),
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Helpful, never noisy.',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      gap(5),
                      subtext(
                        state.isPro
                            ? 'Build a reminder routine around your plans and quiet hours.'
                            : 'Choose up to 3 fixed reminders. Smart reminders are included with Pro.',
                        color: const Color(0xFF65705E),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          gap(20),
          DesignCard(
            child: Column(
              children: [
                for (final reminder in reminders) ...[
                  SettingRow(
                    '${defaultRows[reminder.$1]?['title'] ?? reminder.$2}',
                    _reminderTime(
                      context,
                      defaultRows[reminder.$1],
                      reminder.$3,
                    ),
                    reminder.$4,
                    onTap: defaultRows[reminder.$1] == null
                        ? null
                        : () => context.push(
                            Uri(
                              path: '/reminder-edit',
                              queryParameters: {
                                'id': '${defaultRows[reminder.$1]!['id']}',
                              },
                            ).toString(),
                          ),
                    trailing: Switch.adaptive(
                      activeTrackColor: ink,
                      value: defaultRows[reminder.$1]?['enabled'] == true,
                      onChanged: (enabled) async {
                        if (enabled &&
                            reminder.$1 == 'walking' &&
                            !state.isPro) {
                          context.push('/paywall');
                          return;
                        }
                        final count = state.reminders
                            .where((r) => r['enabled'] == true)
                            .length;
                        if (enabled && !state.isPro && count >= 3) {
                          context.push('/paywall');
                          return;
                        }
                        try {
                          await ref
                              .read(appProvider.notifier)
                              .toggleReminder(
                                '${defaultRows[reminder.$1]?['id'] ?? reminder.$1}',
                                enabled,
                              );
                        } catch (error) {
                          ref.read(appProvider.notifier).reportError(error);
                        }
                      },
                    ),
                  ),
                  if (reminder.$1 != 'weekly') const Divider(height: 1),
                ],
              ],
            ),
          ),
          if (extraRows.isNotEmpty) ...[
            section('More reminders'),
            DesignCard(
              child: Column(
                children: [
                  for (final row in extraRows) ...[
                    SettingRow(
                      '${row['title'] ?? 'Reminder'}',
                      _reminderTime(context, row, 'Choose a time'),
                      Icons.notifications_none_rounded,
                      onTap: () => context.push(
                        Uri(
                          path: '/reminder-edit',
                          queryParameters: {'id': '${row['id']}'},
                        ).toString(),
                      ),
                      trailing: Switch.adaptive(
                        value: row['enabled'] == true,
                        activeTrackColor: ink,
                        onChanged: (enabled) async {
                          if (enabled &&
                              !state.isPro &&
                              (row['smart'] == true ||
                                  state.reminders
                                          .where((r) => r['enabled'] == true)
                                          .length >=
                                      3)) {
                            context.push('/paywall');
                            return;
                          }
                          try {
                            await ref
                                .read(appProvider.notifier)
                                .toggleReminder('${row['id']}', enabled);
                          } catch (error) {
                            ref.read(appProvider.notifier).reportError(error);
                          }
                        },
                      ),
                    ),
                    if (row != extraRows.last) const Divider(height: 1),
                  ],
                ],
              ),
            ),
          ],
          gap(14),
          DesignCard(
            onTap: () =>
                context.push(state.isPro ? '/quiet-hours' : '/paywall'),
            child: Row(
              children: [
                const Icon(Icons.nightlight_outlined, size: 23),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Quiet hours',
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      gap(4),
                      subtext(
                        state.isPro
                            ? 'Choose your uninterrupted hours'
                            : 'Included with LeanGuard Pro',
                        color: const Color(0xFF777F78),
                      ),
                    ],
                  ),
                ),
                Icon(
                  state.isPro
                      ? Icons.chevron_right_rounded
                      : Icons.lock_outline_rounded,
                  size: 20,
                ),
              ],
            ),
          ),
          gap(18),
          PrimaryAction(
            'Notification permissions',
            dark: true,
            onPressed: () => context.push('/notification-permission'),
          ),
          gap(16),
          subtext(
            'You can switch reminders off at any time. Delivery depends on your device permissions and system settings.',
            color: const Color(0xFF838A83),
          ),
        ],
      ),
    );
  }

  String _reminderTime(
    BuildContext context,
    Map<String, dynamic>? row,
    String fallback,
  ) {
    if (row == null) return fallback;
    if (row['smart'] == true) return 'When your target is incomplete';
    final parts = '${row['time_of_day'] ?? ''}'.split(':');
    final hour = int.tryParse(parts.first),
        minute = parts.length > 1 ? int.tryParse(parts[1]) : null;
    if (hour == null || minute == null || hour > 23 || minute > 59) {
      return fallback;
    }
    final days = List<num>.from(row['days_of_week'] ?? []);
    final label = days.length == 7
        ? 'Daily'
        : days
              .where((day) => day >= 1 && day <= 7)
              .map(
                (day) => [
                  'Mon',
                  'Tue',
                  'Wed',
                  'Thu',
                  'Fri',
                  'Sat',
                  'Sun',
                ][day.toInt() - 1],
              )
              .join(', ');
    final time = TimeOfDay(hour: hour, minute: minute).format(context);
    return label.isEmpty ? time : '$label · $time';
  }
}

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final name = state.name.isEmpty ? 'Your profile' : state.name;
    return ScreenFrame(
      title: 'You',
      dark: false,
      tab: 4,
      actions: [
        IconButton(
          tooltip: 'Edit profile',
          onPressed: () => context.push('/edit-profile'),
          icon: const Icon(Icons.settings_outlined),
        ),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                radius: 29,
                backgroundColor: const Color(0xFF1E241D),
                child: Text(
                  name.substring(0, 1).toUpperCase(),
                  style: const TextStyle(
                    color: lime,
                    fontWeight: FontWeight.w800,
                    fontSize: 23,
                  ),
                ),
              ),
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    gap(5),
                    subtext(
                      'Lose weight. Keep your muscle.',
                      color: const Color(0xFF7B827C),
                    ),
                  ],
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  backgroundColor: ink,
                  foregroundColor: lime,
                ),
                onPressed: () => context.push('/paywall'),
                child: Text(
                  state.isPro ? 'PRO' : 'FREE',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          section('Connections'),
          DesignCard(
            child: Column(
              children: [
                SettingRow(
                  'Health connections',
                  'Apple Health / Health Connect',
                  Icons.favorite_outline_rounded,
                  onTap: () => context.push('/health-permission'),
                ),
                const Divider(height: 1),
                SettingRow(
                  'Wearable data',
                  'Manage permissions through your health app',
                  Icons.watch_outlined,
                  onTap: () => context.push('/health-permission'),
                ),
              ],
            ),
          ),
          section('Plan settings'),
          DesignCard(
            child: Column(
              children: [
                SettingRow(
                  'Goals & targets',
                  'Weight, protein, steps and units',
                  Icons.my_location_rounded,
                  onTap: () => context.push('/targets'),
                ),
                const Divider(height: 1),
                SettingRow(
                  'Training preferences',
                  'Equipment, schedule and exercise choices',
                  Icons.tune_rounded,
                  onTap: () => context.push('/personalization'),
                ),
                const Divider(height: 1),
                SettingRow(
                  'GLP-1 support mode',
                  'Optional wellness support',
                  Icons.monitor_heart_outlined,
                  trailing: Switch.adaptive(
                    value: state.glpEnabled,
                    activeTrackColor: ink,
                    onChanged: (enabled) =>
                        ref.read(appProvider.notifier).setGlp(enabled),
                  ),
                ),
                const Divider(height: 1),
                if (state.glpEnabled) ...[
                  SettingRow(
                    'GLP-1 routine support',
                    'Hydration, energy and clinician summaries',
                    Icons.favorite_outline_rounded,
                    onTap: () =>
                        context.push(state.isPro ? '/glp-support' : '/paywall'),
                  ),
                  const Divider(height: 1),
                ],
                SettingRow(
                  'Smart reminders',
                  '${state.reminders.where((r) => r['enabled'] == true).length} reminders active',
                  Icons.notifications_none_rounded,
                  onTap: () => context.push('/reminders'),
                ),
              ],
            ),
          ),
          section('LeanGuard'),
          DesignCard(
            child: Column(
              children: [
                SettingRow(
                  'LeanGuard Pro',
                  state.isPro
                      ? 'Manage subscription'
                      : 'Explore your membership options',
                  Icons.auto_awesome_rounded,
                  iconColor: lime,
                  onTap: () => context.push('/paywall'),
                ),
                const Divider(height: 1),
                SettingRow(
                  'Your reports',
                  'Weekly progress and saved history',
                  Icons.summarize_outlined,
                  onTap: () => context.push('/reports'),
                ),
                const Divider(height: 1),
                SettingRow(
                  'Privacy & data',
                  'Export, consent and account deletion',
                  Icons.shield_outlined,
                  onTap: () => context.push('/privacy'),
                ),
                const Divider(height: 1),
                SettingRow(
                  'Your profile',
                  'Name and preferences',
                  Icons.person_outline_rounded,
                  onTap: () => context.push('/edit-profile'),
                ),
              ],
            ),
          ),
          gap(20),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: () async {
                await ref.read(appProvider.notifier).signOut();
                if (context.mounted) context.go('/welcome');
              },
              child: Text(
                state.demo ? 'Leave sample preview' : 'Sign out',
                style: const TextStyle(color: Color(0xFF747B75)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
