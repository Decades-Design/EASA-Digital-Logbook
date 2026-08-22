import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../domain/currency/currency_dashboard.dart';
import '../../domain/currency/currency_rule_loader.dart';
import '../../domain/model/calendar_date.dart';
import '../../domain/model/utc_instant.dart';
import '../../domain/repository/flight_read_repository.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'rule_asset_paths.dart';
import 'sample_currency_data.dart';
import 'widgets/currency_hero_card.dart';
import 'widgets/currency_rule_row.dart';

/// #62: the currency dashboard — every held licence, grouped, with a reason
/// for each pill. Runs the real `CurrencyRuleEvaluator`/`CurrencyRuleLoader`
/// engine against `sample_currency_data.dart`'s fixture, the same
/// real-engine-over-sample-data convention `NewFlightScreen` and
/// `LogbookScreen` already use pending #56's live repository wiring.
class CurrencyScreen extends StatefulWidget {
  const CurrencyScreen({super.key});

  @override
  State<CurrencyScreen> createState() => _CurrencyScreenState();
}

class _CurrencyScreenState extends State<CurrencyScreen> {
  CurrencyDashboard? _dashboard;
  List<FlightRecord> _flights = const [];
  late final CalendarDate _today;

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

  void _showContributingFlights(List<String> flightIds) {
    final matching = [
      for (final record in _flights)
        if (flightIds.contains(record.id)) record,
    ]..sort((a, b) => b.flight.offBlocks.compareTo(a.flight.offBlocks));

    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => _ContributingFlightsSheet(flights: matching),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dashboard = _dashboard;
    if (dashboard == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final theme = Theme.of(context);
    final heroRows = dashboard.atRiskRows;

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
                    _Header(asOf: _today),
                    if (heroRows.isNotEmpty) ...[
                      // A `ListView` needs a bounded cross-axis height from
                      // its parent — it can't ask a horizontally-scrolling
                      // child to report its own intrinsic height the way a
                      // plain `Row` can (`IntrinsicHeight` around the list
                      // itself throws: the viewport passes its *own*
                      // unbounded incoming height straight through rather
                      // than computing one from its child). 185 is sized to
                      // the card's own content (padding + every internal
                      // row + a two-line footer, the tallest case), not the
                      // much larger fixed box this used before.
                      SizedBox(
                        height: 185,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                          itemCount: heroRows.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 12),
                          itemBuilder: (context, index) => CurrencyHeroCard(
                            row: heroRows[index],
                            asOf: _today,
                            onShowContributingFlights: _showContributingFlights,
                          ),
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
                  for (final group in dashboard.groups)
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
  const _Header({required this.asOf});

  final CalendarDate asOf;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.baseline,
        textBaseline: TextBaseline.alphabetic,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Currency',
            style: theme.textTheme.displaySmall?.copyWith(fontSize: 27),
          ),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: 'as at ',
                  style: theme.textTheme.bodySmall?.copyWith(color: ink.muted),
                ),
                TextSpan(text: '$asOf', style: AppMonoText.value(ink.medium)),
              ],
            ),
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
  final ValueChanged<List<String>> onShowContributingFlights;

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
  const _ContributingFlightsSheet({required this.flights});

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
            const SizedBox(height: 12),
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
