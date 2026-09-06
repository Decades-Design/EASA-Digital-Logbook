import 'dart:io';

import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/instructor_presence.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:easa_digital_log/io/garmin/garmin_adapter.dart';
import 'package:easa_digital_log/io/import_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exercises [GarminAdapter] against a pair of anonymised fixtures built to
/// mirror the real structural shape of a Garmin Pilot export (an
/// aircraft-types file keyed by type name, joined against a separate
/// flight-log file; decimal-only and edit-artifact rows that must be
/// rejected rather than given a fabricated block time; a safety-pilot-style
/// SIC arrangement; an evaluator flight; Garmin's quoted approach format)
/// without carrying anyone's real name or flight history — see the
/// fixture files' own header for provenance.
void main() {
  late String aircraftTypesCsv;
  late String logEntriesCsv;

  setUpAll(() {
    aircraftTypesCsv = File(
      'test/io/garmin/fixtures/aircraft_types_sample.csv',
    ).readAsStringSync();
    logEntriesCsv = File(
      'test/io/garmin/fixtures/logbook_entries_sample.csv',
    ).readAsStringSync();
  });

  ImportParseResult parse({String? aircraftTypes, String? logEntries}) =>
      GarminAdapter().parse({
        GarminAdapter.aircraftTypesKey: aircraftTypes ?? aircraftTypesCsv,
        GarminAdapter.logEntriesKey: logEntries ?? logEntriesCsv,
      });

  test('maps every clean row and reports every unmappable one', () {
    final result = parse();

    expect(result.rows, hasLength(7));
    expect(result.errors, hasLength(4));
    expect(result.hasErrors, isTrue);
  });

  test('a plain solo PIC flight maps cleanly, with its approach parsed', () {
    final result = parse();
    final row = result.rows.firstWhere((r) => r.sourceRowNumber == 2);

    expect(row.flight.route, ['LIQB', 'LIRZ']);
    expect(row.flight.capacity.commandAuthority, isTrue);
    expect(row.flight.capacity.soleManipulator, isTrue);
    expect(row.flight.capacity.soleOccupant, isTrue);
    expect(row.flight.approaches, hasLength(1));
    expect(row.flight.approaches.single.type, ApproachType.ils);
    expect(row.flight.approaches.single.aerodromeIcao, 'LIRZ');
    expect(row.aircraft.registration, 'N100AB');
    expect(row.reviewNotes, isEmpty);
    expect(row.unmappedFields['Remarks'], 'Great VFR day');
  });

  test('dual received is mapped with commandAuthority false and a review '
      'note about the SPIC/dual gap', () {
    final result = parse();
    final row = result.rows.firstWhere((r) => r.sourceRowNumber == 3);

    expect(row.flight.capacity.commandAuthority, isFalse);
    expect(row.flight.capacity.instructor?.influencedFlight, isTrue);
    expect(row.flight.capacity.instructor?.name, 'Jane Instructor');
    expect(row.reviewNotes, contains(contains('SPIC vs. dual')));
  });

  test('an SIC / safety-pilot-style arrangement records the other pilot\'s '
      'name and flags the Multi-Pilot flag override', () {
    final result = parse();
    final row = result.rows.firstWhere((r) => r.sourceRowNumber == 4);

    expect(row.flight.capacity.commandAuthority, isFalse);
    expect(row.flight.capacity.additionalCrewRequiredByRule, isTrue);
    expect(row.flight.capacity.multiPilotOperation, isFalse);
    expect(row.flight.capacity.otherPilotRole, OtherPilotRole.requiredCrew);
    expect(row.flight.otherPilotName, 'Sam Otherpilot');
    expect(row.reviewNotes, contains(contains('safety-pilot')));
    expect(row.reviewNotes, contains(contains("Multi-Pilot flag was set")));
  });

  test('evaluator time is read as this pilot being examined, not acting as '
      'the examiner', () {
    final result = parse();
    final row = result.rows.firstWhere((r) => r.sourceRowNumber == 5);

    expect(row.flight.capacity.commandAuthority, isTrue);
    expect(row.flight.capacity.actingAsExaminer, isFalse);
    expect(
      row.flight.capacity.instructor?.capacity,
      InstructorCapacity.flightExaminer,
    );
    expect(row.flight.capacity.instructor?.name, 'Pat Examiner');
    expect(row.reviewNotes, contains(contains('being examined')));
  });

  test('more landings than the route has legs is flagged as likely circuits, '
      'all counted as full-stop', () {
    final result = parse();
    final row = result.rows.firstWhere((r) => r.sourceRowNumber == 6);

    expect(row.flight.landings.dayFullStop, 3);
    expect(row.flight.landings.dayTouchAndGo, 0);
    expect(
      row.reviewNotes,
      contains(contains('no full-stop vs. touch-and-go split')),
    );
  });

  test('an Aircraft Type with no matching aircraft-types row becomes an error, '
      'never a guess', () {
    final result = parse();
    final error = result.errors.firstWhere((e) => e.rowNumber == 7);

    expect(error.message, contains('GHOSTTYPE'));
  });

  test('an Aircraft Type that is a simulator becomes an error, never '
      'imported as a regular aircraft flight', () {
    final result = parse();
    final error = result.errors.firstWhere((e) => e.rowNumber == 8);

    expect(error.message, contains('simulator/FTD device'));
  });

  test('a row with only a decimal Total Duration and no Time Out/Time In '
      'becomes an error rather than a fabricated block time', () {
    final result = parse();
    final error = result.errors.firstWhere((e) => e.rowNumber == 9);

    expect(error.message, contains('duration-only'));
  });

  test('Time Out/Time In stamped with an edit-session date far from the '
      "flight's own Date becomes an error rather than a wrong block time", () {
    final result = parse();
    final error = result.errors.firstWhere((e) => e.rowNumber == 10);

    expect(error.message, contains('edit-session'));
  });

  test('a flight crossing midnight Zulu rolls the on-blocks date forward '
      'rather than reading as a negative block time', () {
    final result = parse();
    final row = result.rows.firstWhere((r) => r.sourceRowNumber == 11);

    expect(row.flight.offBlocks.toIso8601String(), '2026-01-09T23:50:00.000Z');
    expect(row.flight.onBlocks.toIso8601String(), '2026-01-10T00:20:00.000Z');
    expect(row.flight.onBlocks.difference(row.flight.offBlocks).inMinutes, 30);
    expect(row.flight.landings.nightFullStop, 1);
  });

  test('an unparseable approach cell, real cross-country time, actual '
      'instrument time and simulator time each produce their own review '
      'note on one flight', () {
    final result = parse();
    final row = result.rows.firstWhere((r) => r.sourceRowNumber == 12);

    expect(row.flight.approaches, isEmpty);
    expect(row.reviewNotes, hasLength(4));
    expect(row.reviewNotes, contains(contains('could not be parsed')));
    expect(row.reviewNotes, contains(contains("EASA's FCL.010 pre-planned")));
    expect(row.reviewNotes, contains(contains('ifrFlightPlanFiled')));
    expect(row.reviewNotes, contains(contains('FSTD time')));
  });

  test(
    'throws FormatException for a file with no Garmin aircraft-types columns',
    () {
      expect(
        () => parse(aircraftTypes: 'just,some,csv\n1,2,3\n'),
        throwsFormatException,
      );
    },
  );

  test('throws FormatException for a file with no Garmin logbook columns', () {
    expect(
      () => parse(logEntries: 'just,some,csv\n1,2,3\n'),
      throwsFormatException,
    );
  });
}
