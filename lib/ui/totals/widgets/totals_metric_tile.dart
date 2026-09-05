import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// One glanceable cell in the Totals metric grid (Currency Totals
/// Settings.dc.html, frame 3b) — a mono-caps label over a large mono value,
/// two per row, replacing the old five-tab list of full-width rows.
/// [onTap] gives a cell the same tappable affordance the Ops tab's
/// Aerodromes row always had; a tile with nowhere to go stays plain text.
class TotalsMetricTile extends StatelessWidget {
  const TotalsMetricTile({
    super.key,
    required this.label,
    required this.value,
    this.onTap,
    this.valueColor,
  });

  final String label;
  final String value;
  final VoidCallback? onTap;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;
    final content = Padding(
      padding: const EdgeInsets.fromLTRB(20, 11, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppMonoText.tag(ink.faint).copyWith(letterSpacing: 0.7),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                value,
                style: AppMonoText.value(
                  valueColor ?? theme.colorScheme.onSurface,
                  size: 20,
                  weight: FontWeight.w600,
                ),
              ),
              if (onTap != null) ...[
                const SizedBox(width: 6),
                Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: valueColor ?? theme.colorScheme.primary,
                ),
              ],
            ],
          ),
        ],
      ),
    );
    return ColoredBox(
      color: theme.colorScheme.surface,
      child: onTap == null ? content : InkWell(onTap: onTap, child: content),
    );
  }
}

/// Lays [tiles] out two per row with hairline dividers between them — frame
/// 3b's "hairline metric grid you read at a glance" rather than a single
/// column of full-width rows. An odd tile count leaves the grid's last cell
/// empty rather than stretching the final tile full-width.
class TotalsMetricGrid extends StatelessWidget {
  const TotalsMetricGrid({super.key, required this.tiles});

  final List<Widget> tiles;

  @override
  Widget build(BuildContext context) {
    final divider = Theme.of(context).colorScheme.outlineVariant;
    final rows = <Widget>[];
    for (var i = 0; i < tiles.length; i += 2) {
      if (i != 0) rows.add(Divider(height: 1, color: divider));
      final hasSecond = i + 1 < tiles.length;
      rows.add(
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border(right: BorderSide(color: divider)),
                  ),
                  child: tiles[i],
                ),
              ),
              Expanded(child: hasSecond ? tiles[i + 1] : const SizedBox()),
            ],
          ),
        ),
      );
    }
    return Column(children: rows);
  }
}
