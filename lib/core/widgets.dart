import 'package:flutter/material.dart';
import 'theme.dart';

class LGPage extends StatelessWidget {
  const LGPage({
    super.key,
    required this.title,
    required this.child,
    this.dark = true,
    this.actions,
    this.bottom,
  });
  final String title;
  final Widget child;
  final bool dark;
  final List<Widget>? actions;
  final Widget? bottom;
  @override
  Widget build(BuildContext context) => Theme(
    data: LG.theme(dark: dark),
    child: Builder(
      builder: (context) => Scaffold(
        appBar: AppBar(title: Text(title), actions: actions),
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 680),
              child: child,
            ),
          ),
        ),
        bottomNavigationBar: bottom,
      ),
    ),
  );
}

class LGCard extends StatelessWidget {
  const LGCard({super.key, required this.child, this.color, this.onTap});
  final Widget child;
  final Color? color;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Card(
    color: color,
    margin: const EdgeInsets.symmetric(vertical: 8),
    child: InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(padding: const EdgeInsets.all(18), child: child),
    ),
  );
}

class LGButton extends StatelessWidget {
  const LGButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.secondary = false,
    this.icon,
  });
  final String label;
  final VoidCallback? onPressed;
  final bool secondary;
  final IconData? icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: secondary
        ? OutlinedButton(onPressed: onPressed, child: Text(label))
        : FilledButton(
            onPressed: onPressed,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(child: Text(label, textAlign: TextAlign.center)),
                if (icon != null) ...[const SizedBox(width: 8), Icon(icon)],
              ],
            ),
          ),
  );
}

class SectionTitle extends StatelessWidget {
  const SectionTitle(this.title, {super.key, this.action});
  final String title;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        ?action,
      ],
    ),
  );
}

class StatRing extends StatelessWidget {
  const StatRing({
    super.key,
    required this.progress,
    required this.label,
    required this.caption,
    this.color = LG.lime,
  });
  final double progress;
  final String label, caption;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: 90,
    height: 90,
    child: Stack(
      alignment: Alignment.center,
      children: [
        SizedBox.expand(
          child: CircularProgressIndicator(
            value: progress.clamp(0, 1),
            strokeWidth: 5,
            color: color,
            backgroundColor: color.withValues(alpha: .12),
          ),
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.bold),
            ),
            Text(caption, style: const TextStyle(fontSize: 11)),
          ],
        ),
      ],
    ),
  );
}
