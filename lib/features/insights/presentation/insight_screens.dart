import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/state.dart';
import '../../dashboard/presentation/design.dart';

export 'adaptive_insights_screen.dart';

double _number(dynamic value) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? 0;
DateTime? _recorded(Map<String, dynamic> row) => DateTime.tryParse(
  '${row['recorded_at'] ?? row['completed_at'] ?? row['date'] ?? row['created_at']}',
)?.toLocal();
String _date(DateTime date) =>
    '${['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][date.month - 1]} ${date.day}, ${date.year}';

class ReportsScreen extends ConsumerStatefulWidget {
  const ReportsScreen({super.key});
  @override
  ConsumerState<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends ConsumerState<ReportsScreen> {
  String period = 'week';
  bool exporting = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final selected = state.isPro ? period : 'week';
    final start = selected == 'month'
        ? DateTime(now.year, now.month)
        : selected == 'all'
        ? DateTime(2000)
        : today.subtract(Duration(days: now.weekday - 1));
    bool inside(Map<String, dynamic> row) {
      final at = _recorded(row);
      return at != null &&
          !at.isBefore(start) &&
          at.isBefore(today.add(const Duration(days: 1)));
    }

    final workouts = state.workouts
        .where((row) => row['status'] == 'completed' && inside(row))
        .toList();
    final meals = state.rows('protein_entries').where(inside).toList();
    final activity = state.activities.where(inside).toList();
    final weights = state.weights.where(inside).toList()
      ..sort((a, b) => _recorded(a)!.compareTo(_recorded(b)!));
    final protein = meals.fold<double>(
      0,
      (total, row) => total + _number(row['protein_g']),
    );
    final mealDays = meals
        .map((row) => _recorded(row)!.toIso8601String().substring(0, 10))
        .toSet()
        .length;
    final steps = activity.fold<double>(
      0,
      (total, row) => total + _number(row['steps']),
    );
    final weightChange = weights.length < 2
        ? null
        : _number(weights.last['weight_kg']) -
              _number(weights.first['weight_kg']);
    final days = selected == 'all' ? 0 : today.difference(start).inDays + 1;
    final savedInsights = [...state.rows('weekly_insights')]
      ..sort(
        (a, b) => '${b['week_start'] ?? b['created_at']}'.compareTo(
          '${a['week_start'] ?? a['created_at']}',
        ),
      );
    return ScreenFrame(
      title: 'Your reports',
      back: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          eyebrow('A clearer view of your habits', color: lime),
          gap(10),
          heading('Progress beyond\nthe scale.', size: 31),
          gap(12),
          subtext(
            'Review what you logged, notice patterns and carry the useful habits into your next week.',
          ),
          gap(22),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in [
                ('week', 'This week'),
                ('month', 'This month'),
                ('all', 'All time'),
              ])
                ChoiceChip(
                  label: Text(option.$2),
                  selected: selected == option.$1,
                  onSelected: (_) {
                    if (option.$1 != 'week' && !state.isPro) {
                      context.push('/paywall');
                      return;
                    }
                    setState(() => period = option.$1);
                  },
                ),
            ],
          ),
          gap(18),
          DesignCard(
            gradient: const LinearGradient(
              colors: [Color(0xFF263322), Color(0xFF181E17)],
            ),
            border: const Color(0xFF34452E),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                eyebrow(
                  selected == 'all'
                      ? 'All your recorded days'
                      : '${_date(start)} – ${_date(today)}',
                  color: lime,
                ),
                gap(20),
                Row(
                  children: [
                    Expanded(
                      child: _reportMetric(
                        '${workouts.length}',
                        'strength sessions',
                        Icons.fitness_center_rounded,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _reportMetric(
                        '${steps.round()}',
                        'recorded steps',
                        Icons.directions_walk_rounded,
                      ),
                    ),
                  ],
                ),
                gap(20),
                const Divider(),
                gap(6),
                Text(
                  workouts.isEmpty && meals.isEmpty && activity.isEmpty
                      ? 'Your next logged habit starts this report.'
                      : 'Every recorded habit helps you see what is working.',
                  style: const TextStyle(
                    fontSize: 13,
                    color: muted,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
          section('Your logged numbers'),
          DesignCard(
            child: Column(
              children: [
                _reportRow(
                  'Protein',
                  mealDays == 0
                      ? 'No meals recorded'
                      : '${(protein / mealDays).round()}g average per logged day',
                  '${meals.length} ${meals.length == 1 ? 'meal' : 'meals'} across $mealDays ${mealDays == 1 ? 'day' : 'days'}',
                ),
                const Divider(height: 26),
                _reportRow(
                  'Daily movement',
                  activity.isEmpty
                      ? 'No steps recorded'
                      : '${(steps / activity.length).round()} steps per recorded day',
                  '${activity.length} ${activity.length == 1 ? 'day' : 'days'} recorded',
                ),
                const Divider(height: 26),
                _reportRow(
                  'Weight change',
                  weightChange == null
                      ? 'Add two entries to compare'
                      : '${weightChange > 0 ? '+' : ''}${(state.units == 'lb' ? weightChange * 2.2046226218 : weightChange).toStringAsFixed(1)} ${state.units}',
                  '${weights.length} weight entries',
                ),
              ],
            ),
          ),
          gap(20),
          DesignCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    iconBox(Icons.ios_share_rounded),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        state.isPro
                            ? 'Take your progress with you'
                            : 'Reports you can share · Pro',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 17,
                        ),
                      ),
                    ),
                  ],
                ),
                gap(12),
                subtext(
                  'Export the selected period as a readable PDF or a CSV of your recorded data.',
                ),
                gap(18),
                Row(
                  children: [
                    Expanded(
                      child: PrimaryAction(
                        'PDF report',
                        busy: exporting,
                        onPressed: () => _export('pdf', days, state.isPro),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: PrimaryAction(
                        'CSV data',
                        busy: exporting,
                        onPressed: () => _export('csv', days, state.isPro),
                      ),
                    ),
                  ],
                ),
                gap(10),
                subtext(
                  'Your complete account data export remains available to everyone in Privacy & data.',
                ),
              ],
            ),
          ),
          section('Saved weekly reviews'),
          if (savedInsights.isEmpty)
            DesignCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Your story is still taking shape.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  gap(8),
                  subtext(
                    'Ask Lean Coach for your weekly summary. Your saved reviews stay available even after Pro expires.',
                  ),
                  gap(10),
                  TextButton.icon(
                    onPressed: () => context.go('/coach'),
                    icon: const Icon(Icons.auto_awesome_outlined),
                    label: const Text('Open Lean Coach'),
                  ),
                ],
              ),
            ),
          for (final insight in savedInsights)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: DesignCard(
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(bottom: 8),
                  title: Text(
                    'Week of ${insight['week_start'] ?? 'your saved review'}',
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                    ),
                  ),
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: SelectableText(
                        _insightSummary(insight),
                        style: const TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: muted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          gap(12),
          Center(
            child: TextButton.icon(
              onPressed: () => context.push('/privacy'),
              icon: const Icon(Icons.shield_outlined, size: 18),
              label: const Text('Privacy & full data export'),
            ),
          ),
        ],
      ),
    );
  }

  String _insightSummary(Map<String, dynamic> insight) {
    final content = insight['content'] ?? insight['structured_content'];
    if (content is Map) {
      return '${content['summary'] ?? 'Open Lean Coach to review your saved insight.'}';
    }
    return '${insight['summary'] ?? content ?? 'Open Lean Coach to review your saved insight.'}';
  }

  Widget _reportMetric(String value, String label, IconData icon) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Icon(icon, color: lime, size: 22),
      gap(12),
      heading(value, size: 32),
      gap(5),
      subtext(label),
    ],
  );
  Widget _reportRow(String label, String value, String caption) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      eyebrow(label),
      gap(7),
      Text(
        value,
        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
      ),
      gap(5),
      subtext(caption),
    ],
  );
  Future<void> _export(String format, int days, bool pro) async {
    if (!pro) {
      context.push('/paywall');
      return;
    }
    setState(() => exporting = true);
    try {
      await ref
          .read(appProvider.notifier)
          .exportReport(format: format, days: days);
    } catch (error) {
      ref.read(appProvider.notifier).reportError(error);
    } finally {
      if (mounted) setState(() => exporting = false);
    }
  }
}

class GlpSupportScreen extends ConsumerStatefulWidget {
  const GlpSupportScreen({super.key});
  @override
  ConsumerState<GlpSupportScreen> createState() => _GlpSupportScreenState();
}

class _GlpSupportScreenState extends ConsumerState<GlpSupportScreen> {
  String appetite = 'normal';
  int energy = 3;
  bool hydration = false, busy = false;
  @override
  void initState() {
    super.initState();
    final state = ref.read(appProvider);
    final prefs = state.rows('medication_support_preferences');
    if (prefs.isNotEmpty) {
      appetite = '${prefs.first['appetite_level'] ?? 'normal'}';
      hydration = prefs.first['hydration_reminders'] == true;
    }
    final activity = state.activities.where(
      (row) => row['date'] == state.today,
    );
    if (activity.isNotEmpty) {
      energy =
          (_number(activity.first['energy_level']) == 0
                  ? 3
                  : _number(activity.first['energy_level']).round())
              .clamp(1, 5);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider);
    return ScreenFrame(
      title: 'GLP-1 routine support',
      dark: false,
      back: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DesignCard(
            color: const Color(0xFFE9F1DC),
            border: const Color(0xFFD8E3CA),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                iconBox(
                  Icons.monitor_heart_outlined,
                  color: const Color(0xFFD4E4BF),
                ),
                gap(16),
                heading('Support for\nyour everyday.', size: 29),
                gap(10),
                subtext(
                  'For people already taking medication under clinician supervision. Keep protein, movement and hydration habits in view.',
                  color: const Color(0xFF626E58),
                ),
              ],
            ),
          ),
          gap(18),
          DesignCard(
            child: SettingRow(
              'Support mode',
              'Under the care of my clinician',
              Icons.favorite_outline_rounded,
              trailing: Switch.adaptive(
                value: state.glpEnabled,
                activeTrackColor: ink,
                onChanged: (enabled) =>
                    ref.read(appProvider.notifier).setGlp(enabled),
              ),
            ),
          ),
          gap(16),
          DesignCard(
            color: const Color(0xFFE8EAE5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  color: Color(0xFF626963),
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: subtext(
                    'LeanGuard never diagnoses symptoms or recommends starting, stopping or changing medication or dosage. Your prescribing clinician manages treatment.',
                    color: const Color(0xFF626963),
                  ),
                ),
              ],
            ),
          ),
          section(
            'A quick check-in',
            trailing: state.isPro
                ? null
                : const Icon(Icons.lock_outline_rounded, size: 18),
          ),
          if (!state.isPro)
            _ProCard(
              title: 'Appetite-aware support',
              body:
                  'Unlock routine check-ins, protein-first ideas, energy-aware plan review and a clinician summary.',
              onPressed: () => context.push('/paywall'),
            )
          else ...[
            DesignCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'How is your appetite?',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  gap(13),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final value in [
                        ('normal', 'Usual'),
                        ('low', 'Lower'),
                        ('very_low', 'Very low'),
                      ])
                        ChoiceChip(
                          label: Text(value.$2),
                          selected: appetite == value.$1,
                          onSelected: (_) =>
                              setState(() => appetite = value.$1),
                        ),
                    ],
                  ),
                  gap(22),
                  const Text(
                    'How is your energy?',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  gap(10),
                  Row(
                    children: [
                      const Text(
                        'Low',
                        style: TextStyle(
                          color: Color(0xFF737B73),
                          fontSize: 12,
                        ),
                      ),
                      Expanded(
                        child: Slider(
                          value: energy.toDouble(),
                          min: 1,
                          max: 5,
                          divisions: 4,
                          label: '$energy of 5',
                          activeColor: const Color(0xFF668536),
                          onChanged: (value) =>
                              setState(() => energy = value.round()),
                        ),
                      ),
                      const Text(
                        'High',
                        style: TextStyle(
                          color: Color(0xFF737B73),
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  Center(
                    child: Text(
                      '$energy / 5',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const Divider(height: 25),
                  SettingRow(
                    'Hydration reminder',
                    'A gentle routine check-in',
                    Icons.water_drop_outlined,
                    trailing: Switch.adaptive(
                      value: hydration,
                      activeTrackColor: ink,
                      onChanged: (value) => setState(() => hydration = value),
                    ),
                  ),
                  gap(12),
                  PrimaryAction(
                    'Save check-in',
                    dark: true,
                    busy: busy,
                    onPressed: state.glpEnabled ? _saveCheckIn : null,
                  ),
                  if (!state.glpEnabled) ...[
                    gap(10),
                    subtext(
                      'Enable support mode above to save your check-in.',
                      color: const Color(0xFF737B73),
                    ),
                  ],
                ],
              ),
            ),
            gap(16),
            DesignCard(
              color: const Color(0xFFFFF2E6),
              border: const Color(0xFFF3DDC8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Make the next meal manageable.',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                  ),
                  gap(9),
                  subtext(
                    'Ask for protein-first ideas based on your remaining target, appetite and food preferences.',
                    color: const Color(0xFF8B6F5B),
                  ),
                  gap(15),
                  PrimaryAction(
                    'Ask for protein support',
                    dark: true,
                    busy: busy,
                    onPressed: _proteinSupport,
                  ),
                ],
              ),
            ),
            gap(16),
            DesignCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Prepare for your clinician',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                  ),
                  gap(9),
                  subtext(
                    'Export a factual summary of your recent logs to support a conversation. It does not assess symptoms or recommend treatment.',
                    color: const Color(0xFF737B73),
                  ),
                  gap(15),
                  PrimaryAction(
                    'Export clinician summary',
                    dark: true,
                    busy: busy,
                    onPressed: _clinicianSummary,
                  ),
                ],
              ),
            ),
          ],
          section('When to seek care'),
          DesignCard(
            color: const Color(0xFFFFEEE3),
            border: const Color(0xFFEAD7C9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Pain, fainting, dehydration or severe weakness need professional attention.',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
                gap(9),
                subtext(
                  'Pause exercise and contact an appropriate medical professional. For severe, sudden symptoms or immediate danger, call local emergency services.',
                  color: const Color(0xFF7D685A),
                ),
              ],
            ),
          ),
          gap(18),
        ],
      ),
    );
  }

  Future<void> _saveCheckIn() async {
    setState(() => busy = true);
    try {
      await ref
          .read(appProvider.notifier)
          .saveGlpCheckIn(appetite, energy, hydration);
      if (mounted) showMessage(context, 'Your check-in is saved.');
    } catch (error) {
      ref.read(appProvider.notifier).reportError(error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _clinicianSummary() async {
    setState(() => busy = true);
    try {
      await ref
          .read(appProvider.notifier)
          .exportReport(format: 'pdf', days: 30, clinician: true);
    } catch (error) {
      ref.read(appProvider.notifier).reportError(error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _proteinSupport() async {
    final consent =
        ref
            .read(appProvider)
            .rows('consent_records')
            .where((row) => row['purpose'] == 'ai_processing')
            .toList()
          ..sort(
            (a, b) => '${a['recorded_at'] ?? a['created_at']}'.compareTo(
              '${b['recorded_at'] ?? b['created_at']}',
            ),
          );
    if (consent.isEmpty || consent.last['granted'] != true) {
      final allow = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Enable personalized AI coaching?'),
          content: const Text(
            'With your permission, relevant health logs, food preferences and medication-support preferences are processed by our secure service and AI provider. You can withdraw consent in Privacy & data.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Not now'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('I agree'),
            ),
          ],
        ),
      );
      if (allow != true) return;
      try {
        await ref
            .read(appProvider.notifier)
            .recordConsent('ai_processing', true);
      } catch (error) {
        ref.read(appProvider.notifier).reportError(error);
        return;
      }
    }
    if (!mounted) return;
    setState(() => busy = true);
    try {
      await ref
          .read(appProvider.notifier)
          .askCoach(
            'Suggest manageable protein-first meals for my remaining target, current appetite and logged food preferences. Keep suggestions within my existing target and avoid medication advice.',
          );
      if (mounted) context.go('/coach');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class PersonalizationScreen extends ConsumerStatefulWidget {
  const PersonalizationScreen({super.key});
  @override
  ConsumerState<PersonalizationScreen> createState() =>
      _PersonalizationScreenState();
}

class _PersonalizationScreenState extends ConsumerState<PersonalizationScreen> {
  late Set<String> equipment;
  late Set<int> days;
  late double minutes;
  late String tone;
  final limitations = TextEditingController();
  final preferences = TextEditingController();
  bool busy = false;
  @override
  void initState() {
    super.initState();
    final state = ref.read(appProvider), profile = state.goalProfile;
    equipment = List<String>.from(
      profile['equipment'] ?? ['bodyweight'],
    ).toSet();
    days = List<int>.from(profile['training_days'] ?? [1, 3, 5]).toSet();
    minutes =
        (_number(profile['session_minutes']) == 0
                ? 35.0
                : _number(profile['session_minutes']))
            .clamp(10, 180);
    tone = '${state.profile['coaching_tone'] ?? 'supportive'}';
    limitations.text = List<String>.from(
      profile['limitations'] ?? [],
    ).join(', ');
    preferences.text = List<String>.from(
      profile['exercise_preferences'] ?? [],
    ).join(', ');
  }

  @override
  void dispose() {
    limitations.dispose();
    preferences.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider);
    final futureWorkoutIds = state.workouts
        .where((row) => row['status'] == 'planned')
        .map((row) => row['id'])
        .toSet();
    final planned = state
        .rows('workout_exercises')
        .where(
          (row) =>
              row['status'] == 'planned' &&
              futureWorkoutIds.contains(row['workout_id']) &&
              row['workout_id'] != state.activeWorkout?['id'],
        )
        .toList();
    return ScreenFrame(
      title: 'Make it your plan',
      back: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          eyebrow('Built around your real life', color: lime),
          gap(10),
          heading('Strong habits.\nYour way.', size: 32),
          gap(12),
          subtext(
            'Choose the equipment, schedule and preferences that make a consistent routine possible.',
          ),
          section('Your equipment'),
          DesignCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                subtext('Choose what you have access to.'),
                gap(14),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final item in [
                      ('bodyweight', 'Bodyweight'),
                      ('dumbbells', 'Dumbbells'),
                      ('barbell', 'Barbell'),
                      ('bands', 'Resistance bands'),
                      ('machines', 'Gym machines'),
                      ('kettlebell', 'Kettlebell'),
                    ])
                      FilterChip(
                        label: Text(item.$2),
                        selected: equipment.contains(item.$1),
                        onSelected: (selected) => setState(() {
                          selected
                              ? equipment.add(item.$1)
                              : equipment.remove(item.$1);
                        }),
                      ),
                  ],
                ),
                gap(18),
                PrimaryAction(
                  'Save equipment',
                  busy: busy,
                  onPressed: equipment.isEmpty ? null : _saveEquipment,
                ),
              ],
            ),
          ),
          section(
            'Your training rhythm',
            trailing: state.isPro
                ? null
                : const Icon(Icons.lock_outline_rounded, size: 18),
          ),
          if (!state.isPro)
            _ProCard(
              title: 'A plan that fits around you',
              body:
                  'Personalize training days, session time, exercise preferences and coaching style with Pro.',
              onPressed: () => context.push('/paywall'),
            )
          else ...[
            DesignCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          'Session length',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      Text(
                        '${minutes.round()} min',
                        style: const TextStyle(
                          color: lime,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: minutes,
                    min: 10,
                    max: 180,
                    divisions: 34,
                    label: '${minutes.round()} minutes',
                    activeColor: lime,
                    onChanged: (value) => setState(() => minutes = value),
                  ),
                  gap(10),
                  const Text(
                    'Preferred training days',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  gap(13),
                  Wrap(
                    spacing: 7,
                    runSpacing: 7,
                    children: [
                      for (var day = 1; day <= 7; day++)
                        FilterChip(
                          label: Text(
                            [
                              'Mon',
                              'Tue',
                              'Wed',
                              'Thu',
                              'Fri',
                              'Sat',
                              'Sun',
                            ][day - 1],
                          ),
                          selected: days.contains(day),
                          onSelected: (selected) => setState(() {
                            selected ? days.add(day) : days.remove(day);
                          }),
                        ),
                    ],
                  ),
                  if (days.isEmpty) ...[
                    gap(9),
                    const Text(
                      'Choose at least one training day.',
                      style: TextStyle(color: orange, fontSize: 12),
                    ),
                  ],
                  gap(22),
                  TextField(
                    controller: limitations,
                    maxLength: 500,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Movement limitations',
                      hintText: 'For example: no overhead movements',
                      helperText:
                          'Separate items with commas. Follow clinical restrictions.',
                    ),
                  ),
                  gap(14),
                  TextField(
                    controller: preferences,
                    maxLength: 500,
                    minLines: 1,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Exercise preferences',
                      hintText: 'For example: prefer dumbbells',
                      helperText: 'Separate preferences with commas.',
                    ),
                  ),
                  gap(10),
                  const Text(
                    'Coaching style',
                    style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
                  ),
                  gap(12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final choice in [
                        ('supportive', 'Supportive'),
                        ('direct', 'Direct'),
                        ('detailed', 'Detailed'),
                      ])
                        ChoiceChip(
                          label: Text(choice.$2),
                          selected: tone == choice.$1,
                          onSelected: (_) => setState(() => tone = choice.$1),
                        ),
                    ],
                  ),
                  gap(20),
                  PrimaryAction(
                    'Save training preferences',
                    busy: busy,
                    onPressed: days.isEmpty || equipment.isEmpty
                        ? null
                        : _savePersonalization,
                  ),
                ],
              ),
            ),
            section('Planned exercise substitutions'),
            if (planned.isEmpty)
              DesignCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'No unstarted exercises to swap yet.',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    gap(8),
                    subtext(
                      'Only future planned exercises can be changed here. Your active and completed sessions stay intact.',
                    ),
                  ],
                ),
              )
            else
              for (final row in planned)
                Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: DesignCard(
                    onTap: busy ? null : () => _substitute(row),
                    child: Row(
                      children: [
                        const Icon(Icons.swap_horiz_rounded, color: lime),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                _exerciseName(state, '${row['exercise_id']}'),
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              gap(5),
                              subtext(
                                '${row['target_sets']} sets × ${row['target_reps']} reps',
                              ),
                            ],
                          ),
                        ),
                        const Icon(Icons.chevron_right_rounded),
                      ],
                    ),
                  ),
                ),
            gap(18),
            DesignCard(
              border: const Color(0xFF445833),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Review an adjustment together.',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
                  ),
                  gap(9),
                  subtext(
                    'Lean Coach can suggest conservative changes using your logged sessions. You approve every plan adjustment before it is applied.',
                  ),
                  gap(14),
                  PrimaryAction(
                    'Open Lean Coach',
                    onPressed: () => context.go('/coach'),
                  ),
                ],
              ),
            ),
          ],
          gap(20),
        ],
      ),
    );
  }

  String _exerciseName(AppState state, String id) {
    final matches = state.rows('exercises').where((row) => row['id'] == id);
    return matches.isEmpty ? 'Planned exercise' : '${matches.first['name']}';
  }

  Future<void> _saveEquipment() async {
    setState(() => busy = true);
    try {
      await ref.read(appProvider.notifier).saveEquipment(equipment.toList());
      if (mounted) showMessage(context, 'Equipment saved.');
    } catch (error) {
      ref.read(appProvider.notifier).reportError(error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  List<String> _items(String input) => input
      .split(',')
      .map((item) => item.trim())
      .where((item) => item.isNotEmpty)
      .toList();
  Future<void> _savePersonalization() async {
    setState(() => busy = true);
    try {
      await ref.read(appProvider.notifier).saveEquipment(equipment.toList());
      await ref
          .read(appProvider.notifier)
          .savePersonalization(
            minutes: minutes.round(),
            days: days.toList()..sort(),
            limitations: _items(limitations.text),
            preferences: _items(preferences.text),
            tone: tone,
          );
      if (mounted) {
        showMessage(
          context,
          'Your preferences are saved. Review any plan changes with Lean Coach.',
        );
      }
    } catch (error) {
      ref.read(appProvider.notifier).reportError(error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _substitute(Map<String, dynamic> planned) async {
    final state = ref.read(appProvider);
    final current = '${planned['exercise_id']}';
    final choice = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: math.min(MediaQuery.sizeOf(context).height * 0.7, 520),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              heading('Choose a substitution', size: 24),
              gap(10),
              subtext(
                'Choose an exercise that fits your equipment, abilities and any professional guidance.',
              ),
              gap(15),
              for (final exercise
                  in state
                      .rows('exercises')
                      .where((row) => row['id'] != current))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.fitness_center_rounded),
                  title: Text('${exercise['name']}'),
                  subtitle: Text(
                    '${exercise['equipment']} · ${exercise['muscle_group'] ?? 'Strength'}',
                  ),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => Navigator.pop(context, '${exercise['id']}'),
                ),
            ],
          ),
        ),
      ),
    );
    if (choice == null || !mounted) return;
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirm exercise swap'),
        content: Text(
          'Replace ${_exerciseName(state, current)} with ${_exerciseName(state, choice)} in this planned session? Your past workout logs will stay unchanged.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep current'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Confirm swap'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() => busy = true);
    try {
      await ref
          .read(appProvider.notifier)
          .substituteExercise('${planned['id']}', choice);
      if (mounted) {
        showMessage(context, 'Your planned exercise has been updated.');
      }
    } catch (error) {
      ref.read(appProvider.notifier).reportError(error);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }
}

class _ProCard extends StatelessWidget {
  const _ProCard({
    required this.title,
    required this.body,
    required this.onPressed,
  });
  final String title, body;
  final VoidCallback onPressed;
  @override
  Widget build(BuildContext context) => DesignCard(
    color: const Color(0xFF24301E),
    border: const Color(0xFF4A6135),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            iconBox(Icons.auto_awesome_rounded),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  color: paper,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
        gap(12),
        subtext(body),
        gap(18),
        PrimaryAction('Explore LeanGuard Pro', onPressed: onPressed),
      ],
    ),
  );
}
