import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/model/aerodrome_directory.dart';
import '../../domain/model/calendar_date.dart';
import '../../domain/model/flight_duration.dart';
import '../../domain/model/flight_times.dart';
import '../../domain/model/utc_instant.dart';
import '../../domain/projection/jurisdiction_projection.dart';
import '../../domain/repository/flight_read_repository.dart';
import '../../domain/totals/totals_summary.dart';
import '../aerodromes/aerodromes_screen.dart';
import '../jurisdiction_display.dart';
import '../providers/aerodrome_providers.dart';
import '../providers/flight_records_providers.dart';
import '../providers/jurisdiction_projection_providers.dart';
import '../providers/jurisdiction_providers.dart';
import '../widgets/detail_row.dart';
import '../widgets/large_title_scaffold.dart';
import 'widgets/totals_hero.dart';
import 'widgets/totals_metric_tile.dart';

/// #85: totals and summary view, now frame 3b of Currency Totals
/// Settings.dc.html — a collapsing dark hero (headline total + Year/Month/
/// Week chart, sparkline-only once you scroll) over one continuous
/// "hairline metric grid" of two-up tiles, replacing the earlier five-tab
/// layout so nothing sits alone in empty tab space. Defaults to the pilot's
/// **primary** jurisdiction with an explicit, always-visible dropdown (in
/// the hero) to view the same figures under any other held licence instead
/// (CLAUDE.md's multi-jurisdiction UX rule — a switch, never a silent
/// toggle). Total time of flight, aircraft hours and take-off/landing
/// counts are jurisdiction-agnostic facts computed directly off `Flight`/
/// `PilotCapacity`; PIC/dual/night/instrument/cross-country go through the
/// existing `JurisdictionProjection`, one instance per held licence so
/// switching jurisdictions is a lookup, not a reload.
///
/// #56: reads real repository-backed data via
/// `jurisdictionProjectionsProvider`/`committedFlightRecordsProvider`
/// rather than `sample_totals_data.dart`'s fixture — held jurisdictions
/// come from whatever `HeldRating` rows exist (see
/// `pilot_profile_providers.dart`), so an empty database genuinely shows
/// zero, not stale sample numbers.
class TotalsScreen extends ConsumerStatefulWidget {
  const TotalsScreen({super.key});

  @override
  ConsumerState<TotalsScreen> createState() => _TotalsScreenState();
}

class _TotalsScreenState extends ConsumerState<TotalsScreen> {
  Granularity _granularity = Granularity.year;

  /// Mirrors the mockup's `exp` state: the chart's full form (bars, value
  /// and axis labels, the granularity switch) versus a bare sparkline.
  /// Flipped by scrolling the metric grid ([_handleScroll]) or by tapping
  /// the chart directly ([_toggleHero]).
  bool _heroExpanded = true;
  final _scrollController = ScrollController();

  /// `null` until the pilot explicitly picks a licence from the dropdown —
  /// the primary jurisdiction is then the default, computed fresh in
  /// [build] each time rather than copied into state once, since the
  /// primary licence itself can only be known once the profile has loaded.
  String? _selectedJurisdictionId;

  late final CalendarDate _today;

  @override
  void initState() {
    super.initState();
    _today = CalendarDate.fromUtcInstant(
      UtcInstant.fromDateTime(DateTime.now().toUtc()),
    );
    _scrollController.addListener(_handleScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    super.dispose();
  }

  /// The mockup's `onHeroScroll`: collapse once the grid has scrolled past
  /// 24px, spring back once it's within 8px of the top — a small dead zone
  /// either side so the chart doesn't flicker at the boundary.
  void _handleScroll() {
    final offset = _scrollController.offset;
    if (_heroExpanded && offset > 24) {
      setState(() => _heroExpanded = false);
    } else if (!_heroExpanded && offset < 8) {
      setState(() => _heroExpanded = true);
    }
  }

  /// The mockup's `toggleHero`: tapping the chart flips it by hand, resetting
  /// the grid to the top first if that's what brings the chart back into its
  /// expanded form, so the two controls never fight each other.
  void _toggleHero() {
    if (!_heroExpanded && _scrollController.hasClients) {
      _scrollController.jumpTo(0);
    }
    setState(() => _heroExpanded = !_heroExpanded);
  }

  @override
  Widget build(BuildContext context) {
    final projectionsAsync = ref.watch(jurisdictionProjectionsProvider);
    final aerodromesAsync = ref.watch(aerodromeDirectoryProvider);
    final primaryIdAsync = ref.watch(primaryJurisdictionIdProvider);

    if (projectionsAsync.isLoading ||
        aerodromesAsync.isLoading ||
        primaryIdAsync.isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (projectionsAsync.hasError ||
        aerodromesAsync.hasError ||
        primaryIdAsync.hasError) {
      return const Scaffold(
        body: EmptyStateMessage(
          icon: Icons.error_outline,
          headline: 'Totals could not be loaded',
          caption: 'Something went wrong reading the logbook.',
        ),
      );
    }

    final projections = projectionsAsync.requireValue;
    if (projections.isEmpty) {
      return const Scaffold(
        body: SafeArea(
          child: EmptyStateMessage(
            icon: Icons.query_stats_outlined,
            headline: 'No licence on file yet',
            caption: 'Totals appear once at least one jurisdiction is held.',
          ),
        ),
      );
    }
    final aerodromes = aerodromesAsync.requireValue;
    final primaryId = primaryIdAsync.requireValue;
    final selectedId =
        _selectedJurisdictionId ??
        (projections.containsKey(primaryId) ? primaryId : null) ??
        projections.keys.first;
    final projection = projections[selectedId]!;

    final flightsAsync = ref.watch(
      committedFlightRecordsProvider((projection, const FlightQuery())),
    );
    return flightsAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, stackTrace) => const Scaffold(
        body: EmptyStateMessage(
          icon: Icons.error_outline,
          headline: 'Totals could not be loaded',
          caption: 'Something went wrong reading the logbook.',
        ),
      ),
      data: (flights) {
        final total = FlightDuration.sum([
          for (final record in flights) record.flight.blockTime,
        ]);
        final buckets = bucketTotals(flights, _granularity, _today);

        return Scaffold(
          body: SafeArea(
            bottom: false,
            child: Column(
              children: [
                TotalsHero(
                  expanded: _heroExpanded,
                  onToggleExpanded: _toggleHero,
                  granularity: _granularity,
                  onGranularityChanged: (g) => setState(() => _granularity = g),
                  buckets: buckets,
                  totalTime: total.toHoursMinutes(),
                  flightCount: flights.length,
                  selectedJurisdictionId: selectedId,
                  jurisdictionOptions: {
                    for (final id in projections.keys)
                      id: jurisdictionLabels[id] ?? id,
                  },
                  onJurisdictionChanged: (id) =>
                      setState(() => _selectedJurisdictionId = id),
                  onOpenMap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute(builder: (_) => const AerodromesScreen()),
                  ),
                  // CLAUDE.md requires an explicit jurisdiction choice
                  // before anything is exported; that flow doesn't exist
                  // yet either, so this deliberately exports nothing rather
                  // than exporting without asking.
                  onExport: () {},
                ),
                Expanded(
                  child: ListView(
                    controller: _scrollController,
                    padding: EdgeInsets.zero,
                    children: [
                      _RecentSection(flights: flights, today: _today),
                      _FunctionSection(
                        flights: flights,
                        projection: projection,
                      ),
                      _ConditionsSection(
                        flights: flights,
                        projection: projection,
                      ),
                      _AircraftSection(flights: flights),
                      _OpsSection(flights: flights, aerodromes: aerodromes),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RecentSection extends StatelessWidget {
  const _RecentSection({required this.flights, required this.today});

  final List<FlightRecord> flights;
  final CalendarDate today;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DetailSectionHeader(label: 'RECENT'),
        TotalsMetricGrid(
          tiles: [
            TotalsMetricTile(
              label: 'THIS YEAR',
              value: sumBlockTimeInRange(
                flights,
                CalendarDate(today.year, 1, 1),
                today,
              ).toHoursMinutes(),
            ),
            TotalsMetricTile(
              label: 'LAST 12 MONTHS',
              value: sumBlockTimeInRange(
                flights,
                today.addDays(-365),
                today,
              ).toHoursMinutes(),
            ),
            TotalsMetricTile(
              label: 'LAST 90 DAYS',
              value: sumBlockTimeInRange(
                flights,
                today.addDays(-90),
                today,
              ).toHoursMinutes(),
            ),
            TotalsMetricTile(
              label: 'LAST 28 DAYS',
              value: sumBlockTimeInRange(
                flights,
                today.addDays(-28),
                today,
              ).toHoursMinutes(),
            ),
          ],
        ),
      ],
    );
  }
}

class _FunctionSection extends StatelessWidget {
  const _FunctionSection({required this.flights, required this.projection});

  final List<FlightRecord> flights;
  final JurisdictionProjection projection;

  @override
  Widget build(BuildContext context) {
    final result = projection.projectAggregate([
      for (final record in flights) (record.flight, record.aircraft),
    ]);
    final rows =
        functionRowsByJurisdiction[projection.jurisdictionId] ?? const [];
    final total = FlightDuration.sum([
      for (final name in rows.map((r) => r.$1))
        if (result[name] case final quantity? when quantity.creditable)
          quantity.value,
    ]);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DetailSectionHeader(
          label: 'FUNCTION',
          trailing: total.toHoursMinutes(),
        ),
        TotalsMetricGrid(
          tiles: [
            for (final name in rows)
              if (result[name.$1] != null)
                TotalsMetricTile(
                  label: name.$2.toUpperCase(),
                  value: (result[name.$1]?.value ?? FlightDuration.zero)
                      .toHoursMinutes(),
                ),
          ],
        ),
      ],
    );
  }
}

class _ConditionsSection extends StatelessWidget {
  const _ConditionsSection({required this.flights, required this.projection});

  final List<FlightRecord> flights;
  final JurisdictionProjection projection;

  @override
  Widget build(BuildContext context) {
    final result = projection.projectAggregate([
      for (final record in flights) (record.flight, record.aircraft),
    ]);
    final rows =
        conditionRowsByJurisdiction[projection.jurisdictionId] ?? const [];

    String valueOf(String name) =>
        (result[name]?.value ?? FlightDuration.zero).toHoursMinutes();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DetailSectionHeader(label: 'CONDITIONS'),
        TotalsMetricGrid(
          tiles: [
            for (final name in rows)
              if (result[name.$1] != null) ...[
                TotalsMetricTile(
                  label: name.$2.toUpperCase(),
                  value: valueOf(name.$1),
                ),
                if (name.$1 == 'crossCountry')
                  TotalsMetricTile(
                    label: 'OF WHICH PIC',
                    value: crossCountryOfWhichPic(
                      flights,
                      projection,
                    ).toHoursMinutes(),
                  ),
              ],
            TotalsMetricTile(
              label: 'LONGEST FLIGHT',
              value: longestFlight(flights).toHoursMinutes(),
            ),
          ],
        ),
      ],
    );
  }
}

class _AircraftSection extends StatelessWidget {
  const _AircraftSection({required this.flights});

  final List<FlightRecord> flights;

  @override
  Widget build(BuildContext context) {
    final groups = groupByAircraft(flights);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DetailSectionHeader(
          label: 'AIRCRAFT',
          trailing: '${distinctAircraftFlown(flights)} flown',
        ),
        TotalsMetricGrid(
          tiles: [
            for (final group in groups)
              for (final classTotal in group.classes)
                TotalsMetricTile(
                  label: classTotal.classLabel.toUpperCase(),
                  value: classTotal.total.toHoursMinutes(),
                ),
          ],
        ),
      ],
    );
  }
}

class _OpsSection extends StatelessWidget {
  const _OpsSection({required this.flights, required this.aerodromes});

  final List<FlightRecord> flights;
  final AerodromeDirectory aerodromes;

  @override
  Widget build(BuildContext context) {
    final counts = opsCounts(flights);
    final landings =
        counts.dayFullStopLandings +
        counts.dayTouchAndGoLandings +
        counts.nightFullStopLandings +
        counts.nightTouchAndGoLandings;
    final visited = aerodromesVisited(flights, aerodromes);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DetailSectionHeader(label: 'OPS'),
        TotalsMetricGrid(
          tiles: [
            TotalsMetricTile(label: 'LANDINGS', value: '$landings'),
            TotalsMetricTile(
              label: 'APPROACHES',
              value: '${counts.instrumentApproaches}',
            ),
            // FSTD sessions have no persistence or read path yet (#28) --
            // omitted rather than fabricated, same call the old Ops tab
            // made.
            TotalsMetricTile(
              label: 'AERODROMES',
              value: '${visited.aerodromes}',
              valueColor: Theme.of(context).colorScheme.primary,
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const AerodromesScreen()),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
