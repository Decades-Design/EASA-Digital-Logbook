import 'package:flutter/material.dart';

import '../../../domain/currency/rule_result.dart';
import '../../../domain/model/calendar_date.dart';
import '../../theme/app_colors.dart';

/// Fill fraction and tick position for [progress], per the design's own
/// caption: fill is what you have, the tick is what the rule wants.
///
/// [RuleProgressKind.count]/[RuleProgressKind.hours] normalize against
/// `max(current, required, 1)` rather than clamping the fill at 1.0 — an
/// overshoot (4 of 3 landings) still fits on the bar this way, with the
/// tick sitting short of the fill's full width, instead of losing the
/// overshoot entirely.
///
/// [RuleProgressKind.validity] has no threshold to tick — it fills by how
/// much of its own validity span has elapsed as of [asOf]; never expiring
/// (`validUntil == null`) reads as a full bar.
({double fill, double? tick}) currencyProgressFillAndTick(
  RuleProgress progress,
  CalendarDate asOf,
) {
  switch (progress.kind) {
    case RuleProgressKind.count:
      final current = progress.currentCount!;
      final required = progress.requiredCount!;
      final scale = [current, required, 1].reduce((a, b) => a > b ? a : b);
      return (fill: current / scale, tick: required / scale);

    case RuleProgressKind.hours:
      final current = progress.currentHours!.inMinutes;
      final required = progress.requiredHours!.inMinutes;
      final scale = [current, required, 1].reduce((a, b) => a > b ? a : b);
      return (fill: current / scale, tick: required / scale);

    case RuleProgressKind.validity:
      final validFrom = progress.validFrom!;
      final validUntil = progress.validUntil;
      if (validUntil == null) return (fill: 1, tick: null);
      final totalDays = validUntil.differenceInDays(validFrom);
      if (totalDays <= 0) return (fill: 1, tick: null);
      final elapsedDays = asOf.differenceInDays(validFrom);
      return (fill: (elapsedDays / totalDays).clamp(0, 1), tick: null);
  }
}

/// The horizontal fill-and-tick bar every currency row and hero card
/// shows — see [currencyProgressFillAndTick] for what [fill]/[tick] mean.
///
/// [tickColor] defaults to the neutral ink the mockup's *list rows* use for
/// every tick regardless of state (a flagged row's bar fill is coloured,
/// its tick never is) — hero cards pass their state's own `text` shade
/// instead, since the mockup ticks those to match the surrounding copy.
class CurrencyProgressBar extends StatelessWidget {
  const CurrencyProgressBar({
    super.key,
    required this.fill,
    this.tick,
    required this.fillColor,
    this.tickColor,
  });

  final double fill;
  final double? tick;
  final Color fillColor;
  final Color? tickColor;

  @override
  Widget build(BuildContext context) {
    final track = Theme.of(context).colorScheme.outlineVariant;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        return SizedBox(
          height: 9,
          width: width,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: track,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
              FractionallySizedBox(
                widthFactor: fill.clamp(0, 1).toDouble(),
                child: Container(
                  decoration: BoxDecoration(
                    color: fillColor,
                    borderRadius: BorderRadius.circular(5),
                  ),
                ),
              ),
              if (tick != null)
                Positioned(
                  left: (width * tick!.clamp(0, 1)) - 1,
                  top: -2,
                  bottom: -2,
                  child: Container(
                    width: 2,
                    decoration: BoxDecoration(
                      color: tickColor ?? context.inkTiers.medium,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
