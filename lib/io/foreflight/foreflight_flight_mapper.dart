import '../../domain/model/aircraft.dart';
import '../../domain/model/flight.dart';
import '../../domain/model/flight_duration.dart';
import '../../domain/model/instructor_presence.dart';
import '../../domain/model/pilot_capacity.dart';
import '../../domain/model/utc_instant.dart';

/// Either a mapped [CanonicalImportRow]-shaped `(flight, unmappedFields,
/// reviewNotes)` triple, or an [error] naming why the row could not be
/// mapped at all. Kept as a plain result object rather than throwing —
/// #74's "no silent coercion" applies to malformed rows the same way it
/// applies to the adapter's caller, and a thrown exception mid-file would
/// abort every row after it rather than reporting this one row's problem
/// and continuing.
class ForeFlightFlightMapping {
  const ForeFlightFlightMapping.mapped({
    required this.flight,
    this.unmappedFields = const {},
    this.reviewNotes = const [],
  }) : error = null;

  const ForeFlightFlightMapping.error(this.error)
    : flight = null,
      unmappedFields = const {},
      reviewNotes = const [];

  final Flight? flight;
  final String? error;
  final Map<String, String> unmappedFields;
  final List<String> reviewNotes;
}

/// ForeFlight logs `TimeOut`/`TimeIn`/`TimeOff`/`TimeOn` in Zulu by default
/// — the same convention CLAUDE.md rule 3 requires this app to store in.
/// There is no per-row zone marker to confirm that from the file alone;
/// this is a documented assumption, not a fact this adapter can verify.
/// If a pilot's ForeFlight account was ever configured to export local
/// time instead, every imported time would be silently wrong by that
/// offset — worth a one-time check against a known flight before trusting
/// a full import.
UtcInstant? _parseDateTime(String date, String time) {
  if (date.isEmpty || time.isEmpty) return null;
  final dateParts = date.split('-');
  final timeParts = time.split(':');
  if (dateParts.length != 3 || timeParts.length != 2) return null;
  final year = int.tryParse(dateParts[0]);
  final month = int.tryParse(dateParts[1]);
  final day = int.tryParse(dateParts[2]);
  final hour = int.tryParse(timeParts[0]);
  final minute = int.tryParse(timeParts[1]);
  if (year == null ||
      month == null ||
      day == null ||
      hour == null ||
      minute == null) {
    return null;
  }
  return UtcInstant.utc(year, month, day, hour, minute);
}

FlightDuration _duration(Map<String, String> row, String column) {
  final raw = row[column] ?? '';
  if (raw.isEmpty) return FlightDuration.zero;
  try {
    return FlightDuration.parseHoursMinutes(raw);
  } on FormatException {
    return FlightDuration.zero;
  }
}

int _count(Map<String, String> row, String column) =>
    int.tryParse(row[column] ?? '') ?? 0;

/// Splits ForeFlight's `From`/`Route`/`To` columns into [Flight.route].
/// `Route` holds any intermediate stops as whitespace-separated
/// identifiers (irregular spacing observed in real exports, hence
/// splitting on any run of whitespace rather than a single space).
List<String> _route(Map<String, String> row) {
  final from = row['From'] ?? '';
  final to = row['To'] ?? '';
  final intermediate = (row['Route'] ?? '')
      .split(RegExp(r'\s+'))
      .where((s) => s.isNotEmpty);
  return [if (from.isNotEmpty) from, ...intermediate, if (to.isNotEmpty) to];
}

/// ForeFlight gives four counts (`DayTakeoffs`, `NightTakeoffs`,
/// `DayLandingsFullStop`, `NightLandingsFullStop`, `AllLandings`) rather
/// than this app's own four-way full-stop/touch-and-go split by day and
/// night — CLAUDE.md rule 2's own list names that split as one of the
/// facts a vendor import routinely can't reconstruct cleanly.
///
/// Takeoffs map directly — ForeFlight has no touch-and-go concept for a
/// takeoff (a takeoff is a takeoff regardless of what preceded it), so
/// `DayTakeoffs`/`NightTakeoffs` go straight into the full-stop slots with
/// no ambiguity to flag.
///
/// Landings are genuinely ambiguous: `AllLandings` minus the full-stop
/// counts is the touch-and-go count, but ForeFlight does not say how many
/// of those were flown at night. The whole remainder is assigned to the
/// day bucket — the far more common case — and the row is flagged for
/// review whenever that remainder is nonzero, so a pilot with real night
/// touch-and-goes catches the miscount rather than trusting a silent
/// guess.
({CircuitCounts takeoffs, CircuitCounts landings, String? note}) _circuitCounts(
  Map<String, String> row,
) {
  final dayTakeoffs = _count(row, 'DayTakeoffs');
  final nightTakeoffs = _count(row, 'NightTakeoffs');
  final dayFullStop = _count(row, 'DayLandingsFullStop');
  final nightFullStop = _count(row, 'NightLandingsFullStop');
  final allLandings = _count(row, 'AllLandings');

  final touchAndGo = allLandings - (dayFullStop + nightFullStop);
  final dayTouchAndGo = touchAndGo > 0 ? touchAndGo : 0;

  return (
    takeoffs: CircuitCounts(
      dayFullStop: dayTakeoffs,
      nightFullStop: nightTakeoffs,
    ),
    landings: CircuitCounts(
      dayFullStop: dayFullStop,
      nightFullStop: nightFullStop,
      dayTouchAndGo: dayTouchAndGo,
    ),
    note: dayTouchAndGo > 0
        ? '$dayTouchAndGo touch-and-go landing(s) counted from AllLandings '
              "minus the full-stop counts — ForeFlight doesn't say whether "
              'they were flown by day or night; assigned to day, verify.'
        : null,
  );
}

/// Parses one `Approach1`..`Approach6` cell, formatted
/// `count;description;runway;aerodrome;;[CIRCLE]` — e.g.
/// `1;LOC RWY 27;27;LIMG;;` or `1;RNP A;13;LOAV;;CIRCLE`. Returns `null`
/// for a blank cell; the caller adds a review note for a cell that isn't
/// blank but doesn't parse, rather than dropping it silently.
({Approach? approach, String? unparsed}) _parseApproach(String cell) {
  if (cell.trim().isEmpty) return (approach: null, unparsed: null);

  final parts = cell.split(';');
  if (parts.length < 4) return (approach: null, unparsed: cell);

  final count = int.tryParse(parts[0]) ?? 1;
  final description = parts[1].toUpperCase();
  final runway = parts[2];
  final aerodrome = parts[3];
  if (aerodrome.isEmpty) return (approach: null, unparsed: cell);

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
    // "LOC RWY 27" alone (no ILS prefix) is a stand-alone localizer
    // approach — checked last since "ILS" and several others also
    // contain runway text that could coincidentally include "LOC".
    _ when description.contains('LOC') => ApproachType.loc,
    _ => null,
  };
  if (type == null) return (approach: null, unparsed: cell);

  return (
    approach: Approach(
      type: type,
      aerodromeIcao: aerodrome,
      runway: runway,
      count: count,
    ),
    unparsed: null,
  );
}

const _approachColumns = [
  'Approach1',
  'Approach2',
  'Approach3',
  'Approach4',
  'Approach5',
  'Approach6',
];

/// Columns folded into [PilotCapacity] or elsewhere on [Flight] directly,
/// rather than surviving into [ForeFlightFlightMapping.unmappedFields] —
/// listed once here so the "everything else" loop that builds
/// unmappedFields knows what to skip.
const _mappedColumns = {
  'Date', 'AircraftID', 'From', 'To', 'Route',
  'TimeOut', 'TimeOff', 'TimeOn', 'TimeIn',
  'TotalTime', 'PIC', 'SIC', 'Solo', 'CrossCountry', 'PICUS', 'MultiPilot',
  'IFR', 'Examiner', 'ActualInstrument', 'SimulatedInstrument',
  'Holds', 'DualGiven', 'DualReceived', 'InstructorName',
  'DayTakeoffs', 'DayLandingsFullStop', 'NightTakeoffs',
  'NightLandingsFullStop', 'AllLandings',
  // Legacy duplicates of DayTakeoffs/DayLandingsFullStop with no night
  // counterpart — same values observed in every real row that populates
  // both, so treated as redundant rather than unmapped.
  'Takeoff Day', 'Takeoff Day Towered',
  'Landing Full-Stop Day', 'Landing Full-Stop Day Towered',
  'OnDuty', 'OffDuty', 'Night',
  ..._approachColumns,
};

/// This pilot's [PilotCapacity] reverse-projected from ForeFlight's own
/// derived hour columns — #69's central, "inherently lossy" problem.
/// ForeFlight stores PIC/SIC/dual hours, not the raw command-authority/
/// sole-manipulator/instructor-presence facts CLAUDE.md rule 2 requires;
/// reconstructing one from the other is a best-effort classification of
/// the common cases, never a guess dressed up as certainty — every branch
/// that made a judgement call appends to [notes] rather than staying
/// silent about it.
PilotCapacity _classifyCapacity(Map<String, String> row, List<String> notes) {
  final pic = _duration(row, 'PIC');
  final sic = _duration(row, 'SIC');
  final solo = _duration(row, 'Solo');
  final picus = _duration(row, 'PICUS');
  final multiPilot = _duration(row, 'MultiPilot');
  final dualGiven = _duration(row, 'DualGiven');
  final dualReceived = _duration(row, 'DualReceived');
  final instructorName = row['InstructorName'] ?? '';

  if (dualReceived.inMinutes > 0) {
    notes.add(
      'Logged as dual received from ForeFlight (instructor: '
      '${instructorName.isEmpty ? "not named" : instructorName}) — EASA '
      "SPIC vs. dual, and countersignature state, aren't recoverable from "
      'ForeFlight\'s export and default to "not SPIC, no countersignature". '
      'Verify against the paper/original record.',
    );
    return PilotCapacity(
      commandAuthority: false,
      soleManipulator: true,
      soleOccupant: false,
      multiPilotOperation: multiPilot.inMinutes > 0,
      additionalCrewRequiredByRule: false,
      actingAsInstructor: false,
      actingAsExaminer: false,
      picusClaimed: picus.inMinutes > 0,
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
      'Logged as dual given from ForeFlight — this pilot is recorded as '
      'the instructor. Whether the student was sole manipulator '
      "isn't recoverable from ForeFlight's export; verify.",
    );
    return PilotCapacity(
      commandAuthority: true,
      soleManipulator: false,
      soleOccupant: false,
      multiPilotOperation: multiPilot.inMinutes > 0,
      additionalCrewRequiredByRule: false,
      actingAsInstructor: true,
      actingAsExaminer: false,
      picusClaimed: false,
      picInterventionNotRequired: false,
    );
  }

  if (picus.inMinutes > 0) {
    notes.add(
      'Logged as PICUS from ForeFlight — the countersignature and '
      '"PIC intervention not required" state that make it creditable '
      "under FCL.010 aren't recoverable from ForeFlight's export and "
      'default to unset. Verify and countersign.',
    );
    return PilotCapacity(
      commandAuthority: false,
      soleManipulator: true,
      soleOccupant: false,
      multiPilotOperation: multiPilot.inMinutes > 0,
      additionalCrewRequiredByRule: false,
      actingAsInstructor: false,
      actingAsExaminer: false,
      picusClaimed: true,
      picInterventionNotRequired: false,
      instructor: instructorName.isEmpty
          ? null
          : InstructorPresence(
              capacity: InstructorCapacity.flightInstructor,
              influencedFlight: false,
              name: instructorName,
            ),
    );
  }

  if (sic.inMinutes > 0) {
    notes.add(
      'Logged as SIC from ForeFlight — recorded as a multi-pilot '
      'operation with this pilot not holding command authority; verify.',
    );
    return PilotCapacity(
      commandAuthority: false,
      soleManipulator: false,
      soleOccupant: false,
      multiPilotOperation: true,
      additionalCrewRequiredByRule: true,
      actingAsInstructor: false,
      actingAsExaminer: false,
      picusClaimed: false,
      picInterventionNotRequired: false,
    );
  }

  if (pic.inMinutes > 0) {
    return PilotCapacity(
      commandAuthority: true,
      soleManipulator: true,
      soleOccupant: solo.inMinutes > 0,
      multiPilotOperation: multiPilot.inMinutes > 0,
      additionalCrewRequiredByRule: false,
      actingAsInstructor: false,
      actingAsExaminer: false,
      picusClaimed: false,
      picInterventionNotRequired: false,
    );
  }

  notes.add(
    'None of ForeFlight\'s PIC/SIC/PICUS/dual columns were populated for '
    "this row — pilot capacity couldn't be determined and defaults to "
    'every flag unset. Verify.',
  );
  return const PilotCapacity(
    commandAuthority: false,
    soleManipulator: false,
    soleOccupant: false,
    multiPilotOperation: false,
    additionalCrewRequiredByRule: false,
    actingAsInstructor: false,
    actingAsExaminer: false,
    picusClaimed: false,
    picInterventionNotRequired: false,
  );
}

/// Maps one flights-table [row] to a [Flight] against the aircraft already
/// resolved from the aircraft table ([aircraft] — `null` when the row's
/// `AircraftID` has no canonical equivalent, per
/// [mapForeFlightAircraft]'s own dartdoc: an FTD session, or an aircraft
/// with no make/model on file).
ForeFlightFlightMapping mapForeFlightFlight({
  required Map<String, String> row,
  required Aircraft? aircraft,
}) {
  final registration = row['AircraftID'] ?? '';
  if (registration.isEmpty) {
    return const ForeFlightFlightMapping.error(
      'AircraftID is blank — cannot resolve which aircraft this flight was '
      'flown in.',
    );
  }
  if (aircraft == null) {
    return ForeFlightFlightMapping.error(
      'AircraftID "$registration" is either a flight training device '
      '(FSTD sessions are not yet supported by this app — CLAUDE.md '
      'defers them to a separate form) or has no make/model on file in '
      "ForeFlight's own aircraft table. Add it under Aircraft management "
      'and re-import, or skip this row.',
    );
  }

  final offBlocks = _parseDateTime(row['Date'] ?? '', row['TimeOut'] ?? '');
  var onBlocks = _parseDateTime(row['Date'] ?? '', row['TimeIn'] ?? '');
  if (offBlocks == null || onBlocks == null) {
    return ForeFlightFlightMapping.error(
      'Date "${row['Date']}", TimeOut "${row['TimeOut']}" or TimeIn '
      '"${row['TimeIn']}" is missing or unparseable — every flight needs '
      'both block times.',
    );
  }
  // A flight landing after midnight Zulu has an earlier time-of-day than
  // it departed with; ForeFlight's Date column names the departure date
  // only, so the day rolls over here rather than misreading the block
  // time as negative.
  if (onBlocks < offBlocks) onBlocks = onBlocks.add(const Duration(days: 1));

  final takeoff = _parseDateTime(row['Date'] ?? '', row['TimeOff'] ?? '');
  var landing = _parseDateTime(row['Date'] ?? '', row['TimeOn'] ?? '');
  if (takeoff != null && landing != null && landing < takeoff) {
    landing = landing.add(const Duration(days: 1));
  }

  final route = _route(row);
  if (route.length < 2) {
    return const ForeFlightFlightMapping.error(
      'From and To are both blank — every flight needs at least a '
      'departure and destination.',
    );
  }

  final notes = <String>[];
  final circuits = _circuitCounts(row);
  if (circuits.note != null) notes.add(circuits.note!);

  // Scoped to ForeFlight actually having logged cross-country hours, not
  // merely "the route touches two different aerodromes" — the ordinary
  // case for most flights, and flagging every one of them would drown out
  // the genuinely useful notes in a full import.
  final crossCountry = _duration(row, 'CrossCountry');
  if (crossCountry.inMinutes > 0) {
    notes.add(
      "ForeFlight's CrossCountry column measures its own (FAA-style, "
      "distance-based) definition, not EASA's FCL.010 pre-planned-"
      'navigation test — prePlannedNavigation is left false. Set it '
      'manually if this flight qualifies.',
    );
  }

  final ifrHours = _duration(row, 'IFR');
  final ifrFlightPlanFiled = ifrHours.inMinutes > 0;
  if (ifrFlightPlanFiled) {
    notes.add(
      'ifrFlightPlanFiled inferred from ForeFlight logging IFR time on '
      'this flight — verify.',
    );
  }

  final approaches = <Approach>[];
  for (final column in _approachColumns) {
    final parsed = _parseApproach(row[column] ?? '');
    if (parsed.approach != null) approaches.add(parsed.approach!);
    if (parsed.unparsed != null) {
      notes.add(
        '$column ("${parsed.unparsed}") could not be parsed — dropped.',
      );
    }
  }

  final unmappedFields = <String, String>{};
  for (final entry in row.entries) {
    if (_mappedColumns.contains(entry.key)) continue;
    if (entry.key.isEmpty || entry.value.isEmpty) continue;
    unmappedFields[entry.key] = entry.value;
  }

  // The one custom field this adapter gives specific meaning to, rather
  // than leaving as an opaque preserved string: ForeFlight's own
  // `[Text]Safety pilot` field records the *other* pilot's name on a
  // simulated-instrument flight — `Flight.otherPilotName` and
  // `PilotCapacity.otherPilotRole` exist for exactly this
  // (`§61.51(b)(1)(v)`). Any other `[Type]Label` custom field falls
  // through to the generic unmappedFields loop above, preserved verbatim
  // rather than interpreted.
  String? otherPilotName;
  var capacity = _classifyCapacity(row, notes);
  for (final key in row.keys.where((k) => k.startsWith('['))) {
    final match = RegExp(r'^\[(\w+)\](.+)$').firstMatch(key);
    if (match == null) continue;
    final label = match.group(2)!.trim();
    final value = row[key] ?? '';
    if (label.toLowerCase() == 'safety pilot' && value.trim().isNotEmpty) {
      otherPilotName = value.trim();
      capacity = capacity.copyWith(otherPilotRole: OtherPilotRole.safetyPilot);
      unmappedFields.remove(key);
    }
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
    takeoffs: circuits.takeoffs,
    landings: circuits.landings,
    ifrFlightPlanFiled: ifrFlightPlanFiled,
    actualInstrumentTime: _duration(row, 'ActualInstrument'),
    simulatedInstrumentTime: _duration(row, 'SimulatedInstrument'),
    approaches: approaches,
    holdingProceduresCount: _count(row, 'Holds'),
    trackingPerformed: false,
    remarks: '',
  );

  return ForeFlightFlightMapping.mapped(
    flight: flight,
    unmappedFields: unmappedFields,
    reviewNotes: notes,
  );
}
