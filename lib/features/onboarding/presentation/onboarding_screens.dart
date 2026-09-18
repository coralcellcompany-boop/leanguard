import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/state.dart';
import '../../dashboard/presentation/design.dart';

class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => ScreenFrame(
    title: 'LeanGuard',
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 310,
          child: Center(
            child: Stack(
              alignment: Alignment.center,
              children: [
                for (final size in [290.0, 230.0, 164.0])
                  Container(
                    width: size,
                    height: size,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: size == 164
                            ? const Color(0xFF44513A)
                            : const Color(0xFF2B3428),
                      ),
                      gradient: size == 164
                          ? const RadialGradient(
                              colors: [Color(0xFF293421), Color(0xFF171A17)],
                            )
                          : null,
                    ),
                  ),
                const Icon(Icons.fitness_center_rounded, size: 58, color: lime),
                Positioned(top: 24, right: 9, child: _orbitLabel('STRENGTH')),
                Positioned(bottom: 56, left: 0, child: _orbitLabel('PROTEIN')),
                Positioned(
                  bottom: 12,
                  right: 10,
                  child: _orbitLabel('RECOVERY'),
                ),
              ],
            ),
          ),
        ),
        eyebrow('Your muscle matters', color: lime),
        gap(10),
        heading('Lose weight.', size: 40),
        heading('Keep your muscle.', size: 40, color: lime),
        gap(16),
        subtext(
          'A smarter plan to protect muscle, build strong habits, and feel capable throughout your weight-loss journey.',
        ),
        gap(26),
        PrimaryAction(
          'Build my plan',
          icon: Icons.arrow_forward_rounded,
          onPressed: () => context.go('/auth'),
        ),
        gap(8),
        Center(
          child: TextButton(
            onPressed: () => context.push('/auth'),
            child: const Text(
              'I already have an account',
              style: TextStyle(color: paper),
            ),
          ),
        ),
        Center(
          child: TextButton(
            onPressed: () async {
              await ref.read(appProvider.notifier).enterDemo();
              if (context.mounted) context.go('/today');
            },
            child: const Text(
              'Explore a sample plan',
              style: TextStyle(color: muted, fontSize: 12),
            ),
          ),
        ),
      ],
    ),
  );
  static Widget _orbitLabel(String label) => Container(
    color: const Color(0xFF171A17),
    padding: const EdgeInsets.all(6),
    child: eyebrow(label),
  );
}

class GoalsScreen extends ConsumerStatefulWidget {
  const GoalsScreen({super.key});
  @override
  ConsumerState<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends ConsumerState<GoalsScreen> {
  late Set<String> selected;
  @override
  void initState() {
    super.initState();
    selected = ref.read(appProvider).goals.toSet();
    if (selected.isEmpty) selected = {'Keep my muscle', 'Get stronger'};
  }

  @override
  Widget build(BuildContext context) {
    const choices = [
      ('Keep my muscle', Icons.shield_outlined),
      ('Get stronger', Icons.fitness_center_rounded),
      ('Move more', Icons.directions_walk_rounded),
      ('Build protein habits', Icons.restaurant_rounded),
    ];
    return ScreenFrame(
      title: '',
      dark: false,
      back: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LinearProgressIndicator(
            value: 1 / 3,
            minHeight: 3,
            color: ink,
            backgroundColor: Color(0xFFDEE1DA),
          ),
          gap(30),
          eyebrow('1 of 3 · Your goals', color: const Color(0xFF637048)),
          gap(12),
          heading('What matters most\nduring your journey?', size: 31),
          gap(14),
          subtext(
            'Choose all that apply. Your plan will focus on what you want to protect and improve.',
            color: const Color(0xFF747B75),
          ),
          gap(26),
          for (final option in choices)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Semantics(
                selected: selected.contains(option.$1),
                button: true,
                child: DesignCard(
                  color: selected.contains(option.$1)
                      ? const Color(0xFFEFF6E4)
                      : const Color(0xFFFAFBF7),
                  border: selected.contains(option.$1) ? ink : null,
                  onTap: () => setState(() {
                    selected.contains(option.$1)
                        ? selected.remove(option.$1)
                        : selected.add(option.$1);
                  }),
                  child: Row(
                    children: [
                      iconBox(
                        option.$2,
                        color: selected.contains(option.$1)
                            ? lime
                            : const Color(0xFFE5E8E1),
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Text(
                          option.$1,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                      ),
                      Icon(
                        selected.contains(option.$1)
                            ? Icons.check_circle_rounded
                            : Icons.radio_button_unchecked_rounded,
                        color: selected.contains(option.$1) ? ink : muted,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          gap(30),
          PrimaryAction(
            'Continue',
            dark: true,
            icon: Icons.arrow_forward_rounded,
            busy: ref.watch(appProvider).busy,
            onPressed: selected.isEmpty
                ? null
                : () async {
                    await ref
                        .read(appProvider.notifier)
                        .setGoals(selected.toList());
                    if (context.mounted) context.go('/glp');
                  },
          ),
        ],
      ),
    );
  }
}

class GlpScreen extends ConsumerWidget {
  const GlpScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    return ScreenFrame(
      dark: false,
      back: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const LinearProgressIndicator(
            value: 2 / 3,
            minHeight: 3,
            color: ink,
            backgroundColor: Color(0xFFDEE1DA),
          ),
          gap(30),
          eyebrow('2 of 3 · Personalize', color: const Color(0xFF637048)),
          gap(12),
          heading('Are you using a\nGLP-1 medication?', size: 31),
          gap(14),
          subtext(
            'Optional support for users already taking medication under their clinician’s care. Keep protein, hydration and movement in your routine.',
            color: const Color(0xFF747B75),
          ),
          gap(26),
          DesignCard(
            color: state.glpEnabled ? const Color(0xFFF0F7E5) : Colors.white,
            border: state.glpEnabled ? const Color(0xFF95B951) : null,
            child: Column(
              children: [
                Row(
                  children: [
                    iconBox(
                      Icons.monitor_heart_outlined,
                      color: const Color(0xFFE5E8E1),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Enable GLP-1 support',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                            ),
                          ),
                          gap(4),
                          subtext(
                            'Under the care of my clinician',
                            color: const Color(0xFF767D77),
                          ),
                        ],
                      ),
                    ),
                    Switch.adaptive(
                      value: state.glpEnabled,
                      activeTrackColor: ink,
                      onChanged: (value) =>
                          ref.read(appProvider.notifier).setGlp(value),
                    ),
                  ],
                ),
                if (state.glpEnabled) ...[
                  const Divider(height: 28),
                  for (final label in [
                    'Safety information and routine support',
                    'Medication decisions stay with your clinician',
                    'Appetite and energy-aware coaching with Pro',
                  ])
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Row(
                        children: [
                          const Icon(Icons.check_rounded, size: 16),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              label,
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ],
            ),
          ),
          gap(18),
          DesignCard(
            color: const Color(0xFFE8EAE5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.info_outline_rounded,
                  size: 20,
                  color: Color(0xFF626963),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: subtext(
                    'LeanGuard does not diagnose, prescribe, or change medication. Always follow your clinician’s guidance.',
                    color: const Color(0xFF626963),
                  ),
                ),
              ],
            ),
          ),
          gap(34),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(54),
                    foregroundColor: ink,
                  ),
                  onPressed: () async {
                    await ref.read(appProvider.notifier).setGlp(false);
                    if (context.mounted) context.go('/health-permission');
                  },
                  child: const Text('Not now'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: PrimaryAction(
                  'Continue',
                  dark: true,
                  onPressed: () => context.go('/health-permission'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
