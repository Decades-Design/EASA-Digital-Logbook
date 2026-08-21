import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// The "− n +" counter used throughout §5 (take-offs/landings) and §6 (IR
/// currency: approach repeat count, holding-procedure count). Pre-filled
/// values are immediately editable with no confirmation gate
/// (docs/entry-form.md §5) — this widget is the primary interface, not an
/// override hidden behind a disclosure triangle.
class CounterStepper extends StatelessWidget {
  const CounterStepper({
    super.key,
    required this.value,
    required this.onIncrement,
    required this.onDecrement,
    this.width,
    this.compact = false,
  });

  final int value;
  final VoidCallback onIncrement;
  final VoidCallback? onDecrement;
  final double? width;

  /// Slightly smaller box, used inline in the approach row where three
  /// other controls share the line.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = context.inkTiers;
    final height = compact ? 40.0 : 44.0;
    final buttonSize = compact ? 34.0 : 38.0;

    return Container(
      width: width,
      height: height,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        color: compact ? scheme.surface : scheme.surfaceContainerLow,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(compact ? 8 : 9),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _StepButton(
            icon: Icons.remove,
            size: buttonSize,
            onTap: onDecrement,
            color: onDecrement == null ? ink.faint : scheme.primary,
          ),
          Text(
            '$value',
            style: TextStyle(
              fontFamily: 'IBM Plex Mono',
              fontWeight: FontWeight.w600,
              fontSize: compact ? 14 : 15,
              color: scheme.onSurface,
            ),
          ),
          _StepButton(
            icon: Icons.add,
            size: buttonSize,
            onTap: onIncrement,
            color: scheme.primary,
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({
    required this.icon,
    required this.size,
    required this.onTap,
    required this.color,
  });

  final IconData icon;
  final double size;
  final VoidCallback? onTap;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: size,
        height: size,
        child: Icon(icon, size: 17, color: color),
      ),
    );
  }
}
