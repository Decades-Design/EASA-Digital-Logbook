import 'dart:io';

import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/export/amc1_fcl050_layout.dart';
import 'package:easa_digital_log/export/amc1_fcl050_row.dart';
import 'package:flutter_test/flutter_test.dart';

/// #76's acceptance criteria checked directly, without needing to parse
/// rendered PDF content back out: exact group headings (`docs/amc1-fcl050-
/// layout.md` §2), the citation living in this file's own source, and that
/// a real document — one page, and many rows forced across several —
/// actually generates valid, non-empty PDF bytes.
void main() {
  test('the twelve group headings match AMC1 FCL.050 exactly, in order', () {
    expect(amc1Fcl050ColumnGroupHeadings(), [
      'DATE',
      'DEPARTURE',
      'ARRIVAL',
      'AIRCRAFT',
      'SINGLE-PILOT TIME / MULTI-PILOT TIME',
      'TOTAL TIME OF FLIGHT',
      'NAME(S) PIC',
      'LANDINGS',
      'OPERATIONAL CONDITION TIME',
      'PILOT FUNCTION TIME',
      'FSTD SESSION',
      'REMARKS AND ENDORSEMENTS',
    ]);
  });

  test('every leaf sub-column is accounted for', () {
    expect(amc1Fcl050LeafColumnCount(), 24);
  });

  test('AMC1 FCL.050 is cited in the layout source itself', () {
    final source = File(
      'lib/export/amc1_fcl050_layout.dart',
    ).readAsStringSync();
    expect(source, contains('AMC1 FCL.050'));
  });

  Amc1Fcl050Row sampleRow() => const Amc1Fcl050Row(
    date: '01/06/26',
    departurePlace: 'EGKA',
    departureTime: '09:00',
    arrivalPlace: 'EGKA',
    arrivalTime: '10:30',
    aircraftMakeModelVariant: 'Cessna 152',
    aircraftRegistration: 'G-ABCD',
    singlePilotSingleEngine: FlightDuration(90),
    singlePilotMultiEngine: FlightDuration.zero,
    multiPilotTime: FlightDuration.zero,
    totalTimeOfFlight: FlightDuration(90),
    namesPic: 'SELF',
    landingsDay: 1,
    landingsNight: 0,
    operationalNight: FlightDuration.zero,
    operationalIfr: FlightDuration.zero,
    pilotFunctionPic: FlightDuration(90),
    pilotFunctionCoPilot: FlightDuration.zero,
    pilotFunctionDual: FlightDuration.zero,
    pilotFunctionInstructor: FlightDuration.zero,
    remarks: 'Local flight.',
  );

  test(
    'a document with no rows still generates a valid single-page PDF',
    () async {
      final document = buildAmc1Fcl050Logbook(
        holderName: 'Jane Pilot',
        holderLicenceNumber: 'UK.FCL.123456',
        rows: const [],
      );

      final bytes = await document.save();

      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
      expect(document.document.pdfPageList.pages, hasLength(1));
    },
  );

  test('enough rows to overflow one page produce more than one page', () async {
    final document = buildAmc1Fcl050Logbook(
      holderName: 'Jane Pilot',
      holderLicenceNumber: 'UK.FCL.123456',
      rows: List.generate(80, (_) => sampleRow()),
    );

    final bytes = await document.save();

    expect(bytes, isNotEmpty);
    expect(document.document.pdfPageList.pages.length, greaterThan(1));
  });
}
