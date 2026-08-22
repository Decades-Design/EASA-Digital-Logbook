import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;

import '../../domain/aerodromes/aerodrome_summary.dart';
import '../../domain/model/aerodrome_directory.dart';
import '../../domain/model/calendar_date.dart';
import '../../domain/model/utc_instant.dart';
import '../../domain/repository/flight_read_repository.dart';
import '../../domain/totals/totals_summary.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../totals/sample_totals_data.dart';

enum _AeroTab { map, list }

/// The number of ranked rows the List tab shows before "All N aerodromes"
/// must be tapped to reveal the rest — matches the mockup's own "most
/// visited" cut, which stops at 7 rows.
const _collapsedRowCount = 7;

/// Aerodromes screen (#62/Phase 3) — pushed from Totals' "Map" header pill
/// and its Ops tab "Aerodromes visited" row, never a bottom-nav tab (the
/// mockup: "the Totals tab stays lit — this is a push, not a fifth tab").
///
/// The Map tab is a deliberate placeholder for this phase — no mapping
/// package has been added, agreed with the project owner rather than pulled
/// in silently (CLAUDE.md: "ask before adding a dependency"). The List tab
/// ranks by **visits** (flights whose route touched an aerodrome), not
/// landings: [Flight.landings] is a per-flight total, not broken down by
/// which leg of a multi-stop route it happened on, so there is no raw fact
/// attributing a landing to one aerodrome over another on a route with more
/// than two stops. See `aerodrome_summary.dart`.
///
/// Runs against `sample_totals_data.dart`'s fixture, the same convention
/// every other screen in this redesign uses pending #56's live repository
/// wiring.
class AerodromesScreen extends StatefulWidget {
  const AerodromesScreen({super.key});

  @override
  State<AerodromesScreen> createState() => _AerodromesScreenState();
}

class _AerodromesScreenState extends State<AerodromesScreen> {
  _AeroTab _tab = _AeroTab.map;
  bool _showAllAerodromes = false;

  List<FlightRecord>? _flights;
  AerodromeDirectory? _aerodromes;
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
    // `cache: false` -- see `NewFlightScreen._loadJurisdictions`'s own note.
    final csv = await rootBundle.loadString(
      'assets/aerodromes/airports.csv',
      cache: false,
    );
    final aerodromes = AerodromeDirectory.fromOurAirportsCsv(csv);
    final flights = sampleTotalsFlights(_today);
    if (!mounted) return;
    setState(() {
      _flights = flights;
      _aerodromes = aerodromes;
    });
  }

  @override
  Widget build(BuildContext context) {
    final flights = _flights;
    final aerodromes = _aerodromes;
    if (flights == null || aerodromes == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _Header(tab: _tab, onTabChanged: (t) => setState(() => _tab = t)),
            Expanded(
              child: _tab == _AeroTab.map
                  ? _MapTab(
                      flights: flights,
                      aerodromes: aerodromes,
                      homeBaseIcao: samplePilotProfile.homeBaseIcao,
                    )
                  : _ListTab(
                      flights: flights,
                      aerodromes: aerodromes,
                      homeBaseIcao: samplePilotProfile.homeBaseIcao,
                      showAll: _showAllAerodromes,
                      onShowAll: () =>
                          setState(() => _showAllAerodromes = true),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.tab, required this.onTabChanged});

  final _AeroTab tab;
  final ValueChanged<_AeroTab> onTabChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => Navigator.of(context).pop(),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chevron_left, size: 20, color: scheme.primary),
                  Text(
                    'Totals',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: scheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 2),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Aerodromes',
                style: theme.textTheme.displaySmall?.copyWith(fontSize: 27),
              ),
              _AeroTabSwitch(selected: tab, onChanged: onTabChanged),
            ],
          ),
        ],
      ),
    );
  }
}

class _AeroTabSwitch extends StatelessWidget {
  const _AeroTabSwitch({required this.selected, required this.onChanged});

  final _AeroTab selected;
  final ValueChanged<_AeroTab> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const labels = {_AeroTab.map: 'Map', _AeroTab.list: 'List'};
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final entry in labels.entries)
            InkWell(
              onTap: () => onChanged(entry.key),
              borderRadius: BorderRadius.circular(6),
              child: Container(
                width: 54,
                padding: const EdgeInsets.symmetric(vertical: 6),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: entry.key == selected ? scheme.surface : null,
                  borderRadius: BorderRadius.circular(6),
                  boxShadow: entry.key == selected
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
                  entry.value,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MapTab extends StatelessWidget {
  const _MapTab({
    required this.flights,
    required this.aerodromes,
    required this.homeBaseIcao,
  });

  final List<FlightRecord> flights;
  final AerodromeDirectory aerodromes;
  final String? homeBaseIcao;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;
    final scheme = theme.colorScheme;
    final visited = aerodromesVisited(flights, aerodromes);
    final newThisYear = newAerodromesThisYear(
      flights,
      CalendarDate.fromUtcInstant(
        flights.isEmpty
            ? UtcInstant.fromDateTime(DateTime.now().toUtc())
            : flights
                  .map((r) => r.flight.offBlocks)
                  .reduce((a, b) => a > b ? a : b),
      ),
    );
    final furthest = homeBaseIcao == null
        ? null
        : furthestAerodrome(flights, aerodromes, homeBaseIcao!);

    return Stack(
      children: [
        Positioned.fill(
          child: Container(
            color: scheme.surfaceContainerLowest,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: ink.faint,
                        width: 1.5,
                        style: BorderStyle.solid,
                      ),
                    ),
                    child: Center(
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: ink.faint,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    'Map placeholder',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: ink.muted,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 40),
                    child: Text(
                      'Full-bleed map with every visited aerodrome plotted, '
                      'pin size by visits, tap a pin for its flights — '
                      'planned once a mapping package is added.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: ink.faint,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Positioned(
          left: 16,
          right: 16,
          bottom: 14,
          child: Container(
            padding: const EdgeInsets.fromLTRB(15, 13, 15, 13),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: scheme.outlineVariant),
              boxShadow: [
                BoxShadow(
                  color: scheme.onSurface.withValues(alpha: 0.16),
                  blurRadius: 22,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'AERODROMES VISITED',
                          style: AppMonoText.tag(
                            ink.muted,
                          ).copyWith(letterSpacing: 1.1),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          '${visited.aerodromes}',
                          style: AppMonoText.value(
                            theme.colorScheme.onSurface,
                            size: 30,
                            weight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          '${visited.countries}',
                          style: AppMonoText.value(
                            theme.colorScheme.onSurface,
                            size: 14,
                            weight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          'COUNTRIES',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: ink.faint,
                            letterSpacing: 0.7,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                Container(
                  margin: const EdgeInsets.only(top: 12),
                  padding: const EdgeInsets.only(top: 11),
                  decoration: BoxDecoration(
                    border: Border(
                      top: BorderSide(color: scheme.outlineVariant),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Flexible(
                        child: Text.rich(
                          furthest == null
                              ? TextSpan(
                                  text: 'Furthest — set a home base to see',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: ink.muted,
                                  ),
                                )
                              : TextSpan(
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: ink.muted,
                                  ),
                                  children: [
                                    const TextSpan(text: 'Furthest '),
                                    TextSpan(
                                      text: furthest.icao,
                                      style: AppMonoText.value(
                                        theme.colorScheme.onSurface,
                                        size: 11.5,
                                        weight: FontWeight.w500,
                                      ),
                                    ),
                                    TextSpan(
                                      text: ' · ${furthest.nm.round()} nm',
                                    ),
                                  ],
                                ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text.rich(
                        TextSpan(
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: ink.muted,
                          ),
                          children: [
                            const TextSpan(text: 'New this year '),
                            TextSpan(
                              text: '$newThisYear',
                              style: AppMonoText.value(
                                theme.colorScheme.onSurface,
                                size: 11.5,
                                weight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ListTab extends StatelessWidget {
  const _ListTab({
    required this.flights,
    required this.aerodromes,
    required this.homeBaseIcao,
    required this.showAll,
    required this.onShowAll,
  });

  final List<FlightRecord> flights;
  final AerodromeDirectory aerodromes;
  final String? homeBaseIcao;
  final bool showAll;
  final VoidCallback onShowAll;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;
    final ranked = rankAerodromesByVisits(flights, aerodromes);
    final furthest = homeBaseIcao == null
        ? null
        : furthestAerodrome(flights, aerodromes, homeBaseIcao!);
    final visibleCount = showAll
        ? ranked.length
        : ranked.length.clamp(0, _collapsedRowCount);

    return ListView(
      children: [
        Container(
          color: theme.colorScheme.surfaceContainerLowest,
          padding: const EdgeInsets.fromLTRB(20, 9, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'MOST VISITED',
                  style: AppMonoText.tag(
                    ink.muted,
                  ).copyWith(letterSpacing: 1.1),
                ),
              ),
              Text('VISITS', style: AppMonoText.tag(ink.faint)),
            ],
          ),
        ),
        const _Divider(),
        for (var i = 0; i < visibleCount; i++) ...[
          _AerodromeRow(
            visit: ranked[i],
            isHomeBase: ranked[i].icao == homeBaseIcao,
            isFurthest: ranked[i].icao == furthest?.icao,
            furthestNm: furthest?.nm,
          ),
          const _Divider(),
        ],
        if (!showAll && ranked.length > _collapsedRowCount)
          InkWell(
            onTap: onShowAll,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'All ${ranked.length} aerodromes',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.primary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: theme.colorScheme.primary,
                  ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 24),
      ],
    );
  }
}

class _AerodromeRow extends StatelessWidget {
  const _AerodromeRow({
    required this.visit,
    required this.isHomeBase,
    required this.isFurthest,
    required this.furthestNm,
  });

  final AerodromeVisit visit;
  final bool isHomeBase;
  final bool isFurthest;
  final double? furthestNm;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;
    final name = visit.aerodrome?.name;
    final subtitle = [
      ?name,
      if (isHomeBase) 'home base',
      if (isFurthest && furthestNm != null)
        'furthest ${furthestNm!.round()} nm',
    ].join(' · ');

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  visit.icao,
                  style: AppMonoText.value(
                    theme.colorScheme.onSurface,
                    size: 14,
                    weight: FontWeight.w600,
                  ),
                ),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: ink.muted,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Text(
            '${visit.visitCount}',
            style: AppMonoText.value(
              theme.colorScheme.onSurface,
              size: 13.5,
              weight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) =>
      Divider(height: 1, color: Theme.of(context).colorScheme.outlineVariant);
}
