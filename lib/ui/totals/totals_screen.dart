import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../domain/jurisdiction/jurisdiction_profile.dart';
import '../../domain/jurisdiction/jurisdiction_registry.dart';
import '../../domain/model/aerodrome_directory.dart';
import '../../domain/model/calendar_date.dart';
import '../../domain/model/flight_duration.dart';
import '../../domain/model/flight_times.dart';
import '../../domain/model/utc_instant.dart';
import '../../domain/primitives/default_primitives.dart';
import '../../domain/projection/jurisdiction_projection.dart';
import '../../domain/repository/flight_read_repository.dart';
import '../../domain/totals/totals_summary.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'sample_totals_data.dart';
import 'widgets/totals_bar_chart.dart';
import 'widgets/totals_row.dart';

const _tabLabels = ['Time', 'Aircraft', 'Function', 'Conditions', 'Ops'];
const _granularityLabels = ['Year', 'Month', 'Week', 'Day'];

const _jurisdictionLabels = {
  'eu.easa.part-fcl': 'EASA Part-FCL',
  'us.faa.part61': 'FAA Part 61',
};

/// #85: totals and summary view — five sub-tabs over one flight set, all
/// rendered under the pilot's **primary** jurisdiction only (CLAUDE.md's
/// multi-jurisdiction UX rule). Total time of flight, aircraft hours and
/// take-off/landing counts are jurisdiction-agnostic facts computed directly
/// off `Flight`/`PilotCapacity`; PIC/dual/night/instrument/cross-country go
/// through the existing `JurisdictionProjection` unchanged. Runs against
/// `sample_totals_data.dart`'s fixture, the same convention Currency and the
/// entry form already use pending #56's live repository wiring.
class TotalsScreen extends StatefulWidget {
  const TotalsScreen({super.key});

  @override
  State<TotalsScreen> createState() => _TotalsScreenState();
}

class _TotalsScreenState extends State<TotalsScreen> {
  int _tabIndex = 0;
  Granularity _granularity = Granularity.year;

  List<FlightRecord>? _flights;
  AerodromeDirectory? _aerodromes;
  JurisdictionProjection? _projection;
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
    // `cache: false` — see `NewFlightScreen._loadJurisdictions`'s own note.
    final results = await Future.wait([
      rootBundle.loadString(
        'assets/jurisdictions/eu.easa.part-fcl.yaml',
        cache: false,
      ),
      rootBundle.loadString(
        'assets/jurisdictions/us.faa.part61.yaml',
        cache: false,
      ),
      rootBundle.loadString('assets/aerodromes/airports.csv', cache: false),
    ]);
    final registry = JurisdictionRegistry([
      parseJurisdictionProfileYaml(results[0]),
      parseJurisdictionProfileYaml(results[1]),
    ]);
    final aerodromes = AerodromeDirectory.fromOurAirportsCsv(results[2]);
    final projection = JurisdictionProjection(
      registry: registry,
      primitives: defaultPrimitives,
      aerodromes: aerodromes,
      jurisdictionId: samplePilotProfile.primaryJurisdictionId,
    );
    final flights = sampleTotalsFlights(_today);
    if (!mounted) return;
    setState(() {
      _flights = flights;
      _aerodromes = aerodromes;
      _projection = projection;
    });
  }

  @override
  Widget build(BuildContext context) {
    final flights = _flights;
    final aerodromes = _aerodromes;
    final projection = _projection;
    if (flights == null || aerodromes == null || projection == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverSafeArea(
            bottom: false,
            sliver: SliverToBoxAdapter(
              child: Column(
                children: [
                  _Header(
                    jurisdictionLabel:
                        _jurisdictionLabels[samplePilotProfile
                            .primaryJurisdictionId] ??
                        samplePilotProfile.primaryJurisdictionId,
                  ),
                  _MainTabs(
                    selected: _tabIndex,
                    onChanged: (i) => setState(() => _tabIndex = i),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: switch (_tabIndex) {
              0 => _TimeTab(
                flights: flights,
                today: _today,
                granularity: _granularity,
                onGranularityChanged: (g) => setState(() => _granularity = g),
              ),
              1 => _AircraftTab(flights: flights),
              2 => _FunctionTab(flights: flights, projection: projection),
              3 => _ConditionsTab(flights: flights, projection: projection),
              _ => _OpsTab(flights: flights, aerodromes: aerodromes),
            },
          ),
          const SliverPadding(padding: EdgeInsets.only(bottom: 96)),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.jurisdictionLabel});

  final String jurisdictionLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Totals',
                style: theme.textTheme.displaySmall?.copyWith(fontSize: 27),
              ),
              Row(
                children: [
                  // Pushes to the Aerodromes screen, which doesn't exist yet
                  // (Phase 4) — a harmless no-op, same convention as
                  // Currency's "Edit".
                  _HeaderPillButton(label: 'Map', onTap: () {}),
                  const SizedBox(width: 8),
                  // CLAUDE.md requires an explicit jurisdiction choice before
                  // anything is exported; that flow doesn't exist yet
                  // either, so this deliberately exports nothing rather than
                  // exporting without asking.
                  _HeaderPillButton(
                    label: 'Export',
                    filled: true,
                    onTap: () {},
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Derived under $jurisdictionLabel — your primary licence',
            style: theme.textTheme.bodySmall?.copyWith(color: ink.muted),
          ),
        ],
      ),
    );
  }
}

class _HeaderPillButton extends StatelessWidget {
  const _HeaderPillButton({
    required this.label,
    required this.onTap,
    this.filled = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? scheme.primary : scheme.surface,
          border: filled ? null : Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: filled ? scheme.onPrimary : scheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _MainTabs extends StatelessWidget {
  const _MainTabs({required this.selected, required this.onChanged});

  final int selected;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Row(
        children: [
          for (var i = 0; i < _tabLabels.length; i++)
            Expanded(
              child: InkWell(
                onTap: () => onChanged(i),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 11),
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: BorderSide(
                        color: i == selected
                            ? theme.colorScheme.primary
                            : Colors.transparent,
                        width: 2.5,
                      ),
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _tabLabels[i],
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: i == selected
                          ? theme.colorScheme.primary
                          : ink.medium,
                      fontWeight: i == selected
                          ? FontWeight.w700
                          : FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _GranularitySwitch extends StatelessWidget {
  const _GranularitySwitch({required this.selected, required this.onChanged});

  final Granularity selected;
  final ValueChanged<Granularity> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          for (var i = 0; i < Granularity.values.length; i++)
            Expanded(
              child: InkWell(
                onTap: () => onChanged(Granularity.values[i]),
                borderRadius: BorderRadius.circular(6),
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Granularity.values[i] == selected
                        ? scheme.surface
                        : null,
                    borderRadius: BorderRadius.circular(6),
                    boxShadow: Granularity.values[i] == selected
                        ? [
                            BoxShadow(
                              color: scheme.onSurface.withValues(alpha: 0.14),
                              blurRadius: 3,
                              offset: const Offset(0, 1),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    _granularityLabels[i],
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: scheme.onSurface,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _TimeTab extends StatelessWidget {
  const _TimeTab({
    required this.flights,
    required this.today,
    required this.granularity,
    required this.onGranularityChanged,
  });

  final List<FlightRecord> flights;
  final CalendarDate today;
  final Granularity granularity;
  final ValueChanged<Granularity> onGranularityChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;
    final total = FlightDuration.sum([
      for (final record in flights) record.flight.blockTime,
    ]);
    final buckets = bucketTotals(flights, granularity, today);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _TabDivider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 13),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'TOTAL TIME OF FLIGHT',
                    style: AppMonoText.tag(
                      ink.muted,
                    ).copyWith(letterSpacing: 1.1),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    total.toHoursMinutes(),
                    style: AppMonoText.value(
                      theme.colorScheme.onSurface,
                      size: 34,
                      weight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${flights.length}',
                    style: AppMonoText.value(
                      theme.colorScheme.onSurface,
                      size: 17,
                      weight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'FLIGHTS',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: ink.faint,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const _TabDivider(),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 11, 20, 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _GranularitySwitch(
                selected: granularity,
                onChanged: onGranularityChanged,
              ),
              const SizedBox(height: 12),
              TotalsBarChart(buckets: buckets),
            ],
          ),
        ),
        const _TabDivider(),
        TotalsRow(
          label: 'This year',
          value: sumBlockTimeInRange(
            flights,
            CalendarDate(today.year, 1, 1),
            today,
          ).toHoursMinutes(),
        ),
        const _TabDivider(),
        TotalsRow(
          label: 'Last 12 months',
          value: sumBlockTimeInRange(
            flights,
            today.addDays(-365),
            today,
          ).toHoursMinutes(),
        ),
        const _TabDivider(),
        TotalsRow(
          label: 'Last 90 days',
          value: sumBlockTimeInRange(
            flights,
            today.addDays(-90),
            today,
          ).toHoursMinutes(),
        ),
        const _TabDivider(),
        TotalsRow(
          label: 'Last 28 days',
          value: sumBlockTimeInRange(
            flights,
            today.addDays(-28),
            today,
          ).toHoursMinutes(),
        ),
        const _TabDivider(),
      ],
    );
  }
}

class _AircraftTab extends StatelessWidget {
  const _AircraftTab({required this.flights});

  final List<FlightRecord> flights;

  @override
  Widget build(BuildContext context) {
    final groups = groupByAircraft(flights);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _TabDivider(),
        for (final group in groups) ...[
          TotalsSectionHeader(
            label: group.multiPilot ? 'MULTI-PILOT' : 'SINGLE-PILOT',
            trailing: group.total.toHoursMinutes(),
          ),
          for (final classTotal in group.classes) ...[
            const _TabDivider(),
            if (classTotal.isSingleType)
              TotalsRow(
                label: classTotal.classLabel,
                value: classTotal.total.toHoursMinutes(),
                emphasis: true,
              )
            else ...[
              TotalsRow(
                label: classTotal.classLabel,
                value: classTotal.total.toHoursMinutes(),
                emphasis: true,
              ),
              for (final type in classTotal.types) ...[
                const _TabDivider(),
                TotalsRow(
                  label: type.typeLabel,
                  value: type.total.toHoursMinutes(),
                  indent: true,
                ),
              ],
            ],
          ],
        ],
        const _TabDivider(),
        TotalsRow(
          label: 'Aircraft flown',
          value: '${distinctAircraftFlown(flights)}',
        ),
        const _TabDivider(),
      ],
    );
  }
}

class _FunctionTab extends StatelessWidget {
  const _FunctionTab({required this.flights, required this.projection});

  final List<FlightRecord> flights;
  final JurisdictionProjection projection;

  @override
  Widget build(BuildContext context) {
    final result = projection.projectAggregate([
      for (final record in flights) (record.flight, record.aircraft),
    ]);
    const functionQuantityNames = [
      'pic',
      'picus',
      'spic',
      'copilot',
      'dual',
      'instructor',
    ];
    final total = FlightDuration.sum([
      for (final name in functionQuantityNames)
        if (result[name] case final quantity? when quantity.creditable)
          quantity.value,
    ]);

    String valueOf(String name) =>
        (result[name]?.value ?? FlightDuration.zero).toHoursMinutes();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _TabDivider(),
        TotalsSectionHeader(
          label: 'PILOT FUNCTION TIME',
          trailing: total.toHoursMinutes(),
        ),
        for (final name in const [
          ('pic', 'PIC'),
          ('picus', 'PICUS'),
          ('spic', 'SPIC'),
          ('copilot', 'Co-pilot'),
          ('dual', 'Dual'),
          ('instructor', 'Instructor'),
        ])
          if (result[name.$1] != null) ...[
            const _TabDivider(),
            TotalsRow(label: name.$2, value: valueOf(name.$1)),
          ],
        const _TabDivider(),
        const TotalsSectionHeader(label: 'OTHER ARRANGEMENTS'),
        const _TabDivider(),
        TotalsRow(label: 'Solo', value: soloTime(flights).toHoursMinutes()),
        const _TabDivider(),
        Builder(
          builder: (context) {
            final awaiting = awaitingCountersignatureTime(flights);
            return TotalsRow(
              label: 'Awaiting countersignature',
              value: awaiting.toHoursMinutes(),
              valueColor: awaiting == FlightDuration.zero
                  ? null
                  : context.semanticColors.currencyWarning,
            );
          },
        ),
        const _TabDivider(),
      ],
    );
  }
}

class _ConditionsTab extends StatelessWidget {
  const _ConditionsTab({required this.flights, required this.projection});

  final List<FlightRecord> flights;
  final JurisdictionProjection projection;

  @override
  Widget build(BuildContext context) {
    final result = projection.projectAggregate([
      for (final record in flights) (record.flight, record.aircraft),
    ]);

    String valueOf(String name) =>
        (result[name]?.value ?? FlightDuration.zero).toHoursMinutes();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _TabDivider(),
        const TotalsSectionHeader(label: 'OPERATIONAL CONDITION TIME'),
        for (final name in const [
          ('night', 'Night'),
          ('ifr', 'IFR'),
          ('actualInstrument', 'Actual instrument'),
          ('simulatedInstrument', 'Simulated instrument'),
          ('crossCountry', 'Cross-country'),
        ])
          if (result[name.$1] != null) ...[
            const _TabDivider(),
            TotalsRow(label: name.$2, value: valueOf(name.$1)),
            if (name.$1 == 'crossCountry') ...[
              const _TabDivider(),
              TotalsRow(
                label: 'of which PIC',
                value: crossCountryOfWhichPic(
                  flights,
                  projection,
                ).toHoursMinutes(),
                indent: true,
              ),
            ],
          ],
        const _TabDivider(),
        TotalsRow(
          label: 'Longest flight',
          value: longestFlight(flights).toHoursMinutes(),
        ),
        const _TabDivider(),
      ],
    );
  }
}

class _OpsTab extends StatelessWidget {
  const _OpsTab({required this.flights, required this.aerodromes});

  final List<FlightRecord> flights;
  final AerodromeDirectory aerodromes;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;
    final counts = opsCounts(flights);
    final visited = aerodromesVisited(flights, aerodromes);

    Widget circuitRow(String label, int takeoffs, int landings) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.titleSmall)),
          SizedBox(
            width: 46,
            child: Text(
              '$takeoffs',
              textAlign: TextAlign.right,
              style: AppMonoText.value(theme.colorScheme.onSurface, size: 13.5),
            ),
          ),
          SizedBox(
            width: 46,
            child: Text(
              '$landings',
              textAlign: TextAlign.right,
              style: AppMonoText.value(theme.colorScheme.onSurface, size: 13.5),
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _TabDivider(),
        Container(
          color: theme.colorScheme.surfaceContainerLowest,
          padding: const EdgeInsets.fromLTRB(20, 9, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'TAKE-OFFS & LANDINGS',
                  style: AppMonoText.tag(
                    ink.muted,
                  ).copyWith(letterSpacing: 1.1),
                ),
              ),
              SizedBox(
                width: 46,
                child: Text(
                  'T/O',
                  textAlign: TextAlign.right,
                  style: AppMonoText.tag(ink.faint),
                ),
              ),
              SizedBox(
                width: 46,
                child: Text(
                  'LDG',
                  textAlign: TextAlign.right,
                  style: AppMonoText.tag(ink.faint),
                ),
              ),
            ],
          ),
        ),
        const _TabDivider(),
        circuitRow(
          'Day, full stop',
          counts.dayFullStopTakeoffs,
          counts.dayFullStopLandings,
        ),
        const _TabDivider(),
        circuitRow(
          'Day, touch & go',
          counts.dayTouchAndGoTakeoffs,
          counts.dayTouchAndGoLandings,
        ),
        const _TabDivider(),
        circuitRow(
          'Night, full stop',
          counts.nightFullStopTakeoffs,
          counts.nightFullStopLandings,
        ),
        const _TabDivider(),
        circuitRow(
          'Night, touch & go',
          counts.nightTouchAndGoTakeoffs,
          counts.nightTouchAndGoLandings,
        ),
        const _TabDivider(),
        const TotalsSectionHeader(label: 'APPROACHES & FSTD'),
        const _TabDivider(),
        TotalsRow(
          label: 'Instrument approaches',
          value: '${counts.instrumentApproaches}',
        ),
        const _TabDivider(),
        // FSTD sessions have no persistence or read path yet (#28) --
        // omitted rather than fabricated.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Aerodromes visited', style: theme.textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(
                '${visited.aerodromes} across ${visited.countries} '
                'countries',
                style: theme.textTheme.labelSmall?.copyWith(color: ink.faint),
              ),
              const SizedBox(height: 6),
              Text(
                '${visited.aerodromes}',
                style: AppMonoText.value(
                  theme.colorScheme.onSurface,
                  size: 13.5,
                ),
              ),
            ],
          ),
        ),
        const _TabDivider(),
      ],
    );
  }
}

class _TabDivider extends StatelessWidget {
  const _TabDivider();

  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant);
}
