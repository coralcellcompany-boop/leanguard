import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/state.dart';

const ink = Color(0xFF121513);
const paper = Color(0xFFF3F4EF);
const lime = Color(0xFFB9F34A);
const orange = Color(0xFFFF9F54);
const blue = Color(0xFF65D9FF);
const muted = Color(0xFF929892);

class ScreenFrame extends ConsumerWidget {
  const ScreenFrame({
    super.key,
    this.title = '',
    required this.child,
    this.dark = true,
    this.tab,
    this.actions = const [],
    this.bottom,
    this.back = false,
    this.padding = true,
  });
  final String title;
  final Widget child;
  final bool dark, back, padding;
  final int? tab;
  final List<Widget> actions;
  final Widget? bottom;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(appProvider);
    final base = Theme.of(context);
    final theme = base.copyWith(
      brightness: dark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: dark ? ink : paper,
      colorScheme:
          ColorScheme.fromSeed(
            seedColor: lime,
            brightness: dark ? Brightness.dark : Brightness.light,
          ).copyWith(
            primary: dark ? lime : ink,
            surface: dark ? ink : paper,
            onSurface: dark ? paper : ink,
          ),
      textTheme: base.textTheme.apply(
        bodyColor: dark ? paper : ink,
        displayColor: dark ? paper : ink,
      ),
      iconTheme: IconThemeData(color: dark ? paper : ink),
      dividerColor: dark ? const Color(0xFF303630) : const Color(0xFFDDE2D7),
      chipTheme: ChipThemeData(
        backgroundColor: dark ? const Color(0xFF242A24) : Colors.white,
        selectedColor: dark
            ? const Color(0xFF385022)
            : const Color(0xFFD7E7BC),
        checkmarkColor: dark ? lime : ink,
        labelStyle: (base.textTheme.labelLarge ?? const TextStyle()).copyWith(
          color: dark ? paper : ink,
          fontWeight: FontWeight.w600,
        ),
        side: BorderSide(
          color: dark ? const Color(0xFF3C463B) : const Color(0xFFD1D8CD),
        ),
      ),
    );
    return Theme(
      data: theme,
      child: Builder(
        builder: (context) => Scaffold(
          backgroundColor: dark ? ink : paper,
          appBar: AppBar(
            backgroundColor: dark ? ink : paper,
            foregroundColor: dark ? paper : ink,
            surfaceTintColor: Colors.transparent,
            automaticallyImplyLeading: false,
            centerTitle: true,
            leading: back
                ? IconButton(
                    tooltip: 'Go back',
                    onPressed: () =>
                        context.canPop() ? context.pop() : context.go('/today'),
                    icon: const Icon(Icons.arrow_back_rounded),
                  )
                : Padding(
                    padding: const EdgeInsets.all(13),
                    child: Container(
                      decoration: BoxDecoration(
                        color: lime,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: const Icon(
                        Icons.fitness_center_rounded,
                        color: ink,
                        size: 19,
                      ),
                    ),
                  ),
            title: Text(
              title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700),
            ),
            actions: [...actions, const SizedBox(width: 8)],
          ),
          body: SafeArea(
            top: false,
            child: Column(
              children: [
                if (state.offline)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(10),
                    color: const Color(0xFF4E4328),
                    child: const Text(
                      'Offline · Your saved data is available. Changes sync when you reconnect.',
                      style: TextStyle(fontSize: 12, color: Colors.white),
                    ),
                  ),
                if (state.demo)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 7,
                    ),
                    color: const Color(0xFF2A3421),
                    child: const Text(
                      'PREVIEW · Sample data, stored on this device',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 0.8,
                        color: lime,
                      ),
                    ),
                  ),
                if (state.error != null)
                  MaterialBanner(
                    content: Text(
                      state.error!,
                      style: const TextStyle(fontSize: 12),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () =>
                            ref.read(appProvider.notifier).clearError(),
                        child: const Text('Dismiss'),
                      ),
                    ],
                  ),
                Expanded(
                  child: padding
                      ? SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                          child: child,
                        )
                      : child,
                ),
                ?bottom,
              ],
            ),
          ),
          bottomNavigationBar: tab == null
              ? null
              : NavigationBar(
                  height: 72,
                  selectedIndex: tab!,
                  backgroundColor: dark ? ink : paper,
                  indicatorColor: dark
                      ? const Color(0xFF2B3524)
                      : const Color(0xFFE0E9D1),
                  onDestinationSelected: (i) => context.go(
                    ['/today', '/plan', '/progress', '/coach', '/settings'][i],
                  ),
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.home_outlined),
                      selectedIcon: Icon(Icons.home_rounded),
                      label: 'Today',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.fitness_center_rounded),
                      label: 'Plan',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.show_chart_rounded),
                      label: 'Progress',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.auto_awesome_outlined),
                      label: 'Coach',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.account_circle_outlined),
                      label: 'You',
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

class DesignCard extends StatelessWidget {
  const DesignCard({
    super.key,
    required this.child,
    this.color,
    this.border,
    this.onTap,
    this.padding = 16,
    this.gradient,
  });
  final Widget child;
  final Color? color, border;
  final VoidCallback? onTap;
  final double padding;
  final Gradient? gradient;
  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            color: color ?? (dark ? const Color(0xFF1C201D) : Colors.white),
            gradient: gradient,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color:
                  border ??
                  (dark ? const Color(0xFF303630) : const Color(0xFFDEE2D9)),
            ),
          ),
          padding: EdgeInsets.all(padding),
          child: child,
        ),
      ),
    );
  }
}

class PrimaryAction extends StatelessWidget {
  const PrimaryAction(
    this.label, {
    super.key,
    required this.onPressed,
    this.icon,
    this.dark = false,
    this.busy = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool dark, busy;
  @override
  Widget build(BuildContext context) => SizedBox(
    width: double.infinity,
    height: 54,
    child: FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: dark ? ink : lime,
        foregroundColor: dark ? Colors.white : ink,
        disabledBackgroundColor: const Color(0xFF69715F),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
      ),
      onPressed: busy ? null : onPressed,
      child: busy
          ? const SizedBox(
              height: 22,
              width: 22,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    label,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                if (icon != null) ...[
                  const SizedBox(width: 10),
                  Icon(icon, size: 19),
                ],
              ],
            ),
    ),
  );
}

Widget eyebrow(String text, {Color color = muted}) => Text(
  text.toUpperCase(),
  style: TextStyle(
    fontSize: 10,
    letterSpacing: 1.35,
    fontWeight: FontWeight.w800,
    color: color,
  ),
);
Widget heading(String text, {double size = 28, Color? color}) => Text(
  text,
  style: TextStyle(
    fontSize: size,
    height: 1.1,
    letterSpacing: -0.9,
    fontWeight: FontWeight.w800,
    color: color,
  ),
);
Widget subtext(String text, {Color color = muted}) =>
    Text(text, style: TextStyle(color: color, fontSize: 13, height: 1.5));
Widget section(String title, {Widget? trailing}) => Padding(
  padding: const EdgeInsets.only(top: 24, bottom: 12),
  child: Row(
    children: [
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.3,
          ),
        ),
      ),
      ?trailing,
    ],
  ),
);
Widget iconBox(
  IconData icon, {
  Color color = lime,
  Color foreground = ink,
  double size = 40,
}) => Container(
  width: size,
  height: size,
  decoration: BoxDecoration(
    color: color,
    borderRadius: BorderRadius.circular(12),
  ),
  child: Icon(icon, color: foreground, size: 21),
);
Widget gap([double height = 14]) => SizedBox(height: height);

class RingStat extends StatelessWidget {
  const RingStat({
    super.key,
    required this.value,
    required this.label,
    required this.caption,
    this.color = lime,
    this.size = 78,
  });
  final double value, size;
  final String label, caption;
  final Color color;
  @override
  Widget build(BuildContext context) => Semantics(
    label: '$label $caption',
    child: SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox.expand(
            child: CircularProgressIndicator(
              value: value.clamp(0, 1),
              strokeWidth: 5,
              color: color,
              backgroundColor: Theme.of(context).dividerColor,
              strokeCap: StrokeCap.round,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    caption,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 9, color: muted),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

class SettingRow extends StatelessWidget {
  const SettingRow(
    this.title,
    this.subtitle,
    this.icon, {
    super.key,
    this.onTap,
    this.trailing,
    this.iconColor,
  });
  final String title, subtitle;
  final IconData icon;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color? iconColor;
  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 2),
      child: Row(
        children: [
          iconBox(icon, color: iconColor ?? const Color(0xFFE8EBE4)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 3),
                subtext(subtitle),
              ],
            ),
          ),
          trailing ?? const Icon(Icons.chevron_right_rounded, size: 20),
        ],
      ),
    ),
  );
}

void showMessage(BuildContext context, String message) => ScaffoldMessenger.of(
  context,
).showSnackBar(SnackBar(content: Text(message)));

class TrendChart extends StatelessWidget {
  const TrendChart(this.values, {super.key, this.color = lime});
  final List<double> values;
  final Color color;
  @override
  Widget build(BuildContext context) => SizedBox(
    height: 140,
    width: double.infinity,
    child: values.isEmpty
        ? Center(child: subtext('Log your first weight to see your trend.'))
        : Semantics(
            label:
                'Weight trend from ${values.first.toStringAsFixed(1)} to ${values.last.toStringAsFixed(1)}',
            child: CustomPaint(painter: _TrendPainter(values, color)),
          ),
  );
}

class _TrendPainter extends CustomPainter {
  _TrendPainter(this.values, this.color);
  final List<double> values;
  final Color color;
  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = const Color(0xFF323832)
      ..strokeWidth = 1;
    for (var i = 1; i < 4; i++) {
      canvas.drawLine(
        Offset(0, size.height * i / 4),
        Offset(size.width, size.height * i / 4),
        grid,
      );
    }
    final low = values.reduce(math.min), high = values.reduce(math.max);
    final range = math.max(high - low, 1.0);
    final points = List.generate(
      values.length,
      (i) => Offset(
        values.length == 1
            ? size.width / 2
            : 4 + (size.width - 8) * i / (values.length - 1),
        20 + (size.height - 40) * (1 - (values[i] - low) / range),
      ),
    );
    final path = Path()..moveTo(points.first.dx, points.first.dy);
    for (final point in points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }
    final fill = Path.from(path)
      ..lineTo(points.last.dx, size.height)
      ..lineTo(points.first.dx, size.height)
      ..close();
    canvas.drawPath(
      fill,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [color.withValues(alpha: 0.2), color.withValues(alpha: 0)],
        ).createShader(Offset.zero & size),
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawCircle(points.last, 4, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _TrendPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}
