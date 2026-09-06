import '../canonical_import_row.dart';
import '../import_adapter.dart';
import 'garmin_aircraft_mapper.dart';
import 'garmin_csv_table.dart';
import 'garmin_flight_mapper.dart';

/// Imports Garmin Pilot's logbook export (#71) — two separate CSV files,
/// unlike ForeFlight's single `logbook_template.csv` (#69): an
/// aircraft-*types* export keyed by type name (e.g. `PA28-161`), not by
/// tail number, and a flight-log export naming both the tail number and
/// the type on every row. [parse] joins them per flight row.
///
/// Garmin's own PIC/SIC/dual-time columns are, like ForeFlight's, derived
/// quantities rather than this app's raw facts — see
/// `garmin_flight_mapper.dart` for the reverse-projection judgement calls
/// and why each one appends a review note. Garmin also allows a flight to
/// be logged with only a decimal total duration and no block times at
/// all; per the project owner's own call on #71, such a row is rejected
/// outright rather than given a fabricated off/on-blocks time that never
/// happened — see `garmin_flight_mapper.dart`'s `_blockTimes`.
class GarminAdapter implements ImportAdapter {
  /// Key for the aircraft-types export in [parse]'s `sources`.
  static const aircraftTypesKey = 'aircraftTypes';

  /// Key for the flight-log export in [parse]'s `sources`.
  static const logEntriesKey = 'logEntries';

  @override
  String get displayName => 'Garmin Pilot (aircraft types + logbook CSV)';

  @override
  ImportParseResult parse(Map<String, String> sources) {
    final aircraftTypesCsv = sources[aircraftTypesKey];
    final logEntriesCsv = sources[logEntriesKey];
    if (aircraftTypesCsv == null || logEntriesCsv == null) {
      throw ArgumentError(
        'GarminAdapter.parse requires both "$aircraftTypesKey" and '
        '"$logEntriesKey" entries in sources.',
      );
    }

    final typeRows = parseGarminCsvTable(
      aircraftTypesCsv,
      requiredColumns: const ['Name', 'Simulator'],
      formatDescription: 'a Garmin Pilot aircraft-types export',
    );
    final typesByName = <String, Map<String, String>>{
      for (final row in typeRows)
        if ((row['Name'] ?? '').isNotEmpty) row['Name']!: row,
    };

    final flightRows = parseGarminCsvTable(
      logEntriesCsv,
      requiredColumns: const [
        'Aircraft ID',
        'Aircraft Type',
        'Time Out',
        'Time In',
      ],
      formatDescription: 'a Garmin Pilot logbook export',
    );

    final aircraftByRegistration = <String, GarminAircraftMapping>{};
    final rows = <CanonicalImportRow>[];
    final errors = <ImportRowError>[];

    for (var i = 0; i < flightRows.length; i++) {
      final row = flightRows[i];
      // +1 for 1-based, +1 to move past the header row itself.
      final sourceRowNumber = i + 2;
      final registration = row['Aircraft ID'] ?? '';

      var aircraftMapping = aircraftByRegistration[registration];
      if (aircraftMapping == null && registration.isNotEmpty) {
        final typeRow = typesByName[row['Aircraft Type'] ?? ''];
        final mapped = typeRow == null ? null : mapGarminAircraft(typeRow);
        if (mapped != null) {
          aircraftMapping = GarminAircraftMapping(
            aircraft: mapped.aircraft.copyWith(registration: registration),
            reviewNotes: mapped.reviewNotes,
          );
          aircraftByRegistration[registration] = aircraftMapping;
        }
      }

      final mapped = mapGarminFlight(
        row: row,
        aircraft: aircraftMapping?.aircraft,
      );

      if (mapped.error != null) {
        errors.add(
          ImportRowError(rowNumber: sourceRowNumber, message: mapped.error!),
        );
        continue;
      }

      rows.add(
        CanonicalImportRow(
          sourceRowNumber: sourceRowNumber,
          flight: mapped.flight!,
          aircraft: aircraftMapping!.aircraft,
          unmappedFields: mapped.unmappedFields,
          // Aircraft-level review notes apply once per aircraft, not once
          // per flight — see foreflight_adapter.dart's identical note.
          reviewNotes: mapped.reviewNotes,
        ),
      );
    }

    return ImportParseResult(rows: rows, errors: errors);
  }
}
