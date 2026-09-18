import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/state.dart';
import '../../../core/domain/policies.dart';
import '../../dashboard/presentation/design.dart';

class CoachScreen extends ConsumerStatefulWidget {
  const CoachScreen({super.key});
  @override
  ConsumerState<CoachScreen> createState() => _CoachScreenState();
}

class _CoachScreenState extends ConsumerState<CoachScreen> {
  final query = TextEditingController();
  final scroll = ScrollController();
  bool sending = false;
  @override
  void dispose() {
    query.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(appProvider);
    return ScreenFrame(
      title: 'Lean Coach',
      tab: 3,
      padding: false,
      actions: [
        IconButton(
          tooltip: 'Coaching information',
          onPressed: () => showDialog<void>(
            context: context,
            builder: (context) => AlertDialog(
              title: const Text('Your wellness coach'),
              content: const Text(
                'Lean Coach uses your recent logged data and preferences. AI can make mistakes. It does not diagnose, prescribe medication or change GLP-1 dosage. Plan changes always need your approval.\n\nFor pain, fainting, dehydration or severe weakness, seek appropriate professional care.',
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Got it'),
                ),
              ],
            ),
          ),
          icon: const Icon(Icons.info_outline_rounded),
        ),
      ],
      bottom: Container(
        color: ink,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: query,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 2000,
                    enabled: !sending,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    style: const TextStyle(color: paper, fontSize: 14),
                    decoration: InputDecoration(
                      hintText: 'Ask about your progress…',
                      hintStyle: const TextStyle(color: muted),
                      counterText: '',
                      filled: true,
                      fillColor: const Color(0xFF202420),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(15),
                        borderSide: const BorderSide(color: Color(0xFF333934)),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 13,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 9),
                SizedBox(
                  width: 49,
                  height: 49,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: lime,
                      foregroundColor: ink,
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: sending ? null : _send,
                    child: sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.arrow_forward_rounded),
                  ),
                ),
              ],
            ),
            gap(8),
            Text(
              '${state.coachRemaining} questions remaining this month · Wellness support, not medical advice',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 9, color: muted),
            ),
          ],
        ),
      ),
      child: ListView(
        controller: scroll,
        padding: const EdgeInsets.fromLTRB(18, 12, 18, 24),
        children: [
          if (!_hasAiConsent) ...[
            DesignCard(
              border: const Color(0xFF4C5C3C),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Choose what you share',
                    style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                  ),
                  gap(8),
                  subtext(
                    'With your permission, LeanGuard sends relevant recent health logs and preferences to our secure coaching service and AI provider to create personalized suggestions.',
                  ),
                  gap(14),
                  PrimaryAction(
                    'Enable AI coaching',
                    onPressed: _requestConsent,
                  ),
                  TextButton(
                    onPressed: () => context.push('/privacy'),
                    child: const Text('Privacy and consent controls'),
                  ),
                ],
              ),
            ),
            gap(20),
          ],
          Center(child: iconBox(Icons.auto_awesome_rounded, size: 54)),
          gap(15),
          Center(child: heading('Your plan, explained.', size: 23)),
          gap(9),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'I use your strength, activity, protein and weight trends to help you make practical adjustments.',
              textAlign: TextAlign.center,
              style: TextStyle(color: muted, fontSize: 13, height: 1.5),
            ),
          ),
          gap(23),
          Center(child: eyebrow('Today')),
          gap(18),
          if (state.messages.isEmpty)
            _bubble(
              'Welcome to Lean Coach. Start with a weekly review, or ask about your strength plan, protein habits or daily movement. I’ll explain which logged facts inform each suggestion.',
              false,
            ),
          if (state.messages.isEmpty) ...[
            gap(6),
            DesignCard(
              color: const Color(0xFF1E251C),
              border: const Color(0xFF3B4A32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  eyebrow('Your weekly review', color: lime),
                  gap(7),
                  const Text(
                    'Protect muscle. Build consistency.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  gap(6),
                  subtext(
                    'Bring together your recent logs and choose up to three practical next steps.',
                  ),
                  gap(9),
                  TextButton.icon(
                    onPressed: sending ? null : () => _send(weekly: true),
                    icon: const Icon(Icons.auto_awesome_rounded, size: 17),
                    label: const Text('Generate my weekly summary'),
                  ),
                ],
              ),
            ),
          ],
          for (final message in state.messages) ...[
            _bubble('${message['content'] ?? ''}', message['role'] == 'user'),
            if (message['role'] != 'user') _structuredInsight(message),
          ],
          if (sending)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 15),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: lime,
                      ),
                    ),
                    const SizedBox(width: 10),
                    subtext('Reviewing your recent logs…'),
                  ],
                ),
              ),
            ),
          if (state.proposal != null) ...[
            gap(12),
            DesignCard(
              color: const Color(0xFF26301F),
              border: const Color(0xFF617A43),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  eyebrow('Suggested plan change', color: lime),
                  gap(8),
                  const Text(
                    'You stay in control.',
                    style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800),
                  ),
                  gap(8),
                  subtext(
                    '${state.proposal!['rationale'] ?? state.proposal!['explanation'] ?? state.proposal!['reason'] ?? state.proposal!['summary'] ?? 'Review the proposed conservative adjustment before applying it.'}',
                  ),
                  gap(14),
                  PrimaryAction(
                    'Review adjustment',
                    onPressed: () => _reviewProposal(state.proposal!),
                  ),
                ],
              ),
            ),
          ],
          gap(20),
          Wrap(
            spacing: 7,
            runSpacing: 8,
            children: [
              for (final suggestion in [
                'Should I increase my weights?',
                'Help me hit my protein target',
                'How is my consistency?',
              ])
                ActionChip(
                  label: Text(
                    suggestion,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Color(0xFFAFB5AF),
                    ),
                  ),
                  backgroundColor: ink,
                  side: const BorderSide(color: Color(0xFF323833)),
                  onPressed: sending
                      ? null
                      : () {
                          query.text = suggestion;
                          query.selection = TextSelection.collapsed(
                            offset: query.text.length,
                          );
                        },
                ),
            ],
          ),
          if (state.messages.isNotEmpty) ...[
            gap(14),
            TextButton.icon(
              onPressed: sending ? null : () => _send(weekly: true),
              icon: const Icon(Icons.calendar_view_week_rounded, size: 18),
              label: const Text('Weekly summary'),
            ),
          ],
          TextButton.icon(
            onPressed: sending
                ? null
                : () => state.isPro
                      ? _send(adaptation: true)
                      : context.push('/paywall'),
            icon: const Icon(Icons.tune_rounded, size: 18),
            label: const Text('Review a plan adjustment'),
          ),
          if (state.coachRemaining <= 0 && !state.isPro) ...[
            gap(14),
            DesignCard(
              child: Column(
                children: [
                  const Text(
                    'You’ve used this month’s coach questions.',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  gap(8),
                  subtext(
                    'Your logs and previous conversations remain available.',
                  ),
                  gap(14),
                  PrimaryAction(
                    'Explore LeanGuard Pro',
                    onPressed: () => context.push('/paywall'),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _bubble(String text, bool user) => Align(
    alignment: user ? Alignment.centerRight : Alignment.centerLeft,
    child: Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.sizeOf(context).width * 0.84,
      ),
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: user ? lime : const Color(0xFF232824),
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(17),
          topRight: const Radius.circular(17),
          bottomLeft: Radius.circular(user ? 17 : 5),
          bottomRight: Radius.circular(user ? 5 : 17),
        ),
      ),
      child: SelectableText(
        text,
        style: TextStyle(color: user ? ink : paper, fontSize: 14, height: 1.5),
      ),
    ),
  );

  Widget _structuredInsight(Map<String, dynamic> message) {
    final evidence = message['evidence'] is List
        ? message['evidence'] as List
        : [];
    final actions = message['actions'] is List
        ? message['actions'] as List
        : [];
    if (evidence.isEmpty && actions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: DesignCard(
        color: const Color(0xFF1E251C),
        border: const Color(0xFF3B4A32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (evidence.isNotEmpty) ...[
              eyebrow('From your logged data', color: lime),
              gap(10),
              for (final fact in evidence)
                Padding(
                  padding: const EdgeInsets.only(bottom: 7),
                  child: Text(
                    '• $fact',
                    style: const TextStyle(
                      fontSize: 12,
                      color: muted,
                      height: 1.5,
                    ),
                  ),
                ),
            ],
            if (actions.isNotEmpty) ...[
              gap(5),
              const Text(
                'Your next steps',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
              gap(9),
              for (var i = 0; i < actions.length && i < 3; i++)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    '${i + 1}. ${actions[i]}',
                    style: const TextStyle(fontSize: 13, height: 1.5),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _send({bool weekly = false, bool adaptation = false}) async {
    final text = weekly
        ? 'Review my week and suggest up to three next actions based on my logged data.'
        : adaptation
        ? 'Review my logged strength sessions and suggest a conservative plan adjustment only if the evidence supports it. Explain the data used.'
        : query.text.trim();
    if (text.isEmpty || sending) return;
    final localSafetyReply = CoachSafety.localEscalation(text) != null;
    if (!localSafetyReply && !_hasAiConsent && !await _requestConsent()) return;
    if (!mounted) return;
    if (!localSafetyReply &&
        !weekly &&
        ref.read(appProvider).coachRemaining <= 0) {
      if (!ref.read(appProvider).isPro) {
        context.push('/paywall');
      } else {
        showMessage(
          context,
          'Your monthly fair-use allowance has been used. Your previous conversations remain available.',
        );
      }
      return;
    }
    setState(() => sending = true);
    if (!weekly) query.clear();
    await ref
        .read(appProvider.notifier)
        .askCoach(
          text,
          kind: weekly
              ? 'weekly'
              : adaptation
              ? 'adaptation'
              : 'question',
        );
    if (!mounted) return;
    setState(() => sending = false);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (scroll.hasClients) {
        scroll.animateTo(
          scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  bool get _hasAiConsent {
    final records =
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
    return records.isNotEmpty && records.last['granted'] == true;
  }

  Future<bool> _requestConsent() async {
    final approved = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enable personalized AI coaching?'),
        content: const Text(
          'LeanGuard will process relevant weight, workout, strength, protein, activity and preference records through its secure server and AI provider. Your medication support preference may be included if enabled.\n\nAI may make mistakes. You can withdraw this permission in Privacy & data. Your normal logging features do not require AI consent.',
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
    if (approved != true) return false;
    try {
      await ref.read(appProvider.notifier).recordConsent('ai_processing', true);
      return true;
    } catch (error) {
      ref.read(appProvider.notifier).reportError(error);
      return false;
    }
  }

  Future<void> _reviewProposal(Map<String, dynamic> proposal) async {
    final approved = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 8, 22, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              heading('Review your plan change', size: 25),
              gap(14),
              subtext(
                '${proposal['rationale'] ?? proposal['explanation'] ?? proposal['reason'] ?? proposal['summary'] ?? 'A conservative change based on your recent logs.'}',
              ),
              gap(16),
              for (final change in (proposal['changes'] as List? ?? []))
                _proposalChange(Map<String, dynamic>.from(change as Map)),
              gap(10),
              subtext(
                'Apply only if the change feels manageable and your technique stays comfortable. Stop for pain or warning signs.',
              ),
              gap(22),
              PrimaryAction(
                'Approve and update my plan',
                onPressed: () => Navigator.pop(context, true),
              ),
              gap(8),
              Center(
                child: TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Keep my current plan'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (approved == true) {
      await ref.read(appProvider.notifier).approveProposal();
      if (mounted && ref.read(appProvider).error == null) {
        showMessage(context, 'Your approved plan change has been saved.');
      }
    }
  }

  Widget _proposalChange(Map<String, dynamic> change) {
    final state = ref.read(appProvider);
    final rows = state
        .rows('workout_exercises')
        .where((row) => row['id'] == change['workout_exercise_id']);
    final row = rows.isEmpty ? <String, dynamic>{} : rows.first;
    final exercises = state.exercises.where(
      (exercise) => exercise['id'] == row['exercise_id'],
    );
    final name = exercises.isEmpty
        ? 'Planned exercise'
        : '${exercises.first['name']}';
    final kg = (change['target_weight_kg'] as num?)?.toDouble() ?? 0;
    final weight = state.units == 'lb' ? kg * 2.2046226218 : kg;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(name, style: const TextStyle(fontWeight: FontWeight.w700)),
          gap(5),
          Text(
            '${change['target_sets']} sets × ${change['target_reps']} reps · ${weight.toStringAsFixed(1)} ${state.units}',
            style: const TextStyle(fontSize: 13, height: 1.5),
          ),
        ],
      ),
    );
  }
}
