import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../domain/totals/totals_summary.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// The Time tab's granularity chart — [buckets] in oldest-to-newest order,
/// the current period filled with the accent colour, every other bar a
/// neutral tint, matching the mockup's own "past bars muted, current one
/// solid" convention.
class TotalsBarChart extends StatelessWidget {
  const TotalsBarChart({super.key, required this.buckets});

  final List<TimeBucket> buckets;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;
    final maxMinutes = buckets
        .map((b) => b.value.inMinutes)
        .fold(0, (a, b) => a > b ? a : b);
    // A flat maxY of 0 (no flying at all in view) would make every bar's
    // fraction NaN -- floor it to something a chart can still lay out.
    final maxY = (maxMinutes == 0 ? 60 : maxMinutes).toDouble();

    return SizedBox(
      height: 100,
      child: BarChart(
        BarChartData(
          maxY: maxY,
          alignment: BarChartAlignment.spaceAround,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barTouchData: BarTouchData(enabled: false),
          titlesData: FlTitlesData(
            leftTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            topTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            rightTitles: const AxisTitles(
              sideTitles: SideTitles(showTitles: false),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 18,
                getTitlesWidget: (value, meta) {
                  final index = value.toInt();
                  if (index < 0 || index >= buckets.length) {
                    return const SizedBox.shrink();
                  }
                  final bucket = buckets[index];
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      bucket.label,
                      style: AppMonoText.value(
                        bucket.isCurrent
                            ? theme.colorScheme.primary
                            : ink.faint,
                        size: 9,
                        weight: bucket.isCurrent
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < buckets.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: buckets[i].value.inMinutes.toDouble(),
                    width: 14,
                    color: buckets[i].isCurrent
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
