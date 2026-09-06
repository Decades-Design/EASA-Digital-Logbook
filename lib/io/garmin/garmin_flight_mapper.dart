import '../../domain/model/aircraft.dart';
import '../../domain/model/flight.dart';
import '../../domain/model/flight_duration.dart';
import '../../domain/model/instructor_presence.dart';
import '../../domain/model/pilot_capacity.dart';
import '../../domain/model/utc_instant.dart';

/// Either a mapped [CanonicalImportRow]-shaped `(flight, unmappedFields,
/// reviewNotes)` triple, or an [error] naming why the row could not be
/// mapped at all — the same shape `ForeFlightFlightMapping` uses, and for
/// the same reason: a thrown exception mid-file would abort every row
/// after it, rather than reporting this one row's problem and continuing.
class GarminFlightMapping {
  const GarminFlightMapping.mapped({
    required this.flight,
    this.unmappedFields = const {},
    this.reviewNotes = const [],
  }) : error = null;

  const GarminFlightMapping.error(this.error)
    : flight = null,
      unmappedFields = const {},
      reviewNotes = const [];

  final Flight? flight;
  final String? error;
  final Map<String, String> unmappedFields;
  final List<String> reviewNotes;
}

FlightDuration _duration(Map<String, String> row, String column) {
  final raw = row[column] ?? '';
  if (raw.isEmpty) return FlightDuration.zero;
  try {
    return FlightDuration.parseDecimalHours(raw);
  } on FormatException {
    return FlightDuration.zero;
  }
}

int _count(Map<String, String> row, String column) =>
    int.tryParse(row[column] ?? '') ?? 0;

/// Splits Garmin's single `Route` column (e.g. `LIQB-LIRZ-LIPY-LIQB`) into
/// [Flight.route]. Unlike ForeFlight, Garmin's `Route` already includes the
/// departure and destination — `Departure`/`Destination` are redundant
/// duplicates of its first and last element, not a separate fact.
List<String> _route(Map<String, String> row) =>
    (row['Route'] ?? '').split('-').where((s) => s.isNotEmpty).toList();

UtcInstant? _dateStart(String dateRaw) {
  if (dateRaw.isEmpty) return null;
  return UtcInstant.tryParse('${dateRaw}T00:00:00Z');
}

/// Resolves [Flight.offBlocks]/[onBlocks] from Garmin's `Time Out`/`Time
/// In` columns, or reports why they can't be trusted.
///
/// Garmin Pilot lets a flight be logged with only a decimal `Total
/// Duration` and a `Date`, with no block times recorded at all — and real
/// exports show `Time Out`/`Time In` are sometimes stamped with a much
/// later timestamp than `Date` itself instead of being left blank (an
/// edit-session artifact: touching an old decimal-only entry appears to
/// backfill these columns with the moment of the edit, not a real block
/// time — e.g. a row dated `2022-06-25` with `Time Out` reading
/// `2023-10-29T11:00:00Z`). `Flight.offBlocks`/`onBlocks` are non-nullable
/// raw facts (rule 3) and this app has no duration-only path for a regular
/// flight (`docs/entry-form.md` §2), so a row that fails this check
/// becomes an [ImportRowError] rather than a fabricated clock time — the
/// project owner's own call on #71, not a guess.
///
/// A row is trusted only when both timestamps are present, `Time Out`'s
/// calendar date (UTC) matches `Date`, `Time In` is strictly after `Time
/// Out`, and `Time In`'s calendar date is `Date` or `Date` + 1 (a flight
/// crossing midnight Zulu).
({UtcInstant? offBlocks, UtcInstant? onBlocks, String? error}) _blockTimes(
  Map<String, String> row,
) {
  final dateStart = _dateStart(row['Date'] ?? '');
  if (dateStart == null) {
    return (
      offBlocks: null,
      onBlocks: null,
      error: 'Date "${row['Date']}" is missing or unparseable.',
    );
  }
  final dateEnd = dateStart.add(const Duration(days: 1));

  final timeOut = UtcInstant.tryParse(row['Time Out'] ?? '');
  final timeIn = UtcInstant.tryParse(row['Time In'] ?? '');
  if (timeOut == null || timeIn == null) {
    return (
      offBlocks: null,
      onBlocks: null,
      error:
          'No reliable off/on-block times: Time Out and/or Time In are '
          'blank, so only a total duration was recorded for this flight. '
          'This app has no duration-only path for a regular flight — every '
          'flight needs real block times. Re-enter it by hand if you want '
          'it in the app.',
    );
  }
  if (timeOut < dateStart || timeOut >= dateEnd) {
    return (
      offBlocks: null,
      onBlocks: null,
      error:
          'Time Out (${timeOut.toIso8601String()}) is not on this flight\'s '
          'own Date (${row['Date']}) — this looks like a Garmin edit-session '
          'timestamp rather than a real off-blocks time, not a reliable '
          'raw fact. Re-enter it by hand if you want it in the app.',
    );
  }
  if (timeIn <= timeOut || timeIn >= dateEnd.add(const Duration(days: 1))) {
    return (
      offBlocks: null,
      onBlocks: null,
      error:
          'Time In (${timeIn.toIso8601String()}) is not after Time Out on '
          'this flight\'s own Date (${row['Date']}), or the following day — '
          'not a reliable raw fact. Re-enter it by hand if you want it in '
          'the app.',
    );
  }

  return (offBlocks: timeOut, onBlocks: timeIn, error: null);
}

/// `Time Off`/`Time On` (wheels-off / wheels-on), read as best-effort
/// optional air time — never rejects the row, unlike the block times
/// above, since `Flight.takeoff`/`landing` are genuinely optional
/// (`docs/entry-form.md` §2). A value outside `[offBlocks, onBlocks]` is
/// dropped silently rather than surfaced as an error, on the theory that
/// air time is a bonus fact, not one this app depends on.
UtcInstant? _optionalAirTime(
  Map<String, String> row,
  String column,
  UtcInstant offBlocks,
  UtcInstant onBlocks,
) {
  final parsed = UtcInstant.tryParse(row[column] ?? '');
  if (parsed == null) return null;
  if (parsed < offBlocks || parsed > onBlocks) return null;
  return parsed;
}

/// Parses Garmin's `Approaches` cell, formatted as one or more
/// `'AERODROME' 'TYPE' 'RUNWAY' (COUNT)` groups, e.g. `'LIPO' 'ILS' '32'
/// (1)`. Returns every group matched; the caller adds a review note when
/// the cell is non-blank but nothing matched, rather than dropping it
/// silently.
final _approachPattern = RegExp(r"'(\w+)'\s*'([\w]+)'\s*'(\w+)'\s*\((\d+)\)");

({List<Approach> approaches, String? unparsed}) _parseApproaches(String cell) {
  if (cell.trim().isEmpty) return (approaches: const [], unparsed: null);

  final matches = _approachPattern.allMatches(cell).toList();
  if (matches.isEmpty) return (approaches: const [], unparsed: cell);

  final approaches = <Approach>[];
  for (final match in matches) {
    final aerodrome = match.group(1)!;
    final description = match.group(2)!.toUpperCase();
    final runway = match.group(3)!;
    final count = int.tryParse(match.group(4)!) ?? 1;

    final type = switch (description) {
      _ when description.contains('ILS') => ApproachType.ils,
      _ when description.contains('RNAV') => ApproachType.rnav,
      _ when description.contains('RNP') => ApproachType.rnav,
      _ when description.contains('GNSS') => ApproachType.rnav,
      _ when description.contains('GPS') => ApproachType.gps,
      _ when description.contains('VOR') => ApproachType.vor,
      _ when description.contains('NDB') => ApproachType.ndb,
      _ when description.contains('TACAN') => ApproachType.tacan,
      _ when description.contains('SDF') => ApproachType.sdf,
      _ when description.contains('LDA') => ApproachType.lda,
      _ when description.contains('MLS') => ApproachType.mls,
      _ when description.contains('ASR') => ApproachType.asr,
      _ when description.contains('PAR') => ApproachType.par,
      _ when description.contains('LOC') => ApproachType.loc,
      _ => null,
    };
    if (type == null) continue;

    approaches.add(
      Approach(
        type: type,
        aerodromeIcao: aerodrome,
        runway: runway,
        count: count,
      ),
    );
  }

  return (approaches: approaches, unparsed: approaches.isEmpty ? cell : null);
}

/// Columns folded into [Flight] directly, or intentionally dropped as
/// redundant with a value reconstructed elsewhere — listed once here so
/// the "everything else" loop that builds unmappedFields knows what to
/// skip. `Total Duration`/`Flight Duration` are block time, which this app
/// computes from offBlocks/onBlocks rather than storing (rule 1); `Legs`
/// is `route.length - 1`; `Departure`/`Destination` duplicate `Route`'s
/// first and last element.
const _mappedColumns = {
  'Date',
  'Aircraft ID',
  'Aircraft Type',
  'Multi-Pilot',
  'Time Out',
  'Time Off',
  'Time On',
  'Time In',
  'PIC Duration',
  'SIC Duration',
  'Solo Duration',
  'Dual Received Duration',
  'Dual Given Duration',
  'Evaluator Duration',
  'Cross Country Duration',
  'Actual Instrument Duration',
  'Simulated Instrument Duration',
  'Simulator Duration',
  'Instructor Name',
  'PIC Name',
  'Day Takeoffs',
  'Night Takeoffs',
  'Day Landings',
  'Night Landings',
  'Approaches',
  'Holding Patterns',
  'Track Nav Aid',
  'Departure',
  'Destination',
  'Route',
  'Legs',
  'Total Duration',
  'Flight Duration',
};

/// This pilot's [PilotCapacity] reverse-projected from Garmin's own
/// derived duration columns — the same "inherently lossy" problem
/// `foreflight_flight_mapper.dart` documents for ForeFlight, with a
/// different set of gaps: Garmin has no PICUS-hours column at all (so an
/// EASA PICUS claim can never be reconstructed from this export), but does
/// have `Evaluator Duration`, which ForeFlight's schema lacks. Every
/// branch that made a judgement call appends to [notes] rather than
/// staying silent about it.
PilotCapacity _classifyCapacity({
  required Map<String, String> row,
  required Aircraft aircraft,
  required List<String> notes,
}) {
  final pic = _duration(row, 'PIC Duration');
  final sic = _duration(row, 'SIC Duration');
  final solo = _duration(row, 'Solo Duration');
  final dualReceived = _duration(row, 'Dual Received Duration');
  final dualGiven = _duration(row, 'Dual Given Duration');
  final evaluator = _duration(row, 'Evaluator Duration');
  final instructorName = row['Instructor Name'] ?? '';

  // multiPilotOperation is a fact about the aircraft's type certificate
  // (AMC1 FCL.050 column 5), not about how many pilots happened to be
  // required on this one flight — PilotCapacity.multiPilotOperation's own
  // dartdoc calls out exactly this distinction. Garmin's own "Multi-Pilot"
  // column conflates the two (it is also set for a single-pilot aircraft
  // flown with a required safety pilot), so it is deliberately not read
  // here; the aircraft record is the more precise source.
  final multiPilotOperation = aircraft.requiresMultiCrew;
  if ((row['Multi-Pilot'] ?? '').toLowerCase() == 'true' &&
      !multiPilotOperation) {
    notes.add(
      "Garmin's own Multi-Pilot flag was set on this row, but the aircraft "
      "record isn't marked as requiring multiple crew — multiPilotOperation "
      'left false. Garmin also sets this flag for a single-pilot aircraft '
      'flown with a required second pilot for other reasons (e.g. a '
      "safety pilot), which AMC1 FCL.050's multi-pilot time column does "
      'not count; verify.',
    );
  }

  if (dualReceived.inMinutes > 0) {
    notes.add(
      'Logged as dual received from Garmin (instructor: '
      '${instructorName.isEmpty ? "not named" : instructorName}) — EASA '
      "SPIC vs. dual, and countersignature state, aren't recoverable from "
      'Garmin\'s export and default to "not SPIC, no countersignature". '
      'Verify against the original record.',
    );
    return PilotCapacity(
      commandAuthority: false,
      soleManipulator: true,
      soleOccupant: false,
      multiPilotOperation: multiPilotOperation,
      additionalCrewRequiredByRule: false,
      actingAsInstructor: false,
      actingAsExaminer: false,
      picusClaimed: false,
      picInterventionNotRequired: false,
      instructor: InstructorPresence(
        capacity: InstructorCapacity.flightInstructor,
        influencedFlight: true,
        name: instructorName.isEmpty ? null : instructorName,
      ),
    );
  }

  if (dualGiven.inMinutes > 0) {
    notes.add(
      'Logged as dual given from Garmin — this pilot is recorded as the '
      "instructor. Whether the student was sole manipulator isn't "
      "recoverable from Garmin's export; verify.",
    );
    return PilotCapacity(
      commandAuthority: true,
      soleManipulator: false,
      soleOccupant: false,
      multiPilotOperation: multiPilotOperation,
      additionalCrewRequiredByRule: false,
      actingAsInstructor: true,
      actingAsExaminer: false,
      picusClaimed: false,
      picInterventionNotRequired: false,
    );
  }

  if (evaluator.inMinutes > 0) {
    notes.add(
      'Logged as evaluator time from Garmin — read as this pilot being '
      "examined (a checkride), not acting as the examiner; Garmin's export "
      "doesn't distinguish the two directions. Correct actingAsExaminer "
      'manually if this pilot was the examiner instead.',
    );
    return PilotCapacity(
      commandAuthority: pic.inMinutes > 0,
      soleManipulator: true,
      soleOccupant: false,
      multiPilotOperation: multiPilotOperation,
      additionalCrewRequiredByRule: false,
      actingAsInstructor: false,
      actingAsExaminer: false,
      picusClaimed: false,
      picInterventionNotRequired: false,
      instructor: InstructorPresence(
        capacity: InstructorCapacity.flightExaminer,
        influencedFlight: false,
        name: instructorName.isEmpty ? null : instructorName,
      ),
    );
  }

  if (sic.inMinutes > 0) {
    notes.add(
      'Logged as SIC from Garmin — recorded as required crew, not holding '
      'command authority. Garmin uses this same figure for a §91.109 '
      "safety-pilot arrangement, which it doesn't distinguish from genuine "
      'multi-crew SIC; verify, and set otherPilotRole to safetyPilot '
      'manually if that applies.',
    );
    return PilotCapacity(
      commandAuthority: false,
      soleManipulator: false,
      soleOccupant: false,
      multiPilotOperation: multiPilotOperation,
      additionalCrewRequiredByRule: true,
      actingAsInstructor: false,
      actingAsExaminer: false,
      picusClaimed: false,
      picInterventionNotRequired: false,
      otherPilotRole: OtherPilotRole.requiredCrew,
    );
  }

  if (pic.inMinutes > 0) {
    return PilotCapacity(
      commandAuthority: true,
      soleManipulator: true,
      soleOccupant: solo.inMinutes > 0,
      multiPilotOperation: multiPilotOperation,
      additionalCrewRequiredByRule: false,
      actingAsInstructor: false,
      actingAsExaminer: false,
      picusClaimed: false,
      picInterventionNotRequired: false,
    );
  }

  notes.add(
    "None of Garmin's PIC/SIC/dual/evaluator duration columns were "
    "populated for this row — pilot capacity couldn't be determined and "
    'defaults to every flag unset. Verify.',
  );
  return PilotCapacity(
    commandAuthority: false,
    soleManipulator: false,
    soleOccupant: false,
    multiPilotOperation: multiPilotOperation,
    additionalCrewRequiredByRule: false,
    actingAsInstructor: false,
    actingAsExaminer: false,
    picusClaimed: false,
    picInterventionNotRequired: false,
  );
}

/// Maps one flight-log [row] to a [Flight] against the [aircraft] already
/// resolved from the aircraft-types export (`null` when the row's
/// `Aircraft Type` has no canonical equivalent, per [mapGarminAircraft]'s
/// own dartdoc: a simulator, or a type with no manufacturer on file).
GarminFlightMapping mapGarminFlight({
  required Map<String, String> row,
  required Aircraft? aircraft,
}) {
  final registration = row['Aircraft ID'] ?? '';
  if (registration.isEmpty) {
    return const GarminFlightMapping.error(
      'Aircraft ID is blank — cannot resolve which aircraft this flight '
      'was flown in.',
    );
  }
  if (aircraft == null) {
    final type = row['Aircraft Type'] ?? '';
    return GarminFlightMapping.error(
      'Aircraft Type "${type.isEmpty ? '(blank)' : type}" is either a '
      'simulator/FTD device (FSTD sessions are not yet supported by this '
      "app) or has no matching row in Garmin's aircraft-types export. Add "
      'it under Aircraft management and re-import, or skip this row.',
    );
  }

  final blockTimes = _blockTimes(row);
  if (blockTimes.error != null) {
    return GarminFlightMapping.error(blockTimes.error!);
  }
  final offBlocks = blockTimes.offBlocks!;
  final onBlocks = blockTimes.onBlocks!;
  final takeoff = _optionalAirTime(row, 'Time Off', offBlocks, onBlocks);
  final landing = _optionalAirTime(row, 'Time On', offBlocks, onBlocks);

  final route = _route(row);
  if (route.length < 2) {
    return const GarminFlightMapping.error(
      'Route is blank — every flight needs at least a departure and '
      'destination.',
    );
  }

  final notes = <String>[];
  final capacity = _classifyCapacity(
    row: row,
    aircraft: aircraft,
    notes: notes,
  );

  final picName = (row['PIC Name'] ?? '').trim();
  final otherPilotName = capacity.otherPilotRole != null && picName.isNotEmpty
      ? picName
      : null;

  final dayTakeoffs = _count(row, 'Day Takeoffs');
  final nightTakeoffs = _count(row, 'Night Takeoffs');
  final dayLandings = _count(row, 'Day Landings');
  final nightLandings = _count(row, 'Night Landings');
  final expectedLandings = route.length - 1;
  // Garmin logs one landings total per day/night with no full-stop vs.
  // touch-and-go split at all (unlike ForeFlight, which at least gives an
  // AllLandings figure to compare against). More landings than the route
  // has legs usually means extra circuits at one aerodrome; the whole
  // total is still counted as full-stop below, since there is nothing to
  // subtract it from.
  if (dayLandings + nightLandings > expectedLandings) {
    notes.add(
      'Garmin logs one landings total per day/night with no full-stop '
      'vs. touch-and-go split — more landings ($dayLandings day, '
      '$nightLandings night) were recorded than the route has legs '
      '($expectedLandings), which usually means extra circuits at one '
      'aerodrome. All of it is counted as full-stop below; split manually '
      'if some were touch-and-go.',
    );
  }

  final crossCountry = _duration(row, 'Cross Country Duration');
  if (crossCountry.inMinutes > 0) {
    notes.add(
      "Garmin's Cross Country Duration measures its own (FAA-style, "
      "distance-based) definition, not EASA's FCL.010 pre-planned-"
      'navigation test — prePlannedNavigation is left false. Set it '
      'manually if this flight qualifies.',
    );
  }

  final approachParse = _parseApproaches(row['Approaches'] ?? '');
  if (approachParse.unparsed != null) {
    notes.add(
      'Approaches ("${approachParse.unparsed}") could not be parsed — '
      'dropped.',
    );
  }

  final actualInstrumentTime = _duration(row, 'Actual Instrument Duration');
  if (actualInstrumentTime.inMinutes > 0) {
    notes.add(
      'ifrFlightPlanFiled defaulted to false — Garmin has no field for '
      'this, unlike actual/simulated instrument time; set manually if an '
      'IFR flight plan was filed.',
    );
  }

  final simulatorDuration = _duration(row, 'Simulator Duration');
  if (simulatorDuration.inMinutes > 0) {
    notes.add(
      'Simulator Duration was set on this row — FSTD time has no home on '
      'a regular Flight in this app (a separate form, per CLAUDE.md); not '
      'recorded. Log the simulator session separately if needed.',
    );
  }

  final unmappedFields = <String, String>{};
  for (final entry in row.entries) {
    if (_mappedColumns.contains(entry.key)) continue;
    if (entry.key.isEmpty || entry.value.isEmpty) continue;
    unmappedFields[entry.key] = entry.value;
  }

  final flight = Flight(
    aircraftRegistration: registration,
    route: route,
    prePlannedNavigation: false,
    offBlocks: offBlocks,
    onBlocks: onBlocks,
    takeoff: takeoff,
    landing: landing,
    capacity: capacity,
    otherPilotName: otherPilotName,
    carryingPassengers: false,
    takeoffs: CircuitCounts(
      dayFullStop: dayTakeoffs,
      nightFullStop: nightTakeoffs,
    ),
    landings: CircuitCounts(
      dayFullStop: dayLandings,
      nightFullStop: nightLandings,
    ),
    ifrFlightPlanFiled: false,
    actualInstrumentTime: actualInstrumentTime,
    simulatedInstrumentTime: _duration(row, 'Simulated Instrument Duration'),
    approaches: approachParse.approaches,
    holdingProceduresCount: _count(row, 'Holding Patterns'),
    trackingPerformed: (row['Track Nav Aid'] ?? '').toLowerCase() == 'true',
    remarks: '',
  );

  return GarminFlightMapping.mapped(
    flight: flight,
    unmappedFields: unmappedFields,
    reviewNotes: notes,
  );
}
