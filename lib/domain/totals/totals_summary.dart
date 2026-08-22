import '../model/aircraft.dart';
import '../model/aerodrome_directory.dart';
import '../model/calendar_date.dart';
import '../model/countersignature.dart';
import '../model/flight.dart';
import '../model/flight_duration.dart';
import '../model/flight_times.dart';
import '../projection/projection.dart';
import '../repository/flight_read_repository.dart';

/// Pure aggregation over a flight set for the Totals screen — mirrors
/// `currency_dashboard.dart`'s shape (no Flutter import, unit-tested,
/// deterministic). Every figure here is either jurisdiction-agnostic (total
/// time of flight, aircraft hours, take-off/landing counts — CLAUDE.md rule
/// 5) or a raw-fact sum straight off [Flight]/[PilotCapacity]; anything
/// genuinely jurisdiction-dependent (PIC/dual/night/instrument/...) goes
/// through the existing [Projection.projectAggregate] instead, unchanged.

// ---- Time tab.

enum Granularity { year, month, week, day }

class TimeBucket {
  const TimeBucket({
    required this.label,
    required this.value,
    required this.isCurrent,
  });

  final String label;
  final FlightDuration value;

  /// Whether this is the bucket [asOf] itself falls in — the chart's own
  /// "current period" highlight.
  final bool isCurrent;
}

/// Buckets total time of flight into the last [count] periods ending at
/// [asOf], oldest first.
///
/// [Granularity.week] is 8 rolling 7-day windows ending at [asOf], not ISO
/// calendar weeks — a deliberate simplification for a chart axis label, not
/// a figure anything else depends on.
List<TimeBucket> bucketTotals(
  List<FlightRecord> flights,
  Granularity granularity,
  CalendarDate asOf, {
  int count = 8,
}) {
  switch (granularity) {
    case Granularity.year:
      return _bucketByCalendarField(
        flights,
        asOf,
        count,
        fieldOf: (date) => date.year,
        currentField: asOf.year,
        labelOf: (year) => '$year',
        stepBack: (field, steps) => field - steps,
      );
    case Granularity.month:
      final currentIndex = asOf.year * 12 + (asOf.month - 1);
      return _bucketByCalendarField(
        flights,
        asOf,
        count,
        fieldOf: (date) => date.year * 12 + (date.month - 1),
        currentField: currentIndex,
        labelOf: (index) => _monthAbbreviations[index % 12],
        stepBack: (field, steps) => field - steps,
      );
    case Granularity.week:
      return _bucketByDayWindow(flights, asOf, count, windowDays: 7);
    case Granularity.day:
      return _bucketByDayWindow(flights, asOf, count, windowDays: 1);
  }
}

const _monthAbbreviations = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

List<TimeBucket> _bucketByCalendarField(
  List<FlightRecord> flights,
  CalendarDate asOf,
  int count, {
  required int Function(CalendarDate date) fieldOf,
  required int currentField,
  required String Function(int field) labelOf,
  required int Function(int field, int steps) stepBack,
}) {
  final totals = <int, FlightDuration>{};
  for (final record in flights) {
    final field = fieldOf(CalendarDate.fromUtcInstant(record.flight.offBlocks));
    totals[field] =
        (totals[field] ?? FlightDuration.zero) + record.flight.blockTime;
  }

  return [
    for (var i = 0; i < count; i++)
      () {
        final field = stepBack(currentField, count - 1 - i);
        return TimeBucket(
          label: labelOf(field),
          value: totals[field] ?? FlightDuration.zero,
          isCurrent: field == currentField,
        );
      }(),
  ];
}

List<TimeBucket> _bucketByDayWindow(
  List<FlightRecord> flights,
  CalendarDate asOf,
  int count, {
  required int windowDays,
}) {
  // Bucket 0 is the oldest window, bucket `count - 1` is the one containing
  // `asOf` itself; a flight `daysAgo` days before `asOf` falls in window
  // `daysAgo ~/ windowDays` counting back from the current one.
  final sums = List<FlightDuration>.filled(count, FlightDuration.zero);
  for (final record in flights) {
    final date = CalendarDate.fromUtcInstant(record.flight.offBlocks);
    final daysAgo = asOf.differenceInDays(date);
    if (daysAgo < 0) continue; // A flight logged in the future — ignore it.
    final windowsBack = daysAgo ~/ windowDays;
    if (windowsBack >= count) continue;
    final index = count - 1 - windowsBack;
    sums[index] = sums[index] + record.flight.blockTime;
  }

  return [
    for (var i = 0; i < count; i++)
      TimeBucket(
        label: windowDays == 1
            ? '${asOf.addDays(-(count - 1 - i)).day}'
            : (count - 1 - i == 0
                  ? 'now'
                  : '-${(count - 1 - i) * windowDays}d'),
        value: sums[i],
        isCurrent: i == count - 1,
      ),
  ];
}

/// Total time of flight for every flight whose off-blocks date falls within
/// `[from, to]`, inclusive both ends — the four fixed summary rows (this
/// year / last 12 months / last 90 days / last 28 days).
FlightDuration sumBlockTimeInRange(
  List<FlightRecord> flights,
  CalendarDate from,
  CalendarDate to,
) {
  return FlightDuration.sum([
    for (final record in flights)
      if (_dateOf(record) case final date when date >= from && date <= to)
        record.flight.blockTime,
  ]);
}

CalendarDate _dateOf(FlightRecord record) =>
    CalendarDate.fromUtcInstant(record.flight.offBlocks);

// ---- Aircraft tab.

/// "SEP (land)" / "MEP (land)" / "TMG" from an aircraft's own facts — pure
/// formatting, not regulatory logic, so it lives here rather than as a
/// primitive. Turboprop/turbofan/turbojet aircraft (typically type-rated,
/// not class-rated) fall back to their own type label, which
/// [groupByAircraft] then collapses a class down to a single row for —
/// there is no separate "class" concept above a jet's own type the way
/// there is for a piston single or twin.
String aircraftClassLabel(Aircraft aircraft) {
  if (aircraft.category == AircraftCategory.touringMotorGlider) {
    return 'TMG';
  }
  if (aircraft.category == AircraftCategory.aeroplane &&
      aircraft.engineType == EngineType.piston) {
    final surface = switch (aircraft.operatingSurface) {
      OperatingSurface.land => 'land',
      OperatingSurface.sea => 'sea',
      OperatingSurface.amphibian => 'amphibian',
    };
    final prefix = aircraft.engineCount == 1 ? 'SEP' : 'MEP';
    return '$prefix ($surface)';
  }
  return aircraftTypeLabel(aircraft);
}

/// The specific type an aircraft resolves to for grouping — the same
/// fallback chain `Aircraft.typeRatingDesignator`'s own dartdoc describes
/// for joining two registrations of one type into a single held rating.
String aircraftTypeLabel(Aircraft aircraft) =>
    aircraft.typeRatingDesignator ??
    aircraft.icaoTypeDesignator ??
    '${aircraft.manufacturer} ${aircraft.model}'.trim();

class AircraftTypeTotal {
  const AircraftTypeTotal({required this.typeLabel, required this.total});
  final String typeLabel;
  final FlightDuration total;
}

class AircraftClassTotal {
  const AircraftClassTotal({
    required this.classLabel,
    required this.total,
    required this.types,
  });
  final String classLabel;
  final FlightDuration total;
  final List<AircraftTypeTotal> types;

  /// True when this class has exactly one type sharing its own label (the
  /// jet case [aircraftClassLabel] describes) — the row this collapses to a
  /// single line for, rather than a class header repeating its only child.
  bool get isSingleType =>
      types.length == 1 && types.single.typeLabel == classLabel;
}

class AircraftGroupTotal {
  const AircraftGroupTotal({
    required this.multiPilot,
    required this.total,
    required this.classes,
  });
  final bool multiPilot;
  final FlightDuration total;
  final List<AircraftClassTotal> classes;
}

/// Single-pilot/multi-pilot (`PilotCapacity.multiPilotOperation`) → class
/// (`aircraftClassLabel`) → specific type (`aircraftTypeLabel`), each level
/// carrying its own summed block time. Single-pilot sorts before
/// multi-pilot always (there are only ever the two); classes and types
/// within a group sort by descending total.
List<AircraftGroupTotal> groupByAircraft(List<FlightRecord> flights) {
  final byMultiPilot = <bool, Map<String, Map<String, FlightDuration>>>{};

  for (final record in flights) {
    final multiPilot = record.flight.capacity.multiPilotOperation;
    final classLabel = aircraftClassLabel(record.aircraft);
    final typeLabel = aircraftTypeLabel(record.aircraft);
    final classes = byMultiPilot.putIfAbsent(multiPilot, () => {});
    final types = classes.putIfAbsent(classLabel, () => {});
    types[typeLabel] =
        (types[typeLabel] ?? FlightDuration.zero) + record.flight.blockTime;
  }

  final groups = <AircraftGroupTotal>[];
  for (final multiPilot in [false, true]) {
    final classes = byMultiPilot[multiPilot];
    if (classes == null || classes.isEmpty) continue;

    final classTotals = [
      for (final entry in classes.entries)
        AircraftClassTotal(
          classLabel: entry.key,
          total: FlightDuration.sum(entry.value.values),
          types: [
            for (final typeEntry in entry.value.entries)
              AircraftTypeTotal(
                typeLabel: typeEntry.key,
                total: typeEntry.value,
              ),
          ]..sort((a, b) => b.total.compareTo(a.total)),
        ),
    ]..sort((a, b) => b.total.compareTo(a.total));

    groups.add(
      AircraftGroupTotal(
        multiPilot: multiPilot,
        total: FlightDuration.sum(classTotals.map((c) => c.total)),
        classes: classTotals,
      ),
    );
  }
  return groups;
}

/// Distinct aircraft (by registration) flown across [flights].
int distinctAircraftFlown(List<FlightRecord> flights) =>
    {for (final record in flights) record.aircraft.registration}.length;

// ---- Function tab: "other arrangements".

/// Sum of block time for flights flown as sole occupant.
FlightDuration soloTime(List<FlightRecord> flights) => FlightDuration.sum([
  for (final record in flights)
    if (record.flight.capacity.soleOccupant) record.flight.blockTime,
]);

/// Sum of block time for flights whose countersignature is still
/// [CountersignatureStatus.pending] — a raw fact straight off
/// [PilotCapacity.countersignature], not something [Projection] needs to
/// compute: this is the same fact `easa_pilot_function_time.dart`'s own
/// `_countersignedQuantity` already branches on, just summed directly
/// rather than folded into an excluded-total string.
FlightDuration awaitingCountersignatureTime(List<FlightRecord> flights) =>
    FlightDuration.sum([
      for (final record in flights)
        if (record.flight.capacity.countersignature?.status ==
            CountersignatureStatus.pending)
          record.flight.blockTime,
    ]);

// ---- Conditions tab.

/// Cross-country time, restricted to flights flown with command authority —
/// the Conditions tab's "of which PIC" sub-row. Reads the per-flight
/// cross-country quantity from [projection] rather than re-deriving it.
FlightDuration crossCountryOfWhichPic(
  List<FlightRecord> flights,
  Projection projection,
) {
  var total = FlightDuration.zero;
  for (final record in flights) {
    if (!record.flight.capacity.commandAuthority) continue;
    final result = projection.project(record.flight, record.aircraft);
    final quantity = result['crossCountry'];
    if (quantity != null && quantity.creditable) {
      total = total + quantity.value;
    }
  }
  return total;
}

FlightDuration longestFlight(List<FlightRecord> flights) => flights.isEmpty
    ? FlightDuration.zero
    : flights.map((r) => r.flight.blockTime).reduce((a, b) => a > b ? a : b);

// ---- Ops tab.

class OpsCounts {
  const OpsCounts({
    required this.dayFullStopTakeoffs,
    required this.dayFullStopLandings,
    required this.dayTouchAndGoTakeoffs,
    required this.dayTouchAndGoLandings,
    required this.nightFullStopTakeoffs,
    required this.nightFullStopLandings,
    required this.nightTouchAndGoTakeoffs,
    required this.nightTouchAndGoLandings,
    required this.instrumentApproaches,
  });

  final int dayFullStopTakeoffs;
  final int dayFullStopLandings;
  final int dayTouchAndGoTakeoffs;
  final int dayTouchAndGoLandings;
  final int nightFullStopTakeoffs;
  final int nightFullStopLandings;
  final int nightTouchAndGoTakeoffs;
  final int nightTouchAndGoLandings;
  final int instrumentApproaches;
}

OpsCounts opsCounts(List<FlightRecord> flights) {
  var dfsT = 0, dfsL = 0, dtgT = 0, dtgL = 0;
  var nfsT = 0, nfsL = 0, ntgT = 0, ntgL = 0;
  var approaches = 0;

  for (final record in flights) {
    final t = record.flight.takeoffs;
    final l = record.flight.landings;
    dfsT += t.dayFullStop;
    dtgT += t.dayTouchAndGo;
    nfsT += t.nightFullStop;
    ntgT += t.nightTouchAndGo;
    dfsL += l.dayFullStop;
    dtgL += l.dayTouchAndGo;
    nfsL += l.nightFullStop;
    ntgL += l.nightTouchAndGo;
    for (final approach in record.flight.approaches) {
      approaches += approach.count;
    }
  }

  return OpsCounts(
    dayFullStopTakeoffs: dfsT,
    dayFullStopLandings: dfsL,
    dayTouchAndGoTakeoffs: dtgT,
    dayTouchAndGoLandings: dtgL,
    nightFullStopTakeoffs: nfsT,
    nightFullStopLandings: nfsL,
    nightTouchAndGoTakeoffs: ntgT,
    nightTouchAndGoLandings: ntgL,
    instrumentApproaches: approaches,
  );
}

/// Aerodromes visited across every route leg, resolved for country via
/// [directory] — the Ops tab's "Aerodromes visited" row. An identifier the
/// directory doesn't recognise (a private strip, an unlicensed field —
/// `Flight.route`'s own dartdoc) still counts toward [aerodromes] but not
/// toward [countries], since there is nothing to resolve it to.
///
/// Deliberately does not compute a "furthest" distance — that needs a home
/// base reference point that doesn't exist anywhere in the domain yet.
({int aerodromes, int countries}) aerodromesVisited(
  List<FlightRecord> flights,
  AerodromeDirectory directory,
) {
  final icaoCodes = <String>{};
  for (final record in flights) {
    icaoCodes.addAll(record.flight.route);
  }
  final countries = <String>{
    for (final code in icaoCodes)
      if (directory.byIcao(code)?.isoCountry != null)
        directory.byIcao(code)!.isoCountry!,
  };
  return (aerodromes: icaoCodes.length, countries: countries.length);
}
