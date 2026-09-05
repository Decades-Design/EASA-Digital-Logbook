import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../domain/currency/currency_dashboard.dart';
import '../../domain/currency/currency_rule_loader.dart';
import '../../domain/model/calendar_date.dart';
import '../../domain/model/utc_instant.dart';
import '../../domain/repository/flight_read_repository.dart';
import '../jurisdiction_display.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../widgets/jurisdiction_dropdown.dart';
import '../widgets/large_title_scaffold.dart';
import 'rule_asset_paths.dart';
import 'sample_currency_data.dart';
import 'widgets/currency_hero_card.dart';
import 'widgets/currency_rule_row.dart';

/// #62: the currency dashboard — every held licence, grouped, with a reason
/// for each pill. Runs the real `CurrencyRuleEvaluator`/`CurrencyRuleLoader`
/// engine against `sample_currency_data.dart`'s fixture — unlike Logbook/
/// Totals, this isn't just pending #56's repository wiring (that part's
/// done elsewhere now): `sample_currency_data.dart`'s own dartdoc is
/// explicit that *which currency rules apply to a held licence* has no
/// resolver at all yet ("a pilot without a tailwheel endorsement should
/// never see tailwheel currency" — Settings-phase work), so `ruleIds` stays
/// hand-picked regardless of #56. Real flights/held-ratings/medical data
/// could be wired in without that resolver, but would leave the dashboard
/// evaluating against the *wrong* rule set for whatever a real pilot holds
/// — worse than an honestly-labelled fixture.
class CurrencyScreen extends StatefulWidget {
  const CurrencyScreen({super.key});

  @override
  State<CurrencyScreen> createState() => _CurrencyScreenState();
}

class _CurrencyScreenState extends State<CurrencyScreen> {
  CurrencyDashboard? _dashboard;
  List<FlightRecord> _flights = const [];
  late final CalendarDate _today;

  /// `null` means "Both" — the default, matching CLAUDE.md's "show all held
  /// licences grouped by default."
  String? _selectedJurisdictionId;

  @override
  void initState() {
    super.initState();
    _today = CalendarDate.fromUtcInstant(
      UtcInstant.fromDateTime(DateTime.now().toUtc()),
    );
    _load();
  }

  Future<void> _load() async {
    // `cache: false` — see `NewFlightScreen._loadJurisdictions`'s own note:
    // `rootBundle`'s process-wide cache otherwise returns a permanently-
    // pending `Future` to a later widget-test run that reopens this screen.
    final yamlContents = await Future.wait([
      for (final path in ruleAssetPaths)
        rootBundle.loadString(path, cache: false),
    ]);
    final loader = CurrencyRuleLoader.fromYaml(yamlContents);
    final flights = sampleCurrencyFlights(_today);
    final dashboard = buildCurrencyDashboard(
      licences: sampleCurrencyLicences,
      loader: loader,
      subject: sampleEvaluationSubject(_today),
      asOf: _today,
    );
    if (!mounted) return;
    setState(() {
      _flights = flights;
      _dashboard = dashboard;
    });
  }

  void _showContributingFlights(CurrencyDashboardRow row) {
    final flightIds = row.evaluation.result.contributingFlightIds;
    final matching = [
      for (final record in _flights)
        if (flightIds.contains(record.id)) record,
    ]..sort((a, b) => b.flight.offBlocks.compareTo(a.flight.offBlocks));

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) =>
          _ContributingFlightsSheet(row: row, flights: matching),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = _dashboard;
    if (dashboard == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final theme = Theme.of(context);
    final selected = _selectedJurisdictionId;
    final visibleGroups = selected == null
        ? dashboard.groups
        : [
            for (final group in dashboard.groups)
              if (group.jurisdictionId == selected) group,
          ];
    final heroRows = [
      for (final group in visibleGroups)
        for (final row in group.rows)
          if (row.isAtRisk) row,
    ];

    if (_flights.isEmpty) {
      return Scaffold(
        body: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _Header(
                asOf: _today,
                groups: dashboard.groups,
                selectedJurisdictionId: selected,
                onJurisdictionChanged: (id) =>
                    setState(() => _selectedJurisdictionId = id),
              ),
              const Expanded(
                child: EmptyStateMessage(
                  icon: Icons.verified_outlined,
                  headline: 'No flights logged yet',
                  caption:
                      'Currency requirements will appear here once you log your first flight.',
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          // One continuous tinted band for the title and the hero
          // scroller — the mockup's status-bar-to-hero-row area shares a
          // background a shade off the page, distinct from the plain
          // white list below.
          SliverSafeArea(
            bottom: false,
            sliver: SliverToBoxAdapter(
              child: ColoredBox(
                color: theme.colorScheme.surfaceContainerLowest,
                child: Column(
                  children: [
                    _Header(
                      asOf: _today,
                      groups: dashboard.groups,
                      selectedJurisdictionId: selected,
                      onJurisdictionChanged: (id) =>
                          setState(() => _selectedJurisdictionId = id),
                    ),
                    if (heroRows.isNotEmpty) ...[
                      // A fixed-height `SizedBox` here (this row's earlier
                      // approach) clips at any text scale taller than the
                      // pixel count it was tuned for. A plain `Row` sizes
                      // its own cross axis (height) to its tallest child
                      // during normal layout — no `IntrinsicHeight` needed,
                      // which is just as well: `CurrencyProgressBar` uses a
                      // `LayoutBuilder` internally, and `LayoutBuilder`
                      // can't answer the intrinsic-dimension queries
                      // `IntrinsicHeight` would make. `SingleChildScrollView`
                      // passes its child unbounded main-axis space, so the
                      // hero row is free to size itself to whatever its
                      // tallest card needs.
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                        child: Row(
                          children: [
                            for (var i = 0; i < heroRows.length; i++) ...[
                              if (i > 0) const SizedBox(width: 12),
                              CurrencyHeroCard(
                                row: heroRows[i],
                                asOf: _today,
                                onShowContributingFlights:
                                    _showContributingFlights,
                              ),
                            ],
                          ],
                        ),
                      ),
                      _HeroPageDots(count: heroRows.length),
                      const SizedBox(height: 11),
                    ] else
                      const SizedBox(height: 12),
                  ],
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  top: BorderSide(color: theme.colorScheme.outlineVariant),
                ),
              ),
              child: Column(
                children: [
                  for (final group in visibleGroups)
                    _LicenceGroupSection(
                      group: group,
                      asOf: _today,
                      onShowContributingFlights: _showContributingFlights,
                    ),
                ],
              ),
            ),
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 96)),
        ],
      ),
    );
  }
}

/// The mockup's own pagination hint below the hero scroller — decorative,
/// always showing the first dot "active" rather than tracking real scroll
/// position, since the row is short enough to skim without a live indicator
/// mattering.
class _HeroPageDots extends StatelessWidget {
  const _HeroPageDots({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final ink = context.inkTiers;
    if (count <= 1) return const SizedBox.shrink();
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 15,
          height: 4,
          decoration: BoxDecoration(
            color: ink.medium,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 5),
        for (var i = 1; i < count; i++) ...[
          if (i > 1) const SizedBox(width: 5),
          Container(
            width: 4,
            height: 4,
            decoration: BoxDecoration(
              color: ink.faint,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ],
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.asOf,
    required this.groups,
    required this.selectedJurisdictionId,
    required this.onJurisdictionChanged,
  });

  final CalendarDate asOf;
  final List<CurrencyLicenceGroup> groups;

  /// `null` means "Both".
  final String? selectedJurisdictionId;
  final ValueChanged<String?> onJurisdictionChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              // #66: `spaceBetween` with two fixed-size children (this
              // row's earlier shape) overflows once either grows past
              // what's left at a larger text scale. Both texts are
              // `Flexible` now, sharing the row's width instead of each
              // assuming its own unscaled natural width always fits —
              // `flex: 2` keeps the title the larger of the two, matching
              // the original visual balance.
              Flexible(
                flex: 2,
                child: Text(
                  'Currency',
                  style: theme.textTheme.displaySmall?.copyWith(fontSize: 27),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: 'as at ',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: ink.muted,
                        ),
                      ),
                      TextSpan(
                        text: '$asOf',
                        style: AppMonoText.value(ink.medium),
                      ),
                    ],
                  ),
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          JurisdictionDropdown<String?>(
            value: selectedJurisdictionId,
            label: selectedJurisdictionId == null
                ? 'Both'
                : (jurisdictionLabels[selectedJurisdictionId] ??
                      selectedJurisdictionId!),
            options: {
              null: 'Both',
              for (final group in groups)
                group.jurisdictionId:
                    jurisdictionLabels[group.jurisdictionId] ??
                    group.jurisdictionId,
            },
            onChanged: onJurisdictionChanged,
          ),
        ],
      ),
    );
  }
}

/// One held licence's currency rules, flowing directly into the continuous
/// white list alongside every other licence — the mockup keeps the whole
/// group list as one panel, section headers doing the separating rather
/// than each licence getting its own boxed card with a gap around it.
class _LicenceGroupSection extends StatelessWidget {
  const _LicenceGroupSection({
    required this.group,
    required this.asOf,
    required this.onShowContributingFlights,
  });

  final CurrencyLicenceGroup group;
  final CalendarDate asOf;
  final ValueChanged<CurrencyDashboardRow> onShowContributingFlights;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;
    final scheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 9),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerLowest,
            border: Border(
              top: BorderSide(color: scheme.outlineVariant),
              bottom: BorderSide(color: scheme.outlineVariant),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    group.label.toUpperCase(),
                    style: AppMonoText.tag(
                      ink.muted,
                    ).copyWith(letterSpacing: 1.1),
                  ),
                  const SizedBox(width: 8),
                  if (group.isPrimary)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        'PRIMARY',
                        style: AppMonoText.tag(
                          context.semanticColors.overriddenText,
                        ).copyWith(letterSpacing: 0.7),
                      ),
                    )
                  else
                    Text(
                      group.privilegeSummary,
                      style: AppMonoText.value(ink.faint, size: 10.5),
                    ),
                ],
              ),
              // "Edit" has nowhere to go yet — a licence editor is
              // Settings-phase work — so this is a harmless no-op,
              // matching LogbookScreen's own not-yet-built taps.
              InkWell(
                onTap: () {},
                child: Text(
                  'Edit',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        for (var i = 0; i < group.rows.length; i++) ...[
          if (i > 0) Divider(height: 1, color: scheme.outlineVariant),
          CurrencyRuleRow(
            row: group.rows[i],
            asOf: asOf,
            onShowContributingFlights: onShowContributingFlights,
          ),
        ],
      ],
    );
  }
}

class _ContributingFlightsSheet extends StatelessWidget {
  const _ContributingFlightsSheet({required this.row, required this.flights});

  final CurrencyDashboardRow row;
  final List<FlightRecord> flights;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Which flights counted', style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            // #62: "which rule was applied, with the citation" — kept to
            // this sheet only (never on the dashboard row itself), a
            // deliberate choice so the compact list stays uncluttered.
            Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: row.title,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ink.muted,
                    ),
                  ),
                  TextSpan(
                    text: '  ·  ',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ink.faint,
                    ),
                  ),
                  TextSpan(
                    text: row.evaluation.citation,
                    style: AppMonoText.value(ink.muted, size: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            for (final record in flights)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    Text(
                      CalendarDate.fromUtcInstant(
                        record.flight.offBlocks,
                      ).toString(),
                      style: AppMonoText.value(ink.medium),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        record.flight.route.join(' → '),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    Text(
                      record.aircraft.registration,
                      style: AppMonoText.value(ink.muted, size: 12.5),
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
