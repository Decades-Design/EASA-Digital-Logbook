import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/model/calendar_date.dart';
import '../../domain/model/flight_duration.dart';
import '../../domain/model/flight_times.dart';
import '../entry/duplicate_flight_action.dart';
import '../providers/flight_records_providers.dart';
import '../providers/jurisdiction_projection_providers.dart';
import '../providers/jurisdiction_providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../widgets/large_title_scaffold.dart';
import 'flight_detail_screen.dart';
import 'logbook_filter.dart';
import 'logbook_filters_screen.dart';
import 'logbook_view_model.dart';

/// #57: chronological logbook, primary-jurisdiction figures only — per
/// CLAUDE.md's multi-jurisdiction UX rule, the logbook list is not the
/// place for a jurisdiction toggle. Matches design 1b — "Logbook — Ledger.
/// Dense, ruled, every figure aligned" (Claude Design project
/// 513e7fc3-e41a-40ea-b3a5-f16f086d15f8).
///
/// #56: reads real repository-backed data (drafts and committed flights
/// both — see `logbook_view_model.dart`'s `buildLogbookMonths`) rather than
/// `sample_logbook_data.dart`'s fixture. The `watchFlights` API needs *some*
/// jurisdiction's projection to run at all, so this reads whichever one is
/// available (the primary if one is held) purely as a technical
/// requirement — nothing shown here is jurisdiction-dependent (see
/// `logbook_view_model.dart`'s dartdoc on why `crewRole`/`night` are raw
/// facts, not derived quantities). The "New flight" FAB lives in
/// [AppShell], not here — 1e settled it as a nav-bar fixture, not a
/// per-screen action.
class LogbookScreen extends ConsumerStatefulWidget {
  const LogbookScreen({super.key});

  @override
  ConsumerState<LogbookScreen> createState() => _LogbookScreenState();
}

class _LogbookScreenState extends ConsumerState<LogbookScreen> {
  LogbookFilter _filter = const LogbookFilter();
  final _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(
        () => _filter = _filter.copyWith(searchText: _searchController.text),
      );
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _openFilters() async {
    final updated = await Navigator.of(context).push<LogbookFilter>(
      MaterialPageRoute(builder: (_) => LogbookFiltersScreen(initial: _filter)),
    );
    if (updated != null) {
      setState(() => _filter = updated);
    }
  }

  void _clearAll() {
    _searchController.clear();
    setState(() => _filter = const LogbookFilter());
  }

  @override
  Widget build(BuildContext context) {
    final projectionsAsync = ref.watch(jurisdictionProjectionsProvider);
    if (projectionsAsync.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (projectionsAsync.hasError) {
      return const Scaffold(
        body: EmptyStateMessage(
          icon: Icons.error_outline,
          headline: 'Logbook could not be loaded',
          caption: 'Something went wrong reading the logbook.',
        ),
      );
    }
    final projections = projectionsAsync.requireValue;
    if (projections.isEmpty) {
      return const Scaffold(
        body: SafeArea(
          child: EmptyStateMessage(
            icon: Icons.menu_book_outlined,
            headline: 'No licence on file yet',
            caption: 'The logbook opens once at least one licence is held.',
          ),
        ),
      );
    }
    final primaryId = ref
        .watch(primaryJurisdictionIdProvider)
        .maybeWhen(data: (id) => id, orElse: () => null);
    final projection = projections[primaryId] ?? projections.values.first;

    final draftsAsync = ref.watch(draftFlightRecordsProvider);
    final committedAsync = ref.watch(
      committedFlightRecordsProvider((projection, _filter.toFlightQuery())),
    );
    if (draftsAsync.isLoading || committedAsync.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (draftsAsync.hasError || committedAsync.hasError) {
      return const Scaffold(
        body: EmptyStateMessage(
          icon: Icons.error_outline,
          headline: 'Logbook could not be loaded',
          caption: 'Something went wrong reading the logbook.',
        ),
      );
    }

    // `committedAsync` is already SQL-narrowed by `_filter.toFlightQuery()`
    // (date range, aircraft, aerodrome, capacity); `.matches` is the single
    // source of truth (see its own dartdoc) applied uniformly on top —
    // drafts never went through any SQL filtering to begin with.
    final drafts = draftsAsync.requireValue.where(_filter.matches).toList();
    final committed = committedAsync.requireValue
        .where(_filter.matches)
        .toList();

    if (drafts.isEmpty && committed.isEmpty && _filter.isEmpty) {
      return const Scaffold(
        body: SafeArea(
          child: EmptyStateMessage(
            icon: Icons.menu_book_outlined,
            headline: 'No flights logged yet',
            caption: 'Flights you log will appear here, newest first.',
          ),
        ),
      );
    }

    final months = buildLogbookMonths(
      drafts,
      committed,
      projections: projections,
    );
    final flightCount = drafts.length + committed.length;
    final totalTime = FlightDuration.sum([
      for (final record in drafts) record.flight.blockTime,
      for (final record in committed) record.flight.blockTime,
    ]);
    final awaitingSignatureCount = committed
        .where(isPendingCountersignature)
        .length;

    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverSafeArea(
            bottom: false,
            sliver: SliverToBoxAdapter(
              child: _LogbookHeader(
                flightCount: flightCount,
                totalTime: Duration(minutes: totalTime.inMinutes),
                filtered: !_filter.isEmpty,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: _SearchAndFilterRow(
              controller: _searchController,
              onOpenFilters: _openFilters,
            ),
          ),
          if (!_filter.isEmpty)
            SliverToBoxAdapter(
              child: _ActiveFiltersRow(
                filter: _filter,
                onChanged: (updated) => setState(() => _filter = updated),
                onClearAll: _clearAll,
              ),
            ),
          if (drafts.isNotEmpty || awaitingSignatureCount > 0)
            SliverToBoxAdapter(
              child: _AttentionBanner(
                draftCount: drafts.length,
                awaitingSignatureCount: awaitingSignatureCount,
              ),
            ),
          if (months.isEmpty)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Center(
                  child: Text(
                    'No flights match these filters.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: context.inkTiers.muted,
                    ),
                  ),
                ),
              ),
            ),
          for (final month in months) ...[
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
  const _LogbookHeader({
    required this.flightCount,
    required this.totalTime,
    required this.filtered,
  });

  final int flightCount;
  final Duration totalTime;

  /// #64: "result count and filtered totals shown" — [flightCount]/
  /// [totalTime] are already the filtered figures whenever a filter is
  /// active; this only controls the small "filtered" label so it's never
  /// mistaken for the whole logbook's own totals.
  final bool filtered;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        children: [
          // #56: `spaceBetween` with two fixed-size children (this row's
          // earlier shape) overflows once a real logbook's flight count
          // and running total grow wide enough — found writing this
          // screen's first widget test, against a realistically-sized
          // seeded dataset. `Expanded` (ellipsized) keeps the title from
          // forcing the actual figures off-screen; the figures themselves
          // are the more load-bearing of the two.
          Expanded(
            child: Text(
              'Logbook',
              style: theme.textTheme.displaySmall?.copyWith(fontSize: 27),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 8),
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '$flightCount',
                  style: AppMonoText.value(
                    theme.colorScheme.onSurface,
                    size: 14,
                    weight: FontWeight.w600,
                  ),
                ),
                TextSpan(
                  text: filtered ? ' matching · ' : ' flights · ',
                  style: AppMonoText.value(ink.muted, size: 11.5),
                ),
                TextSpan(
                  text: _formatDuration(totalTime),
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
  const _SearchAndFilterRow({
    required this.controller,
    required this.onOpenFilters,
  });

  final TextEditingController controller;
  final VoidCallback onOpenFilters;

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
                controller: controller,
                style: TextStyle(fontSize: 13.5, color: ink.faint),
                decoration: InputDecoration(
                  isDense: true,
                  isCollapsed: true,
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  hintText: 'Registration, aerodrome, remark…',
                  hintStyle: TextStyle(fontSize: 13.5, color: ink.faint),
                ),
              ),
            ),
            Container(width: 1, height: 18, color: scheme.outlineVariant),
            const SizedBox(width: 10),
            InkWell(
              onTap: onOpenFilters,
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

/// #64: "Filters combinable and the active set clearly visible" — one
/// removable chip per active dimension (free text excluded — it's already
/// visible in the search box itself) plus a blanket "Clear all".
class _ActiveFiltersRow extends StatelessWidget {
  const _ActiveFiltersRow({
    required this.filter,
    required this.onChanged,
    required this.onClearAll,
  });

  final LogbookFilter filter;
  final ValueChanged<LogbookFilter> onChanged;
  final VoidCallback onClearAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ink = context.inkTiers;

    final chips = <(String, LogbookFilter)>[
      if (filter.from != null)
        (
          'From ${_formatFilterDate(filter.from!)}',
          filter.copyWith(clearFrom: true),
        ),
      if (filter.to != null)
        ('To ${_formatFilterDate(filter.to!)}', filter.copyWith(clearTo: true)),
      if (filter.aircraftLabel != null)
        (filter.aircraftLabel!, filter.copyWith(clearAircraft: true)),
      if (filter.aerodromeIdentifier != null)
        (filter.aerodromeIdentifier!, filter.copyWith(clearAerodrome: true)),
      if (filter.ifrFlightPlanFiled != null)
        (
          filter.ifrFlightPlanFiled! ? 'IFR' : 'Not IFR',
          filter.copyWith(clearIfr: true),
        ),
      if (filter.hasNightFlying != null)
        (
          filter.hasNightFlying! ? 'Night' : 'Day only',
          filter.copyWith(clearNight: true),
        ),
      if (filter.capacity != null)
        ('Capacity filters', filter.copyWith(clearCapacity: true)),
    ];

    if (chips.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Wrap(
        spacing: 7,
        runSpacing: 7,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final (label, next) in chips)
            Semantics(
              label: 'Remove $label filter',
              button: true,
              excludeSemantics: true,
              child: InkWell(
                onTap: () => onChanged(next),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.primary,
                          fontSize: 11,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(Icons.close, size: 12, color: scheme.primary),
                    ],
                  ),
                ),
              ),
            ),
          InkWell(
            onTap: onClearAll,
            child: Text(
              'Clear all',
              style: theme.textTheme.labelMedium?.copyWith(
                color: ink.muted,
                fontSize: 11,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatFilterDate(CalendarDate date) =>
    '${date.day}/${date.month}/${date.year}';

/// The "N flights need attention" banner — 1b's answer to "not current, no
/// explanation is a bug": every flight it counts is broken out by reason
/// rather than folded into one number.
///
/// Only drafts and awaiting-signature are real, queryable reasons right now
/// — the fixture this replaces also counted a "needs information" bucket
/// (e.g. a draft missing its landings), but that has no real domain concept
/// backing it yet (no validation surfaces "this flight is incomplete"), so
/// it's dropped rather than reported as a fabricated zero.
class _AttentionBanner extends StatelessWidget {
  const _AttentionBanner({
    required this.draftCount,
    required this.awaitingSignatureCount,
  });

  final int draftCount;
  final int awaitingSignatureCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semanticColors;
    final needsAttention = draftCount + awaitingSignatureCount;

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
              children: [
                // #56: `spaceBetween` with two fixed-size children (this
                // row's earlier shape) overflows once the attention count
                // grows wide enough on a real, long-lived logbook — found
                // writing this screen's first widget test. `Expanded`
                // (ellipsized) keeps "Hide" fully visible and lets the
                // count give way instead.
                Expanded(
                  child: Row(
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
                      Flexible(
                        child: Text(
                          '$needsAttention flights need attention',
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: semantic.currencyWarning,
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
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
                if (draftCount > 0)
                  _AttentionChip(count: draftCount, label: 'drafts'),
                if (awaitingSignatureCount > 0)
                  _AttentionChip(
                    count: awaitingSignatureCount,
                    label: 'awaiting signature',
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

  final LogbookMonth month;

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

  final FlightRowView flight;

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
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => FlightDetailScreen(
              record: flight.record,
              isDraft: flight.isDraft,
            ),
          ),
        ),
        // #65: "reachable... from the list" without going through detail
        // first.
        onLongPress: () => showDuplicateFlightMenu(context, flight.record),
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

  final FlightRowView flight;

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
