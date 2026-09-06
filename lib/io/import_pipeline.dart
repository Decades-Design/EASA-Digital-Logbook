import '../data/repositories/aircraft_repository.dart';
import '../domain/repository/flight_read_repository.dart';
import '../domain/repository/flight_repository.dart';
import 'canonical_import_row.dart';
import 'duplicate_matcher.dart';
import 'import_adapter.dart';

/// One [CanonicalImportRow] paired with its duplicate verdict (#75), if
/// any. Nothing here writes anything — #73's "preview step": a caller can
/// review every mapped row (and, separately, [ImportPreview.errors] for
/// every row that couldn't be mapped at all) before ever calling
/// [applyImport].
class ImportPreviewRow {
  const ImportPreviewRow({required this.row, this.duplicate});

  final CanonicalImportRow row;
  final DuplicateMatch? duplicate;
}

/// Everything a preview screen (not yet built — #73 scopes this PR to the
/// data/orchestration layer) needs to show: every mappable row with its
/// duplicate verdict, and every row that failed to map at all. Building
/// this touches no database — [existingFlights] is supplied by the caller,
/// already fetched.
class ImportPreview {
  const ImportPreview({required this.rows, required this.errors});

  final List<ImportPreviewRow> rows;
  final List<ImportRowError> errors;
}

/// Builds an [ImportPreview] from [parseResult], checking every mapped row
/// for a duplicate against [existingFlights] (#75) — typically a caller's
/// combined drafts and committed flights, the same pool
/// `duplicate_matcher.dart`'s own dartdoc describes.
ImportPreview buildImportPreview({
  required ImportParseResult parseResult,
  required List<FlightRecord> existingFlights,
}) {
  final matches = findDuplicates(
    incoming: parseResult.rows,
    existingFlights: existingFlights,
  );
  return ImportPreview(
    rows: [
      for (var i = 0; i < parseResult.rows.length; i++)
        ImportPreviewRow(row: parseResult.rows[i], duplicate: matches[i]),
    ],
    errors: parseResult.errors,
  );
}

/// Commits [rows] as one all-or-nothing import batch (#73).
///
/// Resolves each row's [CanonicalImportRow.aircraft] to a stored aircraft
/// id, reusing an existing registration's id
/// ([AircraftRepository.findIdByRegistration]) rather than overwriting it
/// — a pilot may have corrected that aircraft's data by hand since the
/// last import, and blindly re-upserting from a vendor CSV every time
/// would silently clobber that. Only a registration seen for the first
/// time gets a new [AircraftRepository.upsert] row. Each distinct
/// registration among [rows] is resolved once, not once per flight.
///
/// [rows] is exactly what should be imported — a caller has already
/// dropped whatever the pilot chose to skip (a duplicate, or a row they
/// didn't want) before calling this. There is no partial-skip concept
/// inside the transaction itself: skipping happens by not including a row
/// here, the same division of responsibility [buildImportPreview] keeps
/// pure and this function's own transaction keeps atomic.
Future<String> applyImport({
  required List<CanonicalImportRow> rows,
  required String sourceLabel,
  required AircraftRepository aircraftRepository,
  required FlightRepository flightRepository,
}) async {
  final aircraftIdByRegistration = <String, String>{};
  final batchFlights = <ImportBatchFlight>[];

  for (final row in rows) {
    final registration = row.aircraft.registration;
    var aircraftId = aircraftIdByRegistration[registration];
    if (aircraftId == null) {
      aircraftId =
          await aircraftRepository.findIdByRegistration(registration) ??
          await aircraftRepository.upsert(row.aircraft);
      aircraftIdByRegistration[registration] = aircraftId;
    }
    batchFlights.add((flight: row.flight, aircraftId: aircraftId));
  }

  return flightRepository.applyImportBatch(
    sourceLabel: sourceLabel,
    flights: batchFlights,
  );
}
