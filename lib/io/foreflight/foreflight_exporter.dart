import '../../domain/model/aircraft.dart';
import '../../domain/model/calendar_date.dart';
import '../../domain/projection/projection.dart';
import '../../domain/repository/flight_read_repository.dart';
import 'foreflight_aircraft_exporter.dart';
import 'foreflight_flight_exporter.dart';

/// Column order for ForeFlight's aircraft table — load-bearing (#70).
/// Verified against a real ForeFlight export during #69's development.
const _aircraftHeader = [
  'AircraftID',
  'TypeCode',
  'Year',
  'Make',
  'Model',
  'GearType',
  'EngineType',
  'equipType (FAA)',
  'aircraftClass (FAA)',
  'complexAircraft (FAA)',
  'taa (FAA)',
  'highPerformance (FAA)',
  'pressurized (FAA)',
];

/// Column order for ForeFlight's flights table — load-bearing (#70).
/// Verified against a real ForeFlight export during #69's development.
/// Deliberately omits any `[Type]Label` custom field column: those are
/// per-ForeFlight-account definitions this app has no schema for, not a
/// fixed part of the format.
const _flightHeader = [
  'Date',
  'AircraftID',
  'From',
  'To',
  'Route',
  'TimeOut',
  'TimeOff',
  'TimeOn',
  'TimeIn',
  'OnDuty',
  'OffDuty',
  'TotalTime',
  'PIC',
  'SIC',
  'Night',
  'Solo',
  'CrossCountry',
  'PICUS',
  'MultiPilot',
  'IFR',
  'Examiner',
  'NVG',
  'NVG Ops',
  'Distance',
  'ActualInstrument',
  'SimulatedInstrument',
  'HobbsStart',
  'HobbsEnd',
  'TachStart',
  'TachEnd',
  'Holds',
  'Approach1',
  'Approach2',
  'Approach3',
  'Approach4',
  'Approach5',
  'Approach6',
  'DualGiven',
  'DualReceived',
  'SimulatedFlight',
  'GroundTraining',
  'GroundTrainingGiven',
  'InstructorName',
  'InstructorComments',
  'Person1',
  'Person2',
  'Person3',
  'Person4',
  'Person5',
  'Person6',
  'PilotComments',
  'Flight Review (FAA)',
  'IPC (FAA)',
  'Checkride (FAA)',
  'FAA 61.58 (FAA)',
  'NVG Proficiency (FAA)',
  'Takeoff Day',
  'Takeoff Day Towered',
  'Landing Full-Stop Day',
  'Landing Full-Stop Day Towered',
  'DayTakeoffs',
  'DayLandingsFullStop',
  'NightTakeoffs',
  'NightLandingsFullStop',
  'AllLandings',
];

String _csvField(String value) {
  if (value.contains(',') || value.contains('"') || value.contains('\n')) {
    return '"${value.replaceAll('"', '""')}"';
  }
  return value;
}

String _csvRow(List<String> header, Map<String, String> values) =>
    header.map((column) => _csvField(values[column] ?? '')).join(',');

/// Builds a ForeFlight `logbook_template.csv` export from [flights],
/// deriving jurisdiction-dependent figures via [faaProjection] (#70).
/// Column order and header names exactly match a real ForeFlight export —
/// required for the file to be accepted back into ForeFlight itself, not
/// just this app's own importer.
///
/// [flights] is exactly what the caller wants exported — this function
/// does no date-range filtering of its own. #70's mandatory range
/// selection is the caller's job (via `FlightQuery.from`/`to` against
/// `FlightReadRepository`), the same division of responsibility the import
/// adapters use for resolving aircraft: pure transformation here, I/O and
/// selection above it.
///
/// Aircraft are listed once each, in order of first appearance among
/// [flights], deduplicated by registration.
String exportForeFlightCsv({
  required List<FlightRecord> flights,
  required Projection faaProjection,
}) {
  final buffer = StringBuffer();
  buffer.writeln(
    'ForeFlight Logbook Import,This row is required for importing into '
    'ForeFlight. Do not delete or modify.',
  );
  buffer.writeln();

  final aircraftByRegistration = <String, Aircraft>{
    for (final record in flights) record.aircraft.registration: record.aircraft,
  };

  buffer.writeln('Aircraft Table');
  buffer.writeln(_aircraftHeader.join(','));
  for (final aircraft in aircraftByRegistration.values) {
    buffer.writeln(
      _csvRow(_aircraftHeader, exportForeFlightAircraftRow(aircraft)),
    );
  }
  buffer.writeln();

  // Trailing space matches a real ForeFlight export's own marker exactly
  // — `foreflight_tables.dart`'s import-side parser tolerates either, but
  // this file also needs to satisfy ForeFlight's own importer, not just
  // this app's.
  buffer.writeln('Flights Table ');
  buffer.writeln(_flightHeader.join(','));
  for (final record in flights) {
    final row = exportForeFlightFlightRow(
      flight: record.flight,
      aircraft: record.aircraft,
      faaProjection: faaProjection,
    );
    buffer.writeln(_csvRow(_flightHeader, row));
  }

  return buffer.toString();
}

/// The filename #70 requires: the export range embedded so a pilot (or a
/// future overlap check) can see at a glance what a file covers without
/// opening it — e.g. `logbook_template_2026-01-01_to_2026-06-30.csv`.
String foreFlightExportFilename({
  required CalendarDate from,
  required CalendarDate to,
}) => 'logbook_template_${from}_to_$to.csv';
