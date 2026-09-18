import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/state.dart';
import '../../dashboard/presentation/design.dart';

class WorkoutScreen extends ConsumerStatefulWidget {
  const WorkoutScreen({super.key});
  @override
  ConsumerState<WorkoutScreen> createState() => _WorkoutScreenState();
}

class _WorkoutScreenState extends ConsumerState<WorkoutScreen> {
  Timer? ticker;
  DateTime? restUntil;
  String? exerciseId;
  int reps = 10;
  double weightKg = 10;
  bool saving = false;

  @override
  void initState() {
    super.initState();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    ticker?.cancel();
    super.dispose();
  }

  String _duration(int seconds) =>
      '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider);
    final active = state.activeWorkout;
    if (active == null) {
      return ScreenFrame(
        title: 'Live workout',
        back: true,
        child: Column(
          children: [
            gap(40),
            const Icon(Icons.fitness_center_rounded, size: 65, color: lime),
            gap(24),
            heading('Your next strong step.'),
            gap(12),
            subtext('Start a session to record your sets, reps and weights.'),
            gap(24),
            PrimaryAction(
              'Start workout',
              onPressed: () => ref.read(appProvider.notifier).startWorkout(),
            ),
          ],
        ),
      );
    }
    final index = (active['exercise_index'] as num?)?.toInt() ?? 0;
    final started =
        DateTime.tryParse('${active['started_at']}') ?? DateTime.now();
    final elapsed = math.max(0, DateTime.now().difference(started).inSeconds);
    final exercises = state.exercises;
    if (index >= exercises.length) {
      return ScreenFrame(
        title: 'Workout complete',
        back: true,
        child: Column(
          children: [
            gap(50),
            iconBox(Icons.check_rounded, size: 78),
            gap(24),
            heading('You showed up.\nThat matters.', size: 34),
            gap(16),
            subtext(
              'Your sets are saved. Finish your session to see the full summary.',
            ),
            gap(26),
            DesignCard(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _stat('DURATION', _duration(elapsed)),
                  _stat('SETS', '${(active['sets'] as List?)?.length ?? 0}'),
                ],
              ),
            ),
            gap(26),
            PrimaryAction('Finish workout', busy: saving, onPressed: _finish),
          ],
        ),
      );
    }
    final exercise = exercises[index];
    final id = '${exercise['id']}';
    if (exerciseId != id) {
      exerciseId = id;
      reps = (exercise['reps'] as num?)?.toInt() ?? 10;
      weightKg = (exercise['weight_kg'] as num?)?.toDouble() ?? 0;
    }
    final setNumber = (active['set_number'] as num?)?.toInt() ?? 1;
    final targetSets = (exercise['sets'] as num?)?.toInt() ?? 3;
    final rest = restUntil == null
        ? 0
        : math.max(0, restUntil!.difference(DateTime.now()).inSeconds);
    final shownWeight = state.units == 'lb'
        ? weightKg * 2.2046226218
        : weightKg;
    return ScreenFrame(
      title: '${active['name'] ?? active['title'] ?? 'Strength workout'}',
      back: true,
      padding: false,
      actions: [
        Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: const Color(0xFF272C28),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              _duration(elapsed),
              style: const TextStyle(
                fontSize: 13,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ),
      ],
      child: SingleChildScrollView(
        child: Column(
          children: [
            LinearProgressIndicator(
              value:
                  (index + (setNumber - 1) / targetSets) /
                  math.max(exercises.length, 1),
              color: lime,
              minHeight: 3,
              backgroundColor: const Color(0xFF2C312D),
            ),
            Container(
              height: 210,
              width: double.infinity,
              decoration: const BoxDecoration(
                gradient: RadialGradient(
                  colors: [
                    Color(0xFF36432E),
                    Color(0xFF1B201C),
                    Color(0xFF151816),
                  ],
                ),
              ),
              child: Stack(
                children: [
                  Positioned(
                    left: 22,
                    top: 18,
                    child: eyebrow('${index + 1} of ${exercises.length}'),
                  ),
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.fitness_center_rounded,
                          size: 67,
                          color: lime,
                        ),
                        gap(24),
                        subtext('Controlled movement · Comfortable range'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Theme(
              data: ThemeData(
                fontFamily: Theme.of(context).textTheme.bodyMedium?.fontFamily,
                brightness: Brightness.light,
                colorScheme: ColorScheme.fromSeed(
                  seedColor: lime,
                ).copyWith(primary: ink, surface: paper),
                useMaterial3: true,
              ),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
                decoration: const BoxDecoration(
                  color: paper,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
                ),
                child: DefaultTextStyle(
                  style: Theme.of(
                    context,
                  ).textTheme.bodyMedium!.copyWith(color: ink, fontSize: 14),
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
                                  '${exercise['equipment'] ?? 'Strength'}',
                                  color: const Color(0xFF78816F),
                                ),
                                gap(5),
                                heading(
                                  '${exercise['name']}',
                                  size: 29,
                                  color: ink,
                                ),
                              ],
                            ),
                          ),
                          IconButton(
                            tooltip: 'Exercise instructions',
                            onPressed: () => context.push('/exercise/$id'),
                            icon: const Icon(
                              Icons.info_outline_rounded,
                              color: ink,
                            ),
                          ),
                        ],
                      ),
                      gap(15),
                      DesignCard(
                        color: const Color(0xFFE4E7DF),
                        border: const Color(0xFFE4E7DF),
                        padding: 13,
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  eyebrow(
                                    'Today’s target',
                                    color: const Color(0xFF747B75),
                                  ),
                                  gap(4),
                                  Text(
                                    '$targetSets sets × ${exercise['reps']} reps',
                                    style: const TextStyle(
                                      color: ink,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Flexible(
                              child: Text(
                                'Good form comes first',
                                textAlign: TextAlign.end,
                                style: const TextStyle(
                                  color: Color(0xFF52663C),
                                  fontSize: 11,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      gap(16),
                      Row(
                        children: List.generate(
                          targetSets,
                          (i) => Expanded(
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 13),
                              decoration: BoxDecoration(
                                border: Border(
                                  bottom: BorderSide(
                                    color: setNumber == i + 1
                                        ? ink
                                        : const Color(0xFFD5D8D1),
                                    width: setNumber == i + 1 ? 2 : 1,
                                  ),
                                ),
                              ),
                              child: Text(
                                setNumber > i + 1
                                    ? '✓ Set ${i + 1}'
                                    : 'Set ${i + 1}',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: setNumber == i + 1
                                      ? ink
                                      : const Color(0xFF878D87),
                                  fontWeight: setNumber == i + 1
                                      ? FontWeight.w800
                                      : FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      gap(24),
                      Row(
                        children: [
                          Expanded(
                            child: _stepper(
                              'WEIGHT',
                              '${shownWeight.toStringAsFixed(shownWeight == shownWeight.roundToDouble() ? 0 : 1)} ${state.units}',
                              () => setState(
                                () => weightKg = math.max(
                                  0,
                                  weightKg -
                                      (state.units == 'lb'
                                          ? 2.5 / 2.2046226218
                                          : 1),
                                ),
                              ),
                              () => setState(
                                () => weightKg = math.min(
                                  1000,
                                  weightKg +
                                      (state.units == 'lb'
                                          ? 2.5 / 2.2046226218
                                          : 1),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: _stepper(
                              'REPS',
                              '$reps',
                              () =>
                                  setState(() => reps = math.max(1, reps - 1)),
                              () => setState(
                                () => reps = math.min(100, reps + 1),
                              ),
                            ),
                          ),
                        ],
                      ),
                      gap(22),
                      if (rest > 0) ...[
                        DesignCard(
                          color: const Color(0xFFE4ECD9),
                          border: const Color(0xFFD8E5C8),
                          child: Row(
                            children: [
                              const Icon(Icons.timer_outlined, color: ink),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Rest · ${_duration(rest)}',
                                  style: const TextStyle(
                                    color: ink,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                              TextButton(
                                onPressed: () =>
                                    setState(() => restUntil = null),
                                child: const Text('End rest'),
                              ),
                            ],
                          ),
                        ),
                        gap(16),
                      ],
                      PrimaryAction(
                        'Complete set',
                        icon: Icons.check_rounded,
                        busy: saving,
                        onPressed: () => _log(id, setNumber, state.isPro),
                      ),
                      gap(8),
                      Center(
                        child: TextButton(
                          onPressed: saving
                              ? null
                              : () async {
                                  setState(() {
                                    saving = true;
                                    restUntil = null;
                                  });
                                  await ref
                                      .read(appProvider.notifier)
                                      .skipExercise(id);
                                  if (mounted) setState(() => saving = false);
                                },
                          child: const Text(
                            'Skip exercise',
                            style: TextStyle(color: Color(0xFF6F756F)),
                          ),
                        ),
                      ),
                      Center(
                        child: TextButton(
                          onPressed: saving ? null : _confirmFinish,
                          child: const Text(
                            'Finish session early',
                            style: TextStyle(
                              color: Color(0xFF747B75),
                              fontSize: 12,
                            ),
                          ),
                        ),
                      ),
                      gap(8),
                      subtext(
                        'Stop if you feel pain, dizziness or unusual weakness. Seek professional care for warning signs.',
                        color: const Color(0xFF72796E),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _stat(String label, String value) =>
      Column(children: [eyebrow(label), gap(10), heading(value, size: 30)]);
  Widget _stepper(
    String label,
    String value,
    VoidCallback minus,
    VoidCallback plus,
  ) => Column(
    children: [
      eyebrow(label, color: const Color(0xFF737A74)),
      gap(10),
      Container(
        height: 78,
        decoration: BoxDecoration(
          border: Border.all(color: const Color(0xFFD7DAD3)),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: 'Decrease $label',
              onPressed: saving ? null : minus,
              icon: const Icon(Icons.remove_rounded, size: 18, color: ink),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 48),
            ),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  style: const TextStyle(
                    fontSize: 26,
                    fontWeight: FontWeight.w800,
                    color: ink,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: 'Increase $label',
              onPressed: saving ? null : plus,
              icon: const Icon(Icons.add_rounded, size: 18, color: ink),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 36, minHeight: 48),
            ),
          ],
        ),
      ),
    ],
  );
  Future<void> _log(String id, int setNumber, bool pro) async {
    setState(() => saving = true);
    await ref
        .read(appProvider.notifier)
        .logSet(
          exerciseId: id,
          setNumber: setNumber,
          reps: reps,
          weightKg: weightKg,
        );
    if (mounted) {
      setState(() {
        saving = false;
        if (pro && ref.read(appProvider).error == null) {
          restUntil = DateTime.now().add(const Duration(seconds: 90));
        }
      });
    }
  }

  Future<void> _finish() async {
    setState(() => saving = true);
    await ref.read(appProvider.notifier).finishWorkout();
    if (!mounted) return;
    setState(() => saving = false);
    if (ref.read(appProvider).error == null) context.go('/workout-summary');
  }

  Future<void> _confirmFinish() async {
    final finish = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Finish this session?'),
        content: const Text(
          'Your completed sets will stay saved. Any remaining exercises will be marked as unfinished.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep going'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Finish session'),
          ),
        ],
      ),
    );
    if (finish == true) await _finish();
  }
}
