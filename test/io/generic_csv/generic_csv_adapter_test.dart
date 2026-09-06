import 'dart:io';

import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:easa_digital_log/io/generic_csv/generic_csv_adapter.dart';
import 'package:easa_digital_log/io/generic_csv/generic_csv_field.dart';
import 'package:easa_digital_log/io/generic_csv/generic_csv_mapping.dart';
import 'package:easa_digital_log/io/import_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exercises [GenericCsvAdapter] against a hand-kept-spreadsheet-shaped
/// fixture: `MM/DD/YYYY` dates, decimal-hours durations, an unmapped
/// "Fuel" column, a blank registration, an unparseable date, and a
/// midnight-Zulu rollover — the same kind of coverage #69's/#71's own
/// adapter tests give a fixed vendor schema, applied here to a
/// user-defined mapping instead.
void main() {
  late String csv;
  late GenericCsvMapping mapping;

  setUpAll(() {
    csv = File(
      'test/io/generic_csv/fixtures/sample_logbook.csv',
    ).readAsStringSync();
    mapping = const GenericCsvMapping(
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
  });

  ImportParseResult parse() =>
      GenericCsvAdapter(mapping).parse({GenericCsvAdapter.csvKey: csv});

  test('maps every clean row and reports every unmappable one', () {
    final result = parse();

    expect(result.rows, hasLength(6));
    expect(result.errors, hasLength(2));
    expect(result.hasErrors, isTrue);
  });

  test('a plain solo PIC flight maps cleanly, aircraft flagged for review', () {
    final result = parse();
    final row = result.rows.firstWhere((r) => r.sourceRowNumber == 2);

    expect(row.flight.route, ['KABC', 'KDEF']);
    expect(row.flight.capacity.commandAuthority, isTrue);
    expect(row.flight.capacity.soleManipulator, isTrue);
    expect(row.flight.capacity.soleOccupant, isTrue);
    expect(row.aircraft.registration, 'N100AB');
    expect(row.aircraft.model, 'C172');
    expect(row.reviewNotes, contains(contains('details defaulted')));
  });

  test('dual received is mapped with commandAuthority false and a review '
      'note about the SPIC/dual gap', () {
    final result = parse();
    final row = result.rows.firstWhere((r) => r.sourceRowNumber == 3);

    expect(row.flight.capacity.commandAuthority, isFalse);
    expect(row.flight.capacity.soleManipulator, isTrue);
    expect(row.reviewNotes, contains(contains('SPIC vs. dual')));
  });

  test('SIC is mapped as required crew, not holding command authority', () {
    final result = parse();
    final row = result.rows.firstWhere((r) => r.sourceRowNumber == 4);

    expect(row.flight.capacity.commandAuthority, isFalse);
    expect(row.flight.capacity.additionalCrewRequiredByRule, isTrue);
    expect(row.reviewNotes, contains(contains('required crew')));
  });

  test('a blank mapped registration becomes an error, never a guess', () {
    final result = parse();
    final error = result.errors.firstWhere((e) => e.rowNumber == 5);

    expect(error.message, contains('aircraft registration'));
  });

  test('an unparseable date becomes an error for that row only, not the '
      'whole file', () {
    final result = parse();
    final error = result.errors.firstWhere((e) => e.rowNumber == 6);

    expect(error.message, contains('unparseable'));
    // The rows before and after the bad one still mapped.
    expect(result.rows.any((r) => r.sourceRowNumber == 4), isTrue);
    expect(result.rows.any((r) => r.sourceRowNumber == 7), isTrue);
  });

  test('a mapped Notes column becomes remarks, and an unmapped Fuel column '
      'is preserved rather than dropped', () {
    final result = parse();
    final row = result.rows.firstWhere((r) => r.sourceRowNumber == 7);

    expect(row.flight.remarks, 'Great flight');
    expect(row.unmappedFields['Fuel'], '12.0');
  });

  test('a flight crossing midnight Zulu rolls the on-blocks date forward '
      'rather than reading as a negative block time', () {
    final result = parse();
    final row = result.rows.firstWhere((r) => r.sourceRowNumber == 8);

    expect(row.flight.offBlocks.toIso8601String(), '2026-01-07T23:50:00.000Z');
    expect(row.flight.onBlocks.toIso8601String(), '2026-01-08T00:20:00.000Z');
  });

  test('a row with no PIC/SIC/dual populated defaults to every capacity '
      'flag unset, flagged for review', () {
    final result = parse();
    final row = result.rows.firstWhere((r) => r.sourceRowNumber == 9);

    expect(
      row.flight.capacity,
      const PilotCapacity(
        commandAuthority: false,
        soleManipulator: false,
        soleOccupant: false,
        multiPilotOperation: false,
        additionalCrewRequiredByRule: false,
        actingAsInstructor: false,
        actingAsExaminer: false,
        picusClaimed: false,
        picInterventionNotRequired: false,
      ),
    );
    expect(row.reviewNotes, contains(contains("couldn't be determined")));
  });

  test('throws FormatException when the mapping names a column this file '
      "doesn't have", () {
    final badMapping = GenericCsvMapping(
      name: 'Broken mapping',
      columnByField: {
        ...mapping.columnByField,
        GenericCsvField.date: 'NoSuchColumn',
      },
      dateFormat: mapping.dateFormat,
      durationFormat: mapping.durationFormat,
    );

    expect(
      () =>
          GenericCsvAdapter(badMapping).parse({GenericCsvAdapter.csvKey: csv}),
      throwsFormatException,
    );
  });

  test('throws FormatException when a required field is not mapped at all', () {
    final incompleteMapping = GenericCsvMapping(
      name: 'Incomplete mapping',
      columnByField: Map.of(mapping.columnByField)
        ..remove(GenericCsvField.destination),
      dateFormat: mapping.dateFormat,
      durationFormat: mapping.durationFormat,
    );

    expect(
      () => GenericCsvAdapter(
        incompleteMapping,
      ).parse({GenericCsvAdapter.csvKey: csv}),
      throwsFormatException,
    );
  });
}
