import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/state.dart';
import '../../dashboard/presentation/design.dart';
import '../domain/adaptive_insights.dart';

class AdaptiveInsightsScreen extends ConsumerStatefulWidget {
  const AdaptiveInsightsScreen({super.key});
  @override
  ConsumerState<AdaptiveInsightsScreen> createState() =>
      _AdaptiveInsightsScreenState();
}

class _AdaptiveInsightsScreenState
    extends ConsumerState<AdaptiveInsightsScreen> {
  final requestedProtein = TextEditingController();
  final proteinForm = GlobalKey<FormState>();
  int? reviewedProteinTarget;
  bool applying = false;
  @override
  void initState() {
    super.initState();
    requestedProtein.text = '${ref.read(appProvider).proteinTarget}';
  }

  @override
  void dispose() {
    requestedProtein.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider);
    if (!state.isPro) {
      return ScreenFrame(
        title: 'Adaptive insights',
        back: true,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            gap(20),
            iconBox(Icons.insights_outlined, size: 62),
            gap(24),
            heading('The patterns\nbehind your progress.', size: 32),
            gap(16),
            subtext(
              'Pro connects your logged activity, protein and weight trends to conservative suggestions. You approve every target change.',
            ),
            gap(26),
            PrimaryAction(
              'Explore LeanGuard Pro',
              onPressed: () => context.push('/paywall'),
            ),
            gap(16),
            TextButton(
              onPressed: () => context.go('/progress'),
              child: const Text('View my existing records'),
            ),
          ],
        ),
      );
    }
    final insights = AdaptiveInsights.evaluate(
      activities: state.activities,
      meals: state.rows('protein_entries'),
      weights: state.weights,
      workouts: state.workouts,
      proteinTarget: state.proteinTarget,
      stepTarget: state.stepTarget,
      allergies: List<String>.from(state.goalProfile['allergies'] ?? []),
      dietaryPreferences: List<String>.from(
        state.goalProfile['dietary_preferences'] ?? [],
      ),
      appetiteLevel:
          '${state.rows('medication_support_preferences').firstOrNull?['appetite_level'] ?? 'normal'}',
      requestedProteinTarget: reviewedProteinTarget,
      weeklyWorkoutTarget:
          (state.goalProfile['workouts_per_week'] as num?)?.toInt() ?? 3,
    );
    final distribution = insights.proteinDistribution;
    return ScreenFrame(
      title: 'Adaptive insights',
      back: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          eyebrow('Your logged data, explained', color: lime),
          gap(10),
          heading('Small adjustments.\nA steadier routine.', size: 31),
          gap(12),
          subtext(
            'These transparent habit rules use your recorded data. Suggestions do not diagnose health, measure muscle directly, or replace professional advice.',
          ),
          gap(22),
          DesignCard(
            gradient: const LinearGradient(
              colors: [Color(0xFF273322), Color(0xFF191F17)],
            ),
            border: const Color(0xFF3B4A31),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      eyebrow('Habit-based readiness', color: lime),
                      gap(9),
                      Text(
                        insights.readiness == null
                            ? 'Building your baseline'
                            : 'A signal from your recent routine',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                        ),
                      ),
                      gap(9),
                      subtext(
                        insights.readiness == null
                            ? 'A few more recorded days help this signal become useful.'
                            : 'Use this alongside how you feel. It is not medical clearance to exercise.',
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                RingStat(
                  value: (insights.readiness ?? 0) / 100,
                  label: insights.readiness == null
                      ? '—'
                      : '${insights.readiness}',
                  caption: '/100',
                  size: 72,
                ),
              ],
            ),
          ),
          if (insights.readinessEvidence.isNotEmpty) ...[
            gap(14),
            _evidence(insights.readinessEvidence),
          ],
          section('Walking target'),
          if (insights.walkingTarget != null)
            _targetCard(insights.walkingTarget!, steps: true)
          else
            DesignCard(
              child: subtext(
                'Keep your current walking target. Suggestions need enough recent, completed activity days and a clear pattern.',
              ),
            ),
          section('Protein rhythm'),
          if (distribution == null)
            DesignCard(
              child: subtext(
                'Log protein across at least three days to see how your recorded meals are distributed. Unlogged meals remain unknown.',
              ),
            )
          else
            DesignCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      iconBox(
                        Icons.restaurant_outlined,
                        color: const Color(0xFF4A3527),
                        foreground: orange,
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            heading(
                              distribution.loggedDays == 0
                                  ? 'No meals yet'
                                  : '${distribution.averageLoggedGrams.round()}g',
                              size: 28,
                            ),
                            gap(5),
                            subtext(
                              'average per logged day · ${distribution.loggedDays} days',
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  gap(17),
                  subtext(distribution.rationale),
                  if (distribution.mealTypeAverages.isNotEmpty) ...[
                    gap(15),
                    for (final entry in distribution.mealTypeAverages.entries)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _label(entry.key),
                                style: const TextStyle(fontSize: 13),
                              ),
                            ),
                            Text(
                              '${entry.value.toStringAsFixed(0)}g',
                              style: const TextStyle(
                                color: orange,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          gap(15),
          DesignCard(
            child: Form(
              key: proteinForm,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Review a protein target you choose',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                  ),
                  gap(9),
                  subtext(
                    'Use an established target or one discussed with a qualified professional. LeanGuard does not calculate a clinical nutrition prescription.',
                  ),
                  gap(16),
                  TextFormField(
                    controller: requestedProtein,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Protein target to review',
                      suffixText: 'g/day',
                    ),
                    validator: (input) {
                      final grams = int.tryParse(input ?? '');
                      return grams != null && grams >= 20 && grams <= 300
                          ? null
                          : 'Enter a whole number from 20 to 300.';
                    },
                  ),
                  gap(16),
                  PrimaryAction(
                    'Review this target',
                    onPressed: () {
                      if (proteinForm.currentState!.validate()) {
                        setState(
                          () => reviewedProteinTarget = int.parse(
                            requestedProtein.text,
                          ),
                        );
                      }
                    },
                  ),
                ],
              ),
            ),
          ),
          gap(15),
          if (insights.proteinTarget != null)
            _targetCard(insights.proteinTarget!, steps: false)
          else
            DesignCard(
              child: subtext(
                reviewedProteinTarget == null
                    ? 'Your current protein goal remains unchanged.'
                    : 'No change is proposed. A review needs at least seven logged protein days and a requested change within 10% of your current goal.',
              ),
            ),
          section('Weight context'),
          DesignCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                eyebrow('Weekly-average pace'),
                gap(10),
                heading(
                  insights.weightPace == null
                      ? 'More data needed'
                      : '${insights.weightPace!.abs().toStringAsFixed(2)}% ${insights.weightPace! >= 0 ? 'loss' : 'gain'} / week',
                  size: 25,
                ),
                gap(10),
                subtext(
                  insights.weightPace == null
                      ? 'Log weight across multiple weeks to compare weekly averages.'
                      : 'Based on recorded weekly averages. The scale cannot tell you how much change is muscle, fat or water.',
                ),
                const Divider(height: 28),
                Text(
                  insights.plateau == null
                      ? 'Plateau signal: not enough history yet.'
                      : insights.plateau!
                      ? 'Your recent weekly averages show little change.'
                      : 'Your recent weekly averages are changing.',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
                  ),
                ),
                gap(8),
                subtext(
                  'Review persistent changes alongside strength, habits and professional guidance. Avoid reacting to a single weigh-in.',
                ),
              ],
            ),
          ),
          section('Activity & active energy'),
          DesignCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                heading(
                  insights.energyStepCorrelation == null
                      ? 'Gathering paired days'
                      : 'r = ${insights.energyStepCorrelation!.toStringAsFixed(2)}',
                  size: 25,
                ),
                gap(10),
                subtext(
                  '${insights.correlationSamples} days with both step and active-energy records.',
                ),
                gap(10),
                subtext(
                  insights.energyStepCorrelation == null
                      ? 'More varied shared records are needed before a correlation can be shown.'
                      : 'This describes an association in your recorded data, not cause and effect or a measure of health.',
                ),
              ],
            ),
          ),
          section('Practical next steps'),
          if (insights.suggestions.isEmpty)
            DesignCard(
              child: subtext(
                'Keep logging your usual routine. Suggestions appear when there is enough context.',
              ),
            ),
          for (final suggestion in insights.suggestions)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: DesignCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      suggestion.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                    gap(9),
                    subtext(suggestion.description),
                    if (suggestion.evidence.isNotEmpty) ...[
                      gap(12),
                      _evidence(suggestion.evidence),
                    ],
                  ],
                ),
              ),
            ),
          gap(10),
          PrimaryAction(
            'Discuss this with Lean Coach',
            icon: Icons.auto_awesome_outlined,
            onPressed: () => context.go('/coach'),
          ),
          gap(18),
        ],
      ),
    );
  }

  String _label(String value) => value.isEmpty
      ? value
      : '${value[0].toUpperCase()}${value.substring(1).replaceAll('_', ' ')}';
  Widget _evidence(List<String> facts) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (final fact in facts)
        Padding(
          padding: const EdgeInsets.only(bottom: 7),
          child: Text(
            '• $fact',
            style: const TextStyle(color: muted, fontSize: 12, height: 1.5),
          ),
        ),
    ],
  );
  Widget _targetCard(
    TargetRecommendation recommendation, {
    required bool steps,
  }) => DesignCard(
    border: recommendation.isRecovery
        ? const Color(0xFF735535)
        : const Color(0xFF3A4F30),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        eyebrow(
          steps
              ? (recommendation.isRecovery
                    ? 'A gentler return to consistency'
                    : 'A gradual next step')
              : 'Your protein target',
          color: steps ? blue : orange,
        ),
        gap(13),
        Wrap(
          spacing: 14,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '${recommendation.currentTarget}',
              style: const TextStyle(
                color: muted,
                fontSize: 23,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Icon(Icons.arrow_forward_rounded, color: muted, size: 21),
            Text(
              '${recommendation.suggestedTarget} ${steps ? 'steps' : 'g'}',
              style: TextStyle(
                color: steps ? blue : orange,
                fontSize: 28,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        gap(12),
        subtext(recommendation.rationale),
        if (recommendation.evidence.isNotEmpty) ...[
          gap(12),
          _evidence(recommendation.evidence),
        ],
        gap(15),
        if (recommendation.requiresApproval &&
            recommendation.suggestedTarget != recommendation.currentTarget)
          PrimaryAction(
            steps ? 'Review walking target' : 'Review protein target',
            busy: applying,
            onPressed: () => _approve(recommendation, steps: steps),
          )
        else
          const Text(
            'Your current target stays unchanged.',
            style: TextStyle(color: muted, fontSize: 12),
          ),
      ],
    ),
  );
  Future<void> _approve(
    TargetRecommendation recommendation, {
    required bool steps,
  }) async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Update your ${steps ? 'walking' : 'protein'} target?'),
        content: Text(
          'Change your daily target from ${recommendation.currentTarget} to ${recommendation.suggestedTarget} ${steps ? 'steps' : 'grams'}?\n\n${recommendation.rationale}\n\nYou can adjust your preferences later. Follow any limits your healthcare professional has given you.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep current target'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Approve target'),
          ),
        ],
      ),
    );
    if (approved != true || !mounted) return;
    setState(() => applying = true);
    try {
      await ref
          .read(appProvider.notifier)
          .applyAdaptiveTarget(
            steps: steps ? recommendation.suggestedTarget : null,
            protein: steps ? null : recommendation.suggestedTarget,
          );
      if (mounted) {
        setState(() => reviewedProteinTarget = null);
        showMessage(context, 'Your approved target is saved.');
      }
    } catch (error) {
      ref.read(appProvider.notifier).reportError(error);
    } finally {
      if (mounted) setState(() => applying = false);
    }
  }
}
