import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// A label-left, mono-value-right row — the repeating shape almost every
/// Totals list row is (Function/Conditions/Ops figures, aircraft subtotals).
/// [indent] pushes a sub-row in under its parent (a type under its class, an
/// "of which PIC" line under Cross-country) without a second widget shape.
class TotalsRow extends StatelessWidget {
  const TotalsRow({
    super.key,
    required this.label,
    required this.value,
    this.indent = false,
    this.emphasis = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool indent;

  /// Section-total rows (class/group subtotals) read slightly larger and
  /// bolder than a plain leaf row — matches the mockup's own weight step
  /// between a class header and its indented types.
  final bool emphasis;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;
    return Padding(
      padding: EdgeInsets.fromLTRB(indent ? 34 : 20, 11, 20, 11),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: indent
                ? theme.textTheme.bodyMedium?.copyWith(color: ink.muted)
                : theme.textTheme.titleSmall,
          ),
          Text(
            value,
            style: AppMonoText.value(
              valueColor ?? theme.colorScheme.onSurface,
              size: indent ? 12.5 : 13.5,
              weight: emphasis ? FontWeight.w700 : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// The small mono-caps section header ("PILOT FUNCTION TIME",
/// "TAKE-OFFS & LANDINGS"), with an optional trailing subtotal.
class TotalsSectionHeader extends StatelessWidget {
  const TotalsSectionHeader({super.key, required this.label, this.trailing});

  final String label;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 9, 20, 8),
      color: theme.colorScheme.surfaceContainerLowest,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: AppMonoText.tag(ink.muted).copyWith(letterSpacing: 1.1),
          ),
          if (trailing != null)
            Text(trailing!, style: AppMonoText.value(ink.faint, size: 11)),
        ],
      ),
    );
  }
}
