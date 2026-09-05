import '../../domain/model/calendar_date.dart';
import '../../domain/model/countersignature.dart';
import '../../domain/model/flight_duration.dart';
import '../../domain/model/flight_times.dart';
import '../../domain/model/pilot_capacity.dart';
import '../../domain/projection/command_time_divergence.dart';
import '../../domain/projection/jurisdiction_projection.dart';
import '../../domain/repository/flight_read_repository.dart';

/// A small flag/tag drawn on a flight row — never a bare colour, always a
/// labelled chip, per CLAUDE.md rule 5 (never render a jurisdiction-
/// dependent fact without saying what it is).
enum FlightRowBadge {
  /// Not yet exported/certified — freely editable (CLAUDE.md rule 4).
  draft,

  /// Committed (exported) but missing the signatory's countersignature.
  unsigned,

  /// This flight's credited command-authority time differs across the
  /// pilot's held licences (`commandTimeDiverges`) — opens the side-by-side
  /// comparison (CLAUDE.md's multi-jurisdiction UX rule).
  mismatch,

  /// At least one night takeoff or landing was logged for this flight — a
  /// raw fact (`CircuitCounts`), not a derived "night flight time" figure,
  /// so this doesn't need a jurisdiction at all.
  night,

  /// An IFR flight plan was filed for this flight (distinct from actual or
  /// simulated instrument conditions — CLAUDE.md rule 2). A raw fact
  /// (`Flight.ifrFlightPlanFiled`).
  ifr,
}

/// What the trailing time column shows in place of a plain "BLOCK" label.
enum FlightTimeState {
  /// The ordinary case: total time as flown, labelled BLOCK.
  block,

  /// A rule primitive's output was manually overridden for this flight —
  /// flagged rather than silently substituted. Not yet computed here — no
  /// override feature exists in the domain model yet.
  overridden,

  /// A countersignature is still pending — the figure is shown, but
  /// visually muted, since it doesn't count yet (CLAUDE.md rule 2).
  notYetCreditable,
}

class FlightRowView {
  const FlightRowView({
    required this.id,
    required this.record,
    required this.isDraft,
    required this.day,
    required this.monthAbbrev,
    required this.route,
    required this.registration,
    required this.crewRole,
    this.crewNote,
    required this.totalTime,
    this.badges = const {},
    this.timeState = FlightTimeState.block,
  });

  final String id;

  /// The underlying record, carried alongside the display fields above so a
  /// tap can open the flight detail screen (#57) without a second lookup.
  final FlightRecord record;
  final bool isDraft;

  final int day;
  final String monthAbbrev;
  final List<String> route;
  final String registration;
  final String crewRole;
  final String? crewNote;
  final Duration totalTime;
  final Set<FlightRowBadge> badges;
  final FlightTimeState timeState;
}

class LogbookMonth {
  const LogbookMonth({
    required this.label,
    required this.flights,
    required this.runningCount,
    required this.runningTotal,
  });

  final String label;
  final List<FlightRowView> flights;

  /// This calendar month's own flight count and total block time — computed
  /// over every flight in the month, not just [flights] (which is however
  /// many rows this build actually renders); the two happen to be equal
  /// here since [buildLogbookMonths] is handed the complete flight set,
  /// unlike the fixture this replaces.
  final int runningCount;
  final Duration runningTotal;
}

const _monthNames = [
  'JANUARY',
  'FEBRUARY',
  'MARCH',
  'APRIL',
  'MAY',
  'JUNE',
  'JULY',
  'AUGUST',
  'SEPTEMBER',
  'OCTOBER',
  'NOVEMBER',
  'DECEMBER',
];

const _monthAbbreviations = [
  'JAN',
  'FEB',
  'MAR',
  'APR',
  'MAY',
  'JUN',
  'JUL',
  'AUG',
  'SEP',
  'OCT',
  'NOV',
  'DEC',
];

/// Command-authority role for this flight, plain-language — PIC, Dual,
/// PICUS, Instructor, Examiner. Jurisdiction-agnostic: this reads
/// [PilotCapacity]'s own raw booleans directly (CLAUDE.md rule 2 keeps
/// command authority a raw fact, separate from any jurisdiction's PIC-time
/// primitive), so it's a plain label rather than a regulatory quantity —
/// unlike Totals' Function tab, which does need the per-jurisdiction
/// primitive.
String _crewRoleLabel(PilotCapacity capacity) {
  if (capacity.actingAsExaminer) return 'Examiner';
  if (capacity.actingAsInstructor) return 'Instructor';
  if (capacity.picusClaimed) return 'PICUS';
  if (capacity.commandAuthority) return 'PIC';
  return 'Dual';
}

/// Whether [record]'s countersignature is still pending — the flight's
/// time doesn't count yet (CLAUDE.md rule 2), regardless of draft/committed
/// state.
bool isPendingCountersignature(FlightRecord record) =>
    record.flight.capacity.countersignature?.status ==
    CountersignatureStatus.pending;

FlightRowView _toRowView(
  FlightRecord record, {
  required bool isDraft,
  required Map<String, JurisdictionProjection> projections,
}) {
  final flight = record.flight;
  final capacity = flight.capacity;
  final date = CalendarDate.fromUtcInstant(flight.offBlocks);
  final pending = isPendingCountersignature(record);
  final nightCircuits =
      flight.landings.nightFullStop + flight.landings.nightTouchAndGo;
  final diverges = commandTimeDiverges([
    for (final projection in projections.values)
      projection.project(flight, record.aircraft),
  ]);

  return FlightRowView(
    id: record.id,
    record: record,
    isDraft: isDraft,
    day: date.day,
    monthAbbrev: _monthAbbreviations[date.month - 1],
    route: flight.route,
    registration: record.aircraft.registration,
    crewRole: _crewRoleLabel(capacity),
    crewNote: flight.remarks.isEmpty ? null : flight.remarks,
    totalTime: Duration(minutes: flight.blockTime.inMinutes),
    badges: {
      if (isDraft) FlightRowBadge.draft,
      if (!isDraft && pending) FlightRowBadge.unsigned,
      if (flight.ifrFlightPlanFiled) FlightRowBadge.ifr,
      if (nightCircuits > 0) FlightRowBadge.night,
      if (diverges) FlightRowBadge.mismatch,
    },
    timeState: pending
        ? FlightTimeState.notYetCreditable
        : FlightTimeState.block,
  );
}

/// Groups every draft and committed flight into newest-first months for the
/// Logbook list (#57, #56) — the real counterpart to
/// `sample_logbook_data.dart`'s fixture.
///
/// [projections] should hold every jurisdiction the pilot currently holds a
/// licence under (see `jurisdictionProjectionsProvider`) — each row's
/// [FlightRowBadge.mismatch] is computed by projecting that flight under
/// every one of them and comparing via `commandTimeDiverges`.
///
/// **Deliberately does not compute [FlightTimeState.overridden]** — a
/// manual-override concept doesn't exist in the domain model at all yet,
/// left for whichever future issue actually builds it rather than
/// half-implemented here.
List<LogbookMonth> buildLogbookMonths(
  List<FlightRecord> draftFlights,
  List<FlightRecord> committedFlights, {
  required Map<String, JurisdictionProjection> projections,
}) {
  final rows = [
    for (final record in draftFlights) (record, true),
    for (final record in committedFlights) (record, false),
  ]..sort((a, b) => b.$1.flight.offBlocks.compareTo(a.$1.flight.offBlocks));

  final byMonth = <(int, int), List<FlightRowView>>{};
  final totalsByMonth = <(int, int), FlightDuration>{};
  for (final (record, isDraft) in rows) {
    final date = CalendarDate.fromUtcInstant(record.flight.offBlocks);
    final key = (date.year, date.month);
    byMonth
        .putIfAbsent(key, () => [])
        .add(_toRowView(record, isDraft: isDraft, projections: projections));
    totalsByMonth[key] =
        (totalsByMonth[key] ?? FlightDuration.zero) + record.flight.blockTime;
  }

  return [
    for (final entry in byMonth.entries)
      LogbookMonth(
        label: '${_monthNames[entry.key.$2 - 1]} ${entry.key.$1}',
        flights: entry.value,
        runningCount: entry.value.length,
        runningTotal: Duration(minutes: totalsByMonth[entry.key]!.inMinutes),
      ),
  ];
}
