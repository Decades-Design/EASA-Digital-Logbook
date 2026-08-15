import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'sample_logbook_data.dart';

/// #57: chronological logbook, primary-jurisdiction figures only — per
/// CLAUDE.md's multi-jurisdiction UX rule, the logbook list is not the
/// place for a jurisdiction toggle. Matches design 1b — "Logbook — Ledger.
/// Dense, ruled, every figure aligned" (Claude Design project
/// 513e7fc3-e41a-40ea-b3a5-f16f086d15f8). Reads [sampleLogbookMonths] for
/// now — see that file's dartdoc for what real data wiring (#56) replaces
/// it with. The "New flight" FAB lives in [AppShell], not here — 1e settled
/// it as a nav-bar fixture, not a per-screen action.
class LogbookScreen extends StatelessWidget {
  const LogbookScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          const SliverSafeArea(
            bottom: false,
            sliver: SliverToBoxAdapter(child: _LogbookHeader()),
          ),
          const SliverToBoxAdapter(child: _SearchAndFilterRow()),
          const SliverToBoxAdapter(child: _AttentionBanner()),
          for (final month in sampleLogbookMonths) ...[
            SliverToBoxAdapter(child: _MonthHeader(month: month)),
            SliverList.separated(
              itemCount: month.flights.length,
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: scheme.outlineVariant),
              itemBuilder: (context, index) =>
                  _FlightRow(flight: month.flights[index]),
            ),
          ],
          const SliverPadding(padding: EdgeInsets.only(bottom: 96)),
        ],
      ),
    );
  }
}

class _LogbookHeader extends StatelessWidget {
  const _LogbookHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Logbook',
            style: theme.textTheme.displaySmall?.copyWith(fontSize: 27),
          ),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '$sampleFlightCount',
                  style: AppMonoText.value(
                    theme.colorScheme.onSurface,
                    size: 14,
                    weight: FontWeight.w600,
                  ),
                ),
                TextSpan(
                  text: ' flights · ',
                  style: AppMonoText.value(ink.muted, size: 11.5),
                ),
                TextSpan(
                  text: _formatDuration(sampleTotalTime),
                  style: AppMonoText.value(
                    theme.colorScheme.onSurface,
                    size: 14,
                    weight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SearchAndFilterRow extends StatelessWidget {
  const _SearchAndFilterRow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ink = context.inkTiers;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 13),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.search, size: 18, color: ink.faint),
            const SizedBox(width: 9),
            Expanded(
              child: TextField(
                style: TextStyle(fontSize: 13.5, color: ink.faint),
                decoration: InputDecoration(
                  isDense: true,
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'Registration, aerodrome, remark…',
                  hintStyle: TextStyle(fontSize: 13.5, color: ink.faint),
                ),
              ),
            ),
            Container(width: 1, height: 18, color: scheme.outlineVariant),
            const SizedBox(width: 10),
            InkWell(
              onTap: () {},
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.tune, size: 16, color: scheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    'Filters',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w500,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The "N flights need attention" banner — 1b's answer to "not current, no
/// explanation is a bug": every flight it counts is broken out by reason
/// rather than folded into one number.
class _AttentionBanner extends StatelessWidget {
  const _AttentionBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semanticColors;
    final needsAttention =
        sampleDraftCount +
        sampleAwaitingSignatureCount +
        sampleNeedsInformationCount;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
        decoration: BoxDecoration(
          color: semantic.currencyWarningSurface,
          border: Border.all(
            color: semantic.currencyWarning.withValues(alpha: 0.3),
          ),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.secondary,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '$needsAttention flights need attention',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: semantic.currencyWarning,
                        fontWeight: FontWeight.w600,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
                Text(
                  'Hide',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: semantic.currencyWarning,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 9),
            Wrap(
              spacing: 7,
              runSpacing: 7,
              children: [
                _AttentionChip(count: sampleDraftCount, label: 'drafts'),
                _AttentionChip(
                  count: sampleAwaitingSignatureCount,
                  label: 'awaiting signature',
                ),
                _AttentionChip(
                  count: sampleNeedsInformationCount,
                  label: 'needs information',
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _AttentionChip extends StatelessWidget {
  const _AttentionChip({required this.count, required this.label});

  final int count;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final semantic = context.semanticColors;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border.all(
          color: semantic.currencyWarning.withValues(alpha: 0.35),
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: AppMonoText.value(
              semantic.currencyWarning,
              size: 11,
              weight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 5),
          Text(
            label,
            style: theme.textTheme.bodySmall?.copyWith(
              color: semantic.currencyWarning,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _MonthHeader extends StatelessWidget {
  const _MonthHeader({required this.month});

  final SampleLogbookMonth month;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = context.inkTiers;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      color: scheme.surfaceContainerLowest,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            month.label,
            style: AppMonoText.value(
              ink.muted,
              size: 10,
              weight: FontWeight.w600,
            ).copyWith(letterSpacing: 1.2),
          ),
          Text(
            '${month.runningCount} · ${_formatDuration(month.runningTotal)}',
            style: AppMonoText.value(
              ink.muted,
              size: 11.5,
              weight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _FlightRow extends StatelessWidget {
  const _FlightRow({required this.flight});

  final SampleFlightRow flight;

  bool get _isFlagged => flight.badges.contains(FlightRowBadge.draft);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ink = context.inkTiers;
    final semantic = context.semanticColors;

    return Container(
      decoration: _isFlagged
          ? BoxDecoration(
              color: semantic.currencyWarningSurface.withValues(alpha: 0.4),
              border: Border(
                left: BorderSide(color: theme.colorScheme.secondary, width: 3),
              ),
            )
          : null,
      child: InkWell(
        onTap: () {},
        child: Padding(
          padding: EdgeInsets.fromLTRB(_isFlagged ? 13 : 16, 13, 16, 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(
                width: 34,
                child: Column(
                  children: [
                    Text(
                      '${flight.day}',
                      style: AppMonoText.value(
                        scheme.onSurface,
                        size: 15,
                        weight: FontWeight.w600,
                      ),
                    ),
                    Text(
                      flight.monthAbbrev,
                      style: TextStyle(
                        fontFamily: 'Instrument Sans',
                        fontSize: 9,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                        color: ink.faint,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        Text(
                          flight.route.join(' → '),
                          style: AppMonoText.value(
                            scheme.onSurface,
                            size: 14.5,
                            weight: FontWeight.w600,
                          ),
                        ),
                        for (final badge in flight.badges)
                          _RowBadge(badge: badge),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: flight.registration,
                            style: AppMonoText.value(ink.muted, size: 11.5),
                          ),
                          TextSpan(
                            text: '  ·  ${flight.crewRole}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: ink.muted,
                              fontSize: 11.5,
                            ),
                          ),
                          if (flight.crewNote != null)
                            TextSpan(
                              text: '  ·  ${flight.crewNote}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: _isFlagged
                                    ? semantic.currencyWarning
                                    : ink.muted,
                                fontSize: 11.5,
                              ),
                            ),
                        ],
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _TimeColumn(flight: flight),
            ],
          ),
        ),
      ),
    );
  }
}

class _RowBadge extends StatelessWidget {
  const _RowBadge({required this.badge});

  final FlightRowBadge badge;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semanticColors;

    final (String label, Color bg, Color fg, Color? border) = switch (badge) {
      FlightRowBadge.draft => (
        'DRAFT',
        semantic.currencyWarningSurface,
        semantic.currencyWarning,
        null,
      ),
      FlightRowBadge.unsigned => (
        'UNSIGNED',
        semantic.currencyWarningSurface,
        semantic.currencyWarning,
        null,
      ),
      FlightRowBadge.mismatch => (
        '⇄ MISMATCH',
        semantic.divergenceSurface,
        semantic.divergence,
        semantic.divergence,
      ),
      FlightRowBadge.night => (
        'NIGHT',
        semantic.nightBadgeSurface,
        semantic.nightBadgeText,
        null,
      ),
      FlightRowBadge.ifr => (
        'IFR',
        semantic.neutralBadgeSurface,
        semantic.neutralBadgeText,
        semantic.neutralBadgeBorder,
      ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        border: border != null
            ? Border.all(color: border.withValues(alpha: 0.4))
            : null,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: AppMonoText.tag(fg).copyWith(letterSpacing: 0.5),
      ),
    );
  }
}

class _TimeColumn extends StatelessWidget {
  const _TimeColumn({required this.flight});

  final SampleFlightRow flight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ink = context.inkTiers;
    final semantic = context.semanticColors;

    final (
      Color valueColor,
      String label,
      Color labelColor,
    ) = switch (flight.timeState) {
      FlightTimeState.block => (scheme.onSurface, 'BLOCK', ink.faint),
      FlightTimeState.notYetCreditable => (
        ink.muted,
        'NOT YET CREDITABLE',
        theme.colorScheme.secondary,
      ),
      FlightTimeState.overridden => (
        scheme.onSurface,
        'OVERRIDDEN',
        semantic.overriddenText,
      ),
    };

    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (flight.timeState == FlightTimeState.overridden) ...[
              Transform.rotate(
                angle: 0.785398, // 45°
                child: Container(width: 6, height: 6, color: scheme.primary),
              ),
              const SizedBox(width: 5),
            ],
            Text(
              _formatDuration(flight.totalTime),
              style: AppMonoText.value(
                valueColor,
                size: 15.5,
                weight: FontWeight.w600,
              ),
            ),
          ],
        ),
        Text(
          label,
          textAlign: TextAlign.right,
          style: TextStyle(
            fontFamily: 'Instrument Sans',
            fontSize: 9.5,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.4,
            color: labelColor,
          ),
        ),
      ],
    );
  }
}

String _formatDuration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60).abs();
  return '$hours:${minutes.toString().padLeft(2, '0')}';
}
