import 'dart:io';

import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:easa_digital_log/io/foreflight/foreflight_adapter.dart';
import 'package:easa_digital_log/io/import_adapter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exercises [ForeFlightAdapter] against an anonymised fixture built to
/// mirror the real structural shape of a `logbook_template.csv` export
/// (two embedded tables, a typed custom field, an FTD/equipType row, a
/// blank-data placeholder aircraft, touch-and-go ambiguity, a quoted
/// comma, an unparseable approach cell) without carrying anyone's real
/// name or flight history — see the fixture file's own header for
/// provenance.
void main() {
  late String csv;

  setUpAll(() {
    csv = File(
      'test/io/foreflight/fixtures/logbook_template_sample.csv',
    ).readAsStringSync();
  });

  ImportParseResult parse(String source) =>
      ForeFlightAdapter().parse({ForeFlightAdapter.logbookKey: source});

  test('maps every clean row and reports every unmappable one', () {
    final result = parse(csv);

    expect(result.rows, hasLength(8));
    expect(result.errors, hasLength(2));
    expect(result.hasErrors, isTrue);
  });

  test('a plain solo PIC flight maps cleanly, with its approach parsed', () {
    final result = parse(csv);
    final row = result.rows.firstWhere((r) => r.sourceRowNumber == 11);

    expect(row.flight.route, ['KABC', 'KDEF']);
    expect(row.flight.capacity.commandAuthority, isTrue);
    expect(row.flight.capacity.soleManipulator, isTrue);
    expect(row.flight.capacity.soleOccupant, isTrue);
    expect(row.flight.approaches, hasLength(1));
    expect(row.flight.approaches.single.type, ApproachType.ils);
    expect(row.flight.approaches.single.aerodromeIcao, 'KDEF');
    expect(row.aircraft.registration, 'N100AB');
    expect(row.reviewNotes, isEmpty);
  });

  test('dual received is mapped with commandAuthority false and a review '
      'note about the SPIC/dual gap', () {
    final result = parse(csv);
    final row = result.rows.firstWhere((r) => r.sourceRowNumber == 12);

    expect(row.flight.capacity.commandAuthority, isFalse);
    expect(row.flight.capacity.instructor?.influencedFlight, isTrue);
    expect(row.flight.capacity.instructor?.name, 'Jane Instructor');
    expect(row.reviewNotes, contains(contains('SPIC vs. dual')));
  });

  test('a PICUS claim is mapped, flagged for countersignature review', () {
    final result = parse(csv);
    final row = result.rows.firstWhere((r) => r.sourceRowNumber == 13);

    expect(row.flight.capacity.picusClaimed, isTrue);
    expect(row.flight.capacity.commandAuthority, isFalse);
    expect(row.reviewNotes, contains(contains('PICUS')));
  });

  test('AllLandings exceeding the full-stop counts is read as touch-and-go, '
      'flagged for a day/night review', () {
    final result = parse(csv);
    final row = result.rows.firstWhere((r) => r.sourceRowNumber == 14);

    expect(row.flight.landings.dayFullStop, 1);
    expect(row.flight.landings.dayTouchAndGo, 2);
    expect(row.flight.landings.nightTouchAndGo, 0);
    expect(row.reviewNotes, contains(contains('touch-and-go')));
  });

  test(
    'an aircraft row with no make/model becomes an error, never a guess',
    () {
      final result = parse(csv);
      final error = result.errors.firstWhere((e) => e.rowNumber == 15);

      expect(error.message, contains('XXXX'));
    },
  );

  test('a flight training device (equipType=ftd) becomes an error, never '
      'imported as a regular aircraft flight', () {
    final result = parse(csv);
    final error = result.errors.firstWhere((e) => e.rowNumber == 16);

    expect(error.message, contains('flight training device'));
  });

  test('the [Text]Safety pilot custom field maps to otherPilotName and '
      'OtherPilotRole.safetyPilot, not a preserved string', () {
    final result = parse(csv);
    final row = result.rows.firstWhere((r) => r.sourceRowNumber == 17);

    expect(row.flight.otherPilotName, 'Alex Rivera');
    expect(row.flight.capacity.otherPilotRole, OtherPilotRole.safetyPilot);
    expect(row.unmappedFields.containsKey('[Text]Safety pilot'), isFalse);
  });

  test('a flight crossing midnight Zulu rolls the on-blocks date forward '
      'rather than reading as a negative block time', () {
    final result = parse(csv);
    final row = result.rows.firstWhere((r) => r.sourceRowNumber == 18);

    expect(row.flight.offBlocks.toIso8601String(), '2026-01-08T23:50:00.000Z');
    expect(row.flight.onBlocks.toIso8601String(), '2026-01-09T00:20:00.000Z');
    expect(row.flight.onBlocks.difference(row.flight.offBlocks).inMinutes, 30);
  });

  test('a quoted field containing an embedded comma survives intact — proves '
      'real CSV parsing, not a naive comma split', () {
    final result = parse(csv);
    final row = result.rows.firstWhere((r) => r.sourceRowNumber == 19);

    expect(
      row.unmappedFields['PilotComments'],
      'Great flight, smooth air throughout',
    );
  });

  test('an approach cell with no aerodrome is dropped with a review note, '
      'not left in Flight.approaches and not failing the whole row', () {
    final result = parse(csv);
    final row = result.rows.firstWhere((r) => r.sourceRowNumber == 20);

    expect(row.flight.approaches, isEmpty);
    expect(row.reviewNotes, contains(contains('could not be parsed')));
  });

  test(
    'throws FormatException for a file with no ForeFlight table markers',
    () {
      expect(() => parse('just,some,csv\n1,2,3\n'), throwsFormatException);
    },
  );
}
