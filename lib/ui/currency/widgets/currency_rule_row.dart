import 'package:flutter/material.dart';

import '../../../domain/currency/currency_dashboard.dart';
import '../../../domain/currency/rule_result.dart';
import '../../../domain/model/calendar_date.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../currency_status_colors.dart';
import 'currency_progress_bar.dart';

/// The "current / required" (or "days remaining") readout next to a
/// progress bar — [RuleProgressKind.validity] has no threshold, so it falls
/// back to a bare day count instead of a fraction.
String currencyNumericLine(RuleProgress progress, CalendarDate asOf) {
  switch (progress.kind) {
    case RuleProgressKind.count:
      return '${progress.currentCount} / ${progress.requiredCount}';
    case RuleProgressKind.hours:
      return '${progress.currentHours!.toHoursMinutes()} / '
          '${progress.requiredHours!.toHoursMinutes()} hours';
    case RuleProgressKind.validity:
      final until = progress.validUntil;
      if (until == null) return 'no expiry';
      final days = until.differenceInDays(asOf);
      return '$days days remaining';
  }
}

/// One evaluated currency rule, as a row inside its licence's card —
/// title + expiry date/day-count, the fill/tick progress bar when
/// [RuleResult.progress] has one, and a value/context-note line below.
///
/// Structure and colour follow the mockup's own list-row convention
/// (Currency Totals Settings.dc.html, 2a) precisely: the title and the
/// numeric value stay neutral ink *even on a flagged row* — only the
/// left accent bar, the row's faint tint, the bar's fill, and the trailing
/// context note pick up the state colour. A row is tappable (revealing
/// which flights counted, via [onShowContributingFlights]) rather than
/// carrying a visible link, since the mockup's rows have no such link —
/// only its hero cards do.
class CurrencyRuleRow extends StatelessWidget {
  const CurrencyRuleRow({
    super.key,
    required this.row,
    required this.asOf,
    required this.onShowContributingFlights,
  });

  final CurrencyDashboardRow row;
  final CalendarDate asOf;

  /// Called with [RuleResult.contributingFlightIds] when the pilot taps
  /// the row — null (or an empty contributing list) leaves the row inert.
  final ValueChanged<List<String>>? onShowContributingFlights;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;
    final brightness = theme.brightness;
    final result = row.evaluation.result;
    final progress = result.progress;

    final Color fillColor;
    final Color? flagColor;
    if (!result.satisfied) {
      final palette = CurrencyPalette.expired(brightness);
      fillColor = palette.fill;
      flagColor = palette.accent;
    } else if (row.isAtRisk) {
      final palette = CurrencyPalette.dueSoon(brightness);
      fillColor = palette.fill;
      flagColor = palette.accent;
    } else {
      fillColor = CurrencyPalette.healthyFill(brightness);
      flagColor = null;
    }

    final expiresOn = result.expiresOn;
    final contributingFlightIds = result.contributingFlightIds;
    final canDrillDown =
        contributingFlightIds.isNotEmpty && onShowContributingFlights != null;

    final content = Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: flagColor == null
          ? null
          : BoxDecoration(
              color: flagColor.withValues(alpha: 0.05),
              border: Border(left: BorderSide(color: flagColor, width: 3)),
            ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(row.title, style: theme.textTheme.titleSmall),
              ),
              const SizedBox(width: 10),
              if (expiresOn != null)
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '$expiresOn ',
                        style: AppMonoText.value(ink.muted, size: 11.5),
                      ),
                      TextSpan(
                        text: '(${expiresOn.differenceInDays(asOf)})',
                        style: AppMonoText.value(ink.faint, size: 11.5),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 9),
          if (progress != null) ...[
            Builder(
              builder: (context) {
                final fillAndTick = currencyProgressFillAndTick(progress, asOf);
                return CurrencyProgressBar(
                  fill: fillAndTick.fill,
                  tick: fillAndTick.tick,
                  fillColor: fillColor,
                );
              },
            ),
            const SizedBox(height: 7),
          ],
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              if (progress != null)
                Text(
                  currencyNumericLine(progress, asOf),
                  style: AppMonoText.value(ink.medium, size: 11.5),
                ),
              const SizedBox(width: 10),
              if (_noteText(progress, result) case final note?)
                Expanded(
                  child: Text(
                    note,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: flagColor ?? ink.muted,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );

    if (!canDrillDown) return content;
    return InkWell(
      onTap: () => onShowContributingFlights!(contributingFlightIds),
      child: content,
    );
  }

  /// The trailing context note, or null to omit it entirely.
  ///
  /// A satisfied [RuleProgressKind.validity] row's own
  /// [RuleResult.explanation] is just `Currently-valid "$kind" held...` —
  /// a raw [HeldRecord.kind] identifier restating the date already shown
  /// above it, not genuine context. The mockup's own validity-style rows
  /// (a medical certificate, a rating with no activity requirement) carry
  /// a short, real note instead ("issued 14 Mar 2025") that this domain
  /// data doesn't have a source for yet, so omitting the row is more
  /// honest than showing an internal string in its place.
  String? _noteText(RuleProgress? progress, RuleResult result) {
    if (progress?.kind == RuleProgressKind.validity && result.satisfied) {
      return null;
    }
    return result.explanation;
  }
}
