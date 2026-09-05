import '../canonical_import_row.dart';
import '../import_adapter.dart';
import 'foreflight_aircraft_mapper.dart';
import 'foreflight_flight_mapper.dart';
import 'foreflight_tables.dart';

/// Imports ForeFlight's `logbook_template.csv` export (#69) — a single CSV
/// containing two embedded tables (Aircraft, then Flights) plus typed
/// custom fields in the form `[Type]FieldName`.
///
/// [parse] throws [FormatException] if [source] doesn't have that basic
/// shape at all (no "Aircraft Table"/"Flights Table" markers) — a whole-file
/// problem, not a per-row one, so it isn't folded into
/// [ImportParseResult.errors] the way a malformed individual row is.
///
/// ForeFlight's own PIC/SIC/dual-time columns are *derived* quantities, not
/// this app's raw facts (CLAUDE.md rule 1) — reconstructing
/// [PilotCapacity] from them is an inherently lossy reverse projection.
/// See `foreflight_flight_mapper.dart`'s own dartdoc for exactly which
/// judgement calls that makes and why every one of them appends a
/// [CanonicalImportRow.reviewNotes] entry rather than staying silent.
class ForeFlightAdapter implements ImportAdapter {
  @override
  String get displayName => 'ForeFlight (logbook_template.csv)';

  @override
  ImportParseResult parse(String source) {
    final tables = parseForeFlightTables(source);

    final aircraftByRegistration = <String, ForeFlightAircraftMapping>{};
    for (final row in tables.aircraftRows) {
      final registration = row['AircraftID'] ?? '';
      if (registration.isEmpty) continue;
      final mapping = mapForeFlightAircraft(row);
      if (mapping != null) aircraftByRegistration[registration] = mapping;
    }

    final rows = <CanonicalImportRow>[];
    final errors = <ImportRowError>[];

    for (var i = 0; i < tables.flightRows.length; i++) {
      final row = tables.flightRows[i];
      final sourceRowNumber = tables.flightDataStartLine + i;
      final aircraftMapping = aircraftByRegistration[row['AircraftID'] ?? ''];

      final mapped = mapForeFlightFlight(
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
          // Aircraft-level review notes (e.g. an engine count that had to
          // be defaulted) apply once per aircraft, not once per flight —
          // repeating them on every one of that aircraft's rows would
          // drown out the flight-specific ones. They're available via
          // `mapForeFlightAircraft` directly for a caller that wants an
          // aircraft-level report instead.
          reviewNotes: mapped.reviewNotes,
        ),
      );
    }

    return ImportParseResult(rows: rows, errors: errors);
  }
}
