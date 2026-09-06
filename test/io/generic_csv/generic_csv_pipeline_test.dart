import 'dart:io';

import 'package:drift/native.dart';
import 'package:easa_digital_log/data/database.dart';
import 'package:easa_digital_log/data/repositories/aircraft_repository.dart';
import 'package:easa_digital_log/data/repositories/flight_repository_drift.dart';
import 'package:easa_digital_log/io/generic_csv/generic_csv_adapter.dart';
import 'package:easa_digital_log/io/generic_csv/generic_csv_field.dart';
import 'package:easa_digital_log/io/generic_csv/generic_csv_mapping.dart';
import 'package:easa_digital_log/io/import_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';

/// #72's own "same validation and error reporting as the vendor adapters"
/// criterion, demonstrated rather than asserted: [GenericCsvAdapter]
/// produces a plain [ImportParseResult], the exact type #69's/#71's own
/// adapters produce, so #73's `buildImportPreview`/`applyImport` need no
/// special case for it at all.
void main() {
  test('a generic CSV mapping\'s output flows through the same preview and '
      'apply pipeline as a vendor adapter, unchanged', () async {
    final csv = File(
      'test/io/generic_csv/fixtures/sample_logbook.csv',
    ).readAsStringSync();
    const mapping = GenericCsvMapping(
      name: 'Test spreadsheet',
      columnByField: {
        GenericCsvField.date: 'Date',
        GenericCsvField.offBlocksTime: 'Off',
        GenericCsvField.onBlocksTime: 'On',
        GenericCsvField.aircraftRegistration: 'Reg',
        GenericCsvField.aircraftType: 'Type',
        GenericCsvField.departure: 'From',
        GenericCsvField.destination: 'To',
        GenericCsvField.picDuration: 'PIC',
        GenericCsvField.sicDuration: 'SIC',
        GenericCsvField.dualReceivedDuration: 'Dual',
        GenericCsvField.soloDuration: 'Solo',
        GenericCsvField.dayLandings: 'DayLdg',
        GenericCsvField.nightLandings: 'NightLdg',
        GenericCsvField.remarks: 'Notes',
      },
      dateFormat: CsvDateFormat.usMdy,
      durationFormat: CsvDurationFormat.decimalHours,
    );

    final parseResult = const GenericCsvAdapter(
      mapping,
    ).parse({GenericCsvAdapter.csvKey: csv});

    final preview = buildImportPreview(
      parseResult: parseResult,
      existingFlights: const [],
    );
    expect(preview.rows, hasLength(6));
    expect(preview.errors, hasLength(2));
    expect(preview.rows.every((r) => r.duplicate == null), isTrue);

    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final batchId = await applyImport(
      rows: parseResult.rows,
      sourceLabel: 'Generic CSV (${mapping.name})',
      aircraftRepository: AircraftRepository(db),
      flightRepository: DriftFlightRepository(db),
    );

    final storedFlights = await db.select(db.flightsTable).get();
    expect(storedFlights, hasLength(6));
    expect(storedFlights.every((f) => f.importBatchId == batchId), isTrue);
    expect(storedFlights.every((f) => f.committedAt == null), isTrue);
  });
}
