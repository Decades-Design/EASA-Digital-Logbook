import 'dart:io';

import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/export/amc1_fcl050_layout.dart';
import 'package:easa_digital_log/export/amc1_fcl050_row.dart';
import 'package:easa_digital_log/export/amc1_fcl050_totals.dart';
import 'package:flutter_test/flutter_test.dart';

/// #76's acceptance criteria checked directly, without needing to parse
/// rendered PDF content back out: exact group headings (`docs/amc1-fcl050-
/// layout.md` §2), the citation living in this file's own source, and that
/// a real document — one page, and many rows forced across several —
/// actually generates valid, non-empty PDF bytes.
///
/// [TestWidgetsFlutterBinding.ensureInitialized] is required here even
/// though nothing pumps a widget: `buildAmc1Fcl050Logbook` embeds real
/// font assets via `rootBundle.load`, which needs a Flutter binding to
/// resolve — the same asset-loading machinery `logbook_screen_test.dart`
/// documents for the (much larger) OurAirports CSV.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the twelve group headings match AMC1 FCL.050 exactly, in order', () {
    expect(amc1Fcl050ColumnGroupHeadings(), [
      'DATE (dd/mm/yy)',
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

  test(
    'every duration leaf splits into two physical hours/minutes columns',
    () {
      // 16 on page one (14 leaves, 2 of them durations: MULTI-PILOT TIME,
      // TOTAL TIME OF FLIGHT); 17 on page two (10 leaves, 7 durations:
      // NIGHT, IFR, PIC, CO-PILOT, DUAL, INSTRUCTOR, TOTAL TIME OF
      // SESSION) — confirmed against a reference transcript of the real
      // published template during #76's review.
      expect(amc1Fcl050PhysicalColumnCount(true), 16);
      expect(amc1Fcl050PhysicalColumnCount(false), 17);
    },
  );

  test('the page footer names both the page number and the total page count '
      '(#78)', () {
    expect(amc1Fcl050PageFooterText(3, 12), 'Page 3 of 12');
    expect(amc1Fcl050PageFooterText(1, 1), 'Page 1 of 1');
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

  test('page one (groups 1-8) carries date through landings, in order, with '
      'SE/ME as ticks and durations split into hours/minutes — not page '
      "two's columns", () {
    expect(amc1Fcl050PageOneCellValues(sampleRow()), [
      '01/06/26',
      'EGKA',
      '09:00',
      'EGKA',
      '10:30',
      'Cessna 152',
      'G-ABCD',
      'X',
      '',
      '',
      '',
      '01',
      '30',
      'SELF',
      '1',
      '',
    ]);
  });

  test('page two (groups 9-12) carries operational/pilot-function time '
      'through remarks, durations split into hours/minutes — not page '
      "one's columns", () {
    expect(amc1Fcl050PageTwoCellValues(sampleRow()), [
      '',
      '',
      '',
      '',
      '01',
      '30',
      '',
      '',
      '',
      '',
      '',
      '',
      '',
      '',
      '',
      '',
      'Local flight.',
    ]);
  });

  test('a countersignature line joins remarks on its own line in group 12 '
      '(#78)', () {
    const row = Amc1Fcl050Row(
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
      countersignature: 'Countersigned by K. Almqvist (SWE.ATPL.90233)',
    );

    expect(
      amc1Fcl050PageTwoCellValues(row).last,
      'Local flight.\nCountersigned by K. Almqvist (SWE.ATPL.90233)',
    );
  });

  test('a countersignature line with no remarks prints alone, with no leading '
      'blank line (#78)', () {
    const row = Amc1Fcl050Row(
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
      remarks: '',
      countersignature: 'Countersignature pending',
    );

    expect(amc1Fcl050PageTwoCellValues(row).last, 'Countersignature pending');
  });

  test('a document with no flight rows still generates front matter, an '
      'address page, and one blank two-page entry spread (columns 1-8, '
      'then 9-12)', () async {
    final document = await buildAmc1Fcl050Logbook(
      holderName: 'Jane Pilot',
      holderLicenceNumber: 'UK.FCL.123456',
      rows: const [],
    );

    final bytes = await document.save();

    expect(bytes, isNotEmpty);
    expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    expect(document.document.pdfPageList.pages, hasLength(4));
  });

  test('enough rows to overflow one entry spread produce further two-page '
      'spreads', () async {
    final document = await buildAmc1Fcl050Logbook(
      holderName: 'Jane Pilot',
      holderLicenceNumber: 'UK.FCL.123456',
      rows: List.generate(80, (_) => sampleRow()),
    );

    final bytes = await document.save();

    expect(bytes, isNotEmpty);
    // 2 front-matter pages + an even number of entry-spread pages (each
    // spread is always a pair — columns 1-8, then 9-12 — never a lone
    // half-page).
    final pageCount = document.document.pdfPageList.pages.length;
    expect(pageCount, greaterThan(4));
    expect((pageCount - 2) % 2, 0);
  });

  test('the rendered document has exactly 2 front-matter pages plus 2 pages '
      'per entry spread — the arithmetic the page-number footer\'s total '
      'relies on (#78)', () async {
    final rows = List.generate(80, (_) => sampleRow());
    final document = await buildAmc1Fcl050Logbook(
      holderName: 'Jane Pilot',
      holderLicenceNumber: 'UK.FCL.123456',
      rows: rows,
    );
    final spreads = await amc1Fcl050SpreadTotals(rows);

    final bytes = await document.save();
    expect(bytes, isNotEmpty);
    expect(document.document.pdfPageList.pages.length, 2 + spreads.length * 2);
  });

  test('no flight rows still produce exactly one all-zero spread', () async {
    final spreads = await amc1Fcl050SpreadTotals(const []);

    expect(spreads, hasLength(1));
    expect(
      amc1Fcl050PageOneTotalsValues(spreads.single.broughtForward),
      amc1Fcl050PageOneTotalsValues(Amc1Fcl050Totals.zero),
    );
    expect(
      amc1Fcl050PageOneTotalsValues(spreads.single.totalToDate),
      amc1Fcl050PageOneTotalsValues(Amc1Fcl050Totals.zero),
    );
  });

  test('a single-flight range has that flight as this-page, zero brought '
      'forward, and total-to-date equal to this-page', () async {
    final spreads = await amc1Fcl050SpreadTotals([sampleRow()]);

    expect(spreads, hasLength(1));
    final expected = Amc1Fcl050Totals.fromRows([sampleRow()]);
    expect(
      amc1Fcl050PageOneTotalsValues(spreads.single.thisPage),
      amc1Fcl050PageOneTotalsValues(expected),
    );
    expect(
      amc1Fcl050PageOneTotalsValues(spreads.single.broughtForward),
      amc1Fcl050PageOneTotalsValues(Amc1Fcl050Totals.zero),
    );
    expect(
      amc1Fcl050PageOneTotalsValues(spreads.single.totalToDate),
      amc1Fcl050PageOneTotalsValues(expected),
    );
  });

  test(
    'brought-forward on spread n equals total-to-date on spread n-1, for '
    'every column, on every page boundary of a multi-spread export — #77',
    () async {
      final rows = List.generate(80, (_) => sampleRow());
      final spreads = await amc1Fcl050SpreadTotals(rows);

      expect(
        spreads.length,
        greaterThan(1),
        reason:
            '80 rows must overflow a single spread for this test to '
            'actually exercise reconciliation across a page boundary',
      );

      expect(
        amc1Fcl050PageOneTotalsValues(spreads.first.broughtForward),
        amc1Fcl050PageOneTotalsValues(Amc1Fcl050Totals.zero),
      );

      for (var i = 1; i < spreads.length; i++) {
        expect(
          amc1Fcl050PageOneTotalsValues(spreads[i].broughtForward),
          amc1Fcl050PageOneTotalsValues(spreads[i - 1].totalToDate),
          reason: 'page one, spread $i',
        );
        expect(
          amc1Fcl050PageTwoTotalsValues(spreads[i].broughtForward),
          amc1Fcl050PageTwoTotalsValues(spreads[i - 1].totalToDate),
          reason: 'page two, spread $i',
        );
      }

      final overall = Amc1Fcl050Totals.fromRows(rows);
      expect(
        amc1Fcl050PageOneTotalsValues(spreads.last.totalToDate),
        amc1Fcl050PageOneTotalsValues(overall),
      );
    },
  );

  test('an opening balance seeds the first spread\'s brought-forward instead '
      'of zero (#83)', () async {
    final opening = Amc1Fcl050Totals.fromRows([sampleRow()]);

    final spreads = await amc1Fcl050SpreadTotals([
      sampleRow(),
    ], openingBalance: opening);

    expect(spreads, hasLength(1));
    expect(
      amc1Fcl050PageOneTotalsValues(spreads.single.broughtForward),
      amc1Fcl050PageOneTotalsValues(opening),
    );
    // total-to-date = opening balance + this page's own flight.
    final expectedTotal = opening + Amc1Fcl050Totals.fromRows([sampleRow()]);
    expect(
      amc1Fcl050PageOneTotalsValues(spreads.single.totalToDate),
      amc1Fcl050PageOneTotalsValues(expectedTotal),
    );
  });

  // #80's row-height budget boundary. `sampleRow()`'s own short remark
  // ('Local flight.') never wraps, so every row here is exactly
  // _dataRowHeight tall — empirically confirmed (not just computed by
  // hand) that 25 such rows exactly fill one spread's own row budget on
  // this page format/margins, and a 26th overflows it. A change to page
  // geometry that moves this boundary is expected to need this test
  // updated; that is the point of pinning it.

  test(
    '25 uniform-height rows exactly fill one spread\'s row budget (#80)',
    () async {
      final spreads = await amc1Fcl050SpreadTotals(
        List.generate(25, (_) => sampleRow()),
      );

      expect(spreads, hasLength(1));
      expect(spreads.single.rows, hasLength(25));
    },
  );

  test('a 26th row past the budget starts a new spread instead of overflowing '
      'the page (#80)', () async {
    final spreads = await amc1Fcl050SpreadTotals(
      List.generate(26, (_) => sampleRow()),
    );

    expect(spreads, hasLength(2));
    expect(spreads[0].rows, hasLength(25));
    expect(spreads[1].rows, hasLength(1));
  });

  test('a remark so long it alone exceeds an entire spread\'s budget still '
      'gets a spread of its own, never split or dropped (#80)', () async {
    final longRemark = List.filled(300, 'word').join(' ');
    final row = Amc1Fcl050Row(
      date: '01/06/26',
      departurePlace: 'EGKA',
      departureTime: '09:00',
      arrivalPlace: 'EGKA',
      arrivalTime: '10:30',
      aircraftMakeModelVariant: 'Cessna 152',
      aircraftRegistration: 'G-ABCD',
      singlePilotSingleEngine: const FlightDuration(90),
      singlePilotMultiEngine: FlightDuration.zero,
      multiPilotTime: FlightDuration.zero,
      totalTimeOfFlight: const FlightDuration(90),
      namesPic: 'SELF',
      landingsDay: 1,
      landingsNight: 0,
      operationalNight: FlightDuration.zero,
      operationalIfr: FlightDuration.zero,
      pilotFunctionPic: const FlightDuration(90),
      pilotFunctionCoPilot: FlightDuration.zero,
      pilotFunctionDual: FlightDuration.zero,
      pilotFunctionInstructor: FlightDuration.zero,
      remarks: longRemark,
    );

    final spreads = await amc1Fcl050SpreadTotals([row]);

    expect(spreads, hasLength(1));
    expect(spreads.single.rows, hasLength(1));
    expect(spreads.single.rows.single.remarks, longRemark);
  });
}
