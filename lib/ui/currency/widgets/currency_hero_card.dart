import 'package:flutter/material.dart';

import '../../../domain/currency/currency_dashboard.dart';
import '../../../domain/model/calendar_date.dart';
import '../../theme/app_typography.dart';
import '../currency_status_colors.dart';
import 'currency_progress_bar.dart';
import 'currency_rule_row.dart';

/// One at-risk rule, called out in the horizontal-scrolling hero row —
/// [CurrencyDashboard.atRiskRows] only, so every card here is either
/// unsatisfied or expiring inside the hero window (never a healthy row).
///
/// Colour follows the mockup's hero-card convention (Currency Totals
/// Settings.dc.html, 2a), which is louder and more uniform than a list
/// row's: the status dot, the EXPIRED/DUE SOON label and the "Which
/// flights counted" link all use the state's brightest `accent` shade;
/// the title, numeric line, tick and footer note all share a single
/// darker `text` shade; the bar fill gets its own third shade. Unlike a
/// list row, nothing here stays neutral.
class CurrencyHeroCard extends StatelessWidget {
  const CurrencyHeroCard({
    super.key,
    required this.row,
    required this.asOf,
    required this.onShowContributingFlights,
  });

  final CurrencyDashboardRow row;
  final CalendarDate asOf;
  final ValueChanged<List<String>>? onShowContributingFlights;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = row.evaluation.result;
    final progress = result.progress;
    final expired = !result.satisfied;
    final palette = expired
        ? CurrencyPalette.expired(theme.brightness)
        : CurrencyPalette.dueSoon(theme.brightness);
    final labelColor = expired
        ? palette.accent
        : CurrencyPalette.dueSoonLabel(theme.brightness);
    final expiresOn = result.expiresOn;
    final contributingFlightIds = result.contributingFlightIds;

    return Container(
      width: 330,
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
      decoration: BoxDecoration(
        color: palette.cardBackground,
        border: Border.all(color: palette.cardBorder),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: palette.accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                expired ? 'EXPIRED' : 'DUE SOON',
                style: AppMonoText.tag(labelColor).copyWith(letterSpacing: 1.2),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            row.title,
            style: theme.textTheme.titleMedium?.copyWith(color: palette.text),
          ),
          if (progress != null) ...[
            const SizedBox(height: 12),
            Builder(
              builder: (context) {
                final fillAndTick = currencyProgressFillAndTick(progress, asOf);
                return CurrencyProgressBar(
                  fill: fillAndTick.fill,
                  tick: fillAndTick.tick,
                  fillColor: palette.fill,
                  tickColor: palette.text,
                );
              },
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  currencyNumericLine(progress, asOf),
                  style: AppMonoText.value(palette.text, size: 11.5),
                ),
                if (expiresOn != null)
                  Text(
                    'expires $expiresOn',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: palette.text,
                    ),
                  ),
              ],
            ),
          ],
          const SizedBox(height: 11),
          Container(height: 1, color: palette.cardBorder),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  result.explanation,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: palette.text,
                  ),
                ),
              ),
              if (contributingFlightIds.isNotEmpty &&
                  onShowContributingFlights != null) ...[
                const SizedBox(width: 8),
                InkWell(
                  onTap: () =>
                      onShowContributingFlights!(contributingFlightIds),
                  child: Text(
                    'Which flights counted →',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: palette.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
