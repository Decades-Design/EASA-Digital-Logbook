import '../../domain/model/aircraft.dart';
import '../../domain/model/flight.dart';
import '../../domain/model/flight_duration.dart';
import '../../domain/model/flight_times.dart';
import '../../domain/model/instructor_presence.dart';
import '../../domain/model/pilot_capacity.dart';
import '../../domain/model/utc_instant.dart';
import '../../domain/projection/projection.dart';
import '../../domain/projection/projection_result.dart';

String _twoDigits(int value) => value.toString().padLeft(2, '0');

String _formatDate(UtcInstant instant) {
  final utc = instant.asUtcDateTime;
  return '${utc.year.toString().padLeft(4, '0')}-'
      '${_twoDigits(utc.month)}-${_twoDigits(utc.day)}';
}

String _formatTime(UtcInstant instant) {
  final utc = instant.asUtcDateTime;
  return '${_twoDigits(utc.hour)}:${_twoDigits(utc.minute)}';
}

String _formatDuration(FlightDuration duration) =>
    duration.inMinutes == 0 ? '0:00' : duration.toHoursMinutes();

FlightDuration _quantity(ProjectionResult result, String name) =>
    result[name]?.value ?? FlightDuration.zero;

/// Reverse of `foreflight_flight_mapper.dart`'s approach-type keyword
/// classification. [ApproachType.backCourse] has no import-side keyword at
/// all (its own switch never checks for one) — `LOC BC` is written back as
/// the closest honest label, but re-importing it will classify it as a
/// plain [ApproachType.loc], the same known, one-way gap the import side
/// already documents for values it cannot recognise.
String _approachTypeLabel(ApproachType type) => switch (type) {
  ApproachType.ils => 'ILS',
  ApproachType.rnav => 'RNAV',
  ApproachType.gps => 'GPS',
  ApproachType.vor => 'VOR',
  ApproachType.loc => 'LOC',
  ApproachType.ndb => 'NDB',
  ApproachType.backCourse => 'LOC BC',
  ApproachType.lda => 'LDA',
  ApproachType.sdf => 'SDF',
  ApproachType.tacan => 'TACAN',
  ApproachType.par => 'PAR',
  ApproachType.asr => 'ASR',
  ApproachType.mls => 'MLS',
};

/// Formats one [Approach] as ForeFlight's `count;description;runway;
/// aerodrome;;[CIRCLE]` cell — the reverse of
/// `foreflight_flight_mapper.dart`'s `_parseApproach`. Never emits the
/// trailing `CIRCLE` marker: this app has no "circling approach" fact to
/// read it back from.
String _formatApproach(Approach approach) =>
    '${approach.count};${_approachTypeLabel(approach.type)} RWY '
    '${approach.runway};${approach.runway};${approach.aerodromeIcao};;';

const _approachColumns = [
  'Approach1',
  'Approach2',
  'Approach3',
  'Approach4',
  'Approach5',
  'Approach6',
];

/// Maps one [flight] flown in [aircraft] to a row of ForeFlight's flights
/// table columns, computing every jurisdiction-dependent figure (PIC, SIC,
/// solo, night, cross-country, actual/simulated instrument, dual received)
/// via [faaProjection] — #70's own instruction, since ForeFlight's schema
/// is FAA-shaped and has no EASA equivalents for most of these.
///
/// Everything else here is a raw [PilotCapacity]/[Flight] fact read
/// directly, not projected — `DualGiven`, `Examiner`, `MultiPilot`, `PICUS`
/// and `IFR` all have a single, jurisdiction-independent meaning already
/// (whether this pilot instructed, was examined, flew a multi-pilot
/// operation, claimed PICUS, or filed an IFR plan), so there is no
/// projection to run for them — the whole block time is attributed to
/// whichever of these flags is set, the same simplifying assumption the
/// import side made in reverse (`foreflight_flight_mapper.dart`'s own
/// dartdoc on `_classifyCapacity` and `ifrFlightPlanFiled` inference).
///
/// Columns with nothing to read this app's model for at all (`OnDuty`,
/// `HobbsStart`/`End`, `TachStart`/`End`, `NVG`, `Distance`,
/// `GroundTraining`, `Person1`-`6`, the `(FAA)` alternative-compliance
/// columns, `Takeoff Day`/`Landing Full-Stop Day` and their towered
/// variants) are always left blank — never fabricated.
Map<String, String> exportForeFlightFlightRow({
  required Flight flight,
  required Aircraft aircraft,
  required Projection faaProjection,
}) {
  final capacity = flight.capacity;
  final blockTime = flight.blockTime;
  final result = faaProjection.project(flight, aircraft);

  final route = flight.route;
  final intermediateStops = route.length > 2
      ? route.sublist(1, route.length - 1).join(' ')
      : '';

  final dayTakeoffs =
      flight.takeoffs.dayFullStop + flight.takeoffs.dayTouchAndGo;
  final nightTakeoffs =
      flight.takeoffs.nightFullStop + flight.takeoffs.nightTouchAndGo;
  final allLandings =
      flight.landings.dayFullStop +
      flight.landings.dayTouchAndGo +
      flight.landings.nightFullStop +
      flight.landings.nightTouchAndGo;

  final instructor = capacity.instructor;
  final examinerPresent =
      instructor?.capacity == InstructorCapacity.flightExaminer;

  final row = <String, String>{
    'Date': _formatDate(flight.offBlocks),
    'AircraftID': flight.aircraftRegistration,
    'From': route.isNotEmpty ? route.first : '',
    'To': route.length > 1 ? route.last : '',
    'Route': intermediateStops,
    'TimeOut': _formatTime(flight.offBlocks),
    'TimeOff': flight.takeoff != null ? _formatTime(flight.takeoff!) : '',
    'TimeOn': flight.landing != null ? _formatTime(flight.landing!) : '',
    'TimeIn': _formatTime(flight.onBlocks),
    'OnDuty': '',
    'OffDuty': '',
    'TotalTime': _formatDuration(blockTime),
    'PIC': _formatDuration(_quantity(result, 'loggedPic')),
    'SIC': _formatDuration(_quantity(result, 'sic')),
    'Night': _formatDuration(_quantity(result, 'nightFlightTime')),
    'Solo': _formatDuration(_quantity(result, 'solo')),
    'CrossCountry': _formatDuration(_quantity(result, 'crossCountry')),
    'PICUS': _formatDuration(
      capacity.picusClaimed ? blockTime : FlightDuration.zero,
    ),
    'MultiPilot': _formatDuration(
      capacity.multiPilotOperation ? blockTime : FlightDuration.zero,
    ),
    'IFR': _formatDuration(
      flight.ifrFlightPlanFiled ? blockTime : FlightDuration.zero,
    ),
    'Examiner': _formatDuration(
      examinerPresent ? blockTime : FlightDuration.zero,
    ),
    'NVG': '',
    'NVG Ops': '',
    'Distance': '',
    'ActualInstrument': _formatDuration(_quantity(result, 'actualInstrument')),
    'SimulatedInstrument': _formatDuration(
      _quantity(result, 'simulatedInstrument'),
    ),
    'HobbsStart': '',
    'HobbsEnd': '',
    'TachStart': '',
    'TachEnd': '',
    'Holds': flight.holdingProceduresCount.toString(),
    for (var i = 0; i < _approachColumns.length; i++)
      _approachColumns[i]: i < flight.approaches.length
          ? _formatApproach(flight.approaches[i])
          : '',
    'DualGiven': _formatDuration(
      capacity.actingAsInstructor ? blockTime : FlightDuration.zero,
    ),
    'DualReceived': _formatDuration(_quantity(result, 'dualReceived')),
    'SimulatedFlight': '',
    'GroundTraining': '',
    'GroundTrainingGiven': '',
    'InstructorName': instructor?.name ?? '',
    'InstructorComments': '',
    'Person1': '',
    'Person2': '',
    'Person3': '',
    'Person4': '',
    'Person5': '',
    'Person6': '',
    'PilotComments': flight.remarks,
    'Flight Review (FAA)': '',
    'IPC (FAA)': '',
    'Checkride (FAA)': '',
    'FAA 61.58 (FAA)': '',
    'NVG Proficiency (FAA)': '',
    'Takeoff Day': '',
    'Takeoff Day Towered': '',
    'Landing Full-Stop Day': '',
    'Landing Full-Stop Day Towered': '',
    'DayTakeoffs': dayTakeoffs.toString(),
    'DayLandingsFullStop': flight.landings.dayFullStop.toString(),
    'NightTakeoffs': nightTakeoffs.toString(),
    'NightLandingsFullStop': flight.landings.nightFullStop.toString(),
    'AllLandings': allLandings.toString(),
  };

  return row;
}
