import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/model/flight_duration.dart';
import 'amc1_fcl050_row.dart';

/// `AMC1 FCL.050`'s twelve numbered column groups, transcribed verbatim
/// from `docs/amc1-fcl050-layout.md` §2 — the authority for every heading
/// here (#76's own citation requirement). [subHeadings] lists one entry
/// per printed leaf (sub-)column, in order; an empty string means the
/// group has no sub-column of its own (group 6, 7 and 12 are a single
/// cell, per the doc's "—" entries) and renders as a blank second header
/// row under the group name, rather than a repeated label.
class _ColumnGroup {
  const _ColumnGroup(this.number, this.heading, this.subHeadings);

  final int number;
  final String heading;
  final List<String> subHeadings;
}

const List<_ColumnGroup> _columnGroups = [
  _ColumnGroup(1, 'DATE', ['(dd/mm/yy)']),
  _ColumnGroup(2, 'DEPARTURE', ['PLACE', 'TIME']),
  _ColumnGroup(3, 'ARRIVAL', ['PLACE', 'TIME']),
  _ColumnGroup(4, 'AIRCRAFT', ['MAKE, MODEL, VARIANT', 'REGISTRATION']),
  _ColumnGroup(5, 'SINGLE-PILOT TIME / MULTI-PILOT TIME', [
    'SE',
    'ME',
    'MULTI-PILOT',
  ]),
  _ColumnGroup(6, 'TOTAL TIME OF FLIGHT', ['']),
  _ColumnGroup(7, 'NAME(S) PIC', ['']),
  _ColumnGroup(8, 'LANDINGS', ['DAY', 'NIGHT']),
  _ColumnGroup(9, 'OPERATIONAL CONDITION TIME', ['NIGHT', 'IFR']),
  _ColumnGroup(10, 'PILOT FUNCTION TIME', [
    'PIC',
    'CO-PILOT',
    'DUAL',
    'INSTRUCTOR',
  ]),
  _ColumnGroup(11, 'FSTD SESSION', [
    'DATE (dd/mm/yy)',
    'TYPE',
    'TOTAL TIME OF SESSION',
  ]),
  _ColumnGroup(12, 'REMARKS AND ENDORSEMENTS', ['']),
];

/// The twelve group headings, in `AMC1 FCL.050` order — public so a test
/// can assert this file's citation matches `docs/amc1-fcl050-layout.md`
/// §2 exactly, without parsing rendered PDF bytes back out.
List<String> amc1Fcl050ColumnGroupHeadings() => [
  for (final group in _columnGroups) group.heading,
];

/// Total printed leaf (sub-)columns across all twelve groups — 24 as
/// currently transcribed. Exposed for the same reason as
/// [amc1Fcl050ColumnGroupHeadings]: a test can catch an accidental leaf
/// miscount without rendering a page.
int amc1Fcl050LeafColumnCount() =>
    _columnGroups.fold(0, (sum, group) => sum + group.subHeadings.length);

/// One [FlexColumnWidth] per printed leaf column, in the same left-to-right
/// order [_columnGroups] enumerates them — shared between the repeating
/// header and every data row so both line up exactly. Widths are a layout
/// choice `docs/amc1-fcl050-layout.md` §6 flags as unprescribed by the AMC;
/// group 12 (remarks) gets the most room since it is free text, and every
/// duration/count column gets the least since its content is always a few
/// characters.
Map<int, pw.TableColumnWidth> _leafColumnWidths() {
  const narrow = pw.FlexColumnWidth(1);
  const wide = pw.FlexColumnWidth(2.4);
  final widths = <int, pw.TableColumnWidth>{};
  var index = 0;
  for (final group in _columnGroups) {
    for (var i = 0; i < group.subHeadings.length; i++) {
      widths[index] = group.number == 12 ? wide : narrow;
      index++;
    }
  }
  return widths;
}

const _headerBorder = pw.TableBorder(
  left: pw.BorderSide(width: 0.5),
  right: pw.BorderSide(width: 0.5),
  top: pw.BorderSide(width: 0.5),
  bottom: pw.BorderSide(width: 0.5),
  horizontalInside: pw.BorderSide(width: 0.5),
  verticalInside: pw.BorderSide(width: 0.5),
);

pw.Widget _headerCell(String text, {bool bold = false}) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 3),
  child: pw.Text(
    text,
    textAlign: pw.TextAlign.center,
    style: pw.TextStyle(
      fontSize: 6,
      fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
    ),
  ),
);

/// The repeating two-row column header: group names (`AMC1 FCL.050`'s own
/// numbering and wording) over their sub-column labels.
pw.Widget _buildColumnHeader() {
  final groupRow = <pw.Widget>[];
  final subRow = <pw.Widget>[];
  for (final group in _columnGroups) {
    for (var i = 0; i < group.subHeadings.length; i++) {
      groupRow.add(
        i == 0
            ? _headerCell('${group.number}. ${group.heading}', bold: true)
            : _headerCell(''),
      );
      subRow.add(_headerCell(group.subHeadings[i]));
    }
  }

  return pw.Table(
    border: _headerBorder,
    columnWidths: _leafColumnWidths(),
    children: [
      pw.TableRow(children: groupRow),
      pw.TableRow(children: subRow),
    ],
  );
}

pw.Widget _dataCell(String text) => pw.Padding(
  padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2),
  child: pw.Text(
    text,
    textAlign: pw.TextAlign.center,
    style: const pw.TextStyle(fontSize: 6.5),
  ),
);

/// Blank rather than `00:00` for a zero duration — the printed sheet
/// leaves a column empty when nothing applies, matching how a paper
/// logbook is actually filled in (a pilot writes `1:30`, not `0:00`, for
/// the columns that don't apply to a given flight).
String _duration(FlightDuration value) =>
    value.inMinutes == 0 ? '' : value.toHoursMinutes();

/// One printed flight row, as the twenty-four leaf cells [_columnGroups]
/// defines — group 11 (FSTD session) is always blank, since [row] never
/// carries FSTD data (`Amc1Fcl050Row`'s own dartdoc: no data model exists
/// yet for #28).
pw.Widget _buildDataRow(Amc1Fcl050Row row) {
  final cells = [
    _dataCell(row.date),
    _dataCell(row.departurePlace),
    _dataCell(row.departureTime),
    _dataCell(row.arrivalPlace),
    _dataCell(row.arrivalTime),
    _dataCell(row.aircraftMakeModelVariant),
    _dataCell(row.aircraftRegistration),
    _dataCell(_duration(row.singlePilotSingleEngine)),
    _dataCell(_duration(row.singlePilotMultiEngine)),
    _dataCell(_duration(row.multiPilotTime)),
    _dataCell(_duration(row.totalTimeOfFlight)),
    _dataCell(row.namesPic),
    _dataCell(row.landingsDay == 0 ? '' : row.landingsDay.toString()),
    _dataCell(row.landingsNight == 0 ? '' : row.landingsNight.toString()),
    _dataCell(_duration(row.operationalNight)),
    _dataCell(_duration(row.operationalIfr)),
    _dataCell(_duration(row.pilotFunctionPic)),
    _dataCell(_duration(row.pilotFunctionCoPilot)),
    _dataCell(_duration(row.pilotFunctionDual)),
    _dataCell(_duration(row.pilotFunctionInstructor)),
    _dataCell(''), // FSTD date — no session data yet (#28).
    _dataCell(''), // FSTD type.
    _dataCell(''), // FSTD total time of session.
    _dataCell(row.remarks),
  ];

  return pw.Table(
    border: _headerBorder,
    columnWidths: _leafColumnWidths(),
    children: [pw.TableRow(children: cells)],
  );
}

/// Page 1's front matter (`docs/amc1-fcl050-layout.md` §1): the holder's
/// name and licence number, centred, above the entry table.
pw.Widget _buildHolderBlock({
  required String holderName,
  required String holderLicenceNumber,
}) => pw.Padding(
  padding: const pw.EdgeInsets.only(bottom: 8),
  child: pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      pw.Text(
        'PILOT LOGBOOK',
        style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 6),
      pw.Text(
        "Holder's name(s): $holderName",
        style: const pw.TextStyle(fontSize: 9),
      ),
      pw.Text(
        "Holder's licence number: $holderLicenceNumber",
        style: const pw.TextStyle(fontSize: 9),
      ),
    ],
  ),
);

/// Builds the `AMC1 FCL.050` landscape A4 logbook document (#76): the
/// twelve column groups, headed exactly as the AMC specifies, over as many
/// pages as [rows] needs. The holder block repeats on every page so a
/// loose printed sheet is still self-identifying on its own.
///
/// Running totals (`TOTAL THIS PAGE` / `FROM PREVIOUS PAGES` / `TOTAL
/// TIME`, #77) and the certification block (#78) are not rendered yet —
/// out of scope for this issue, which is the column layout itself.
pw.Document buildAmc1Fcl050Logbook({
  required String holderName,
  required String holderLicenceNumber,
  required List<Amc1Fcl050Row> rows,
}) {
  final document = pw.Document();

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4.landscape,
      margin: const pw.EdgeInsets.all(20),
      header: (context) => pw.Column(
        children: [
          if (context.pageNumber == 1)
            _buildHolderBlock(
              holderName: holderName,
              holderLicenceNumber: holderLicenceNumber,
            ),
          _buildColumnHeader(),
        ],
      ),
      // `MultiPage` renders no page at all — not even [header] — when
      // `build` returns an empty list (its own pagination loop never runs
      // once), which would silently produce a blank AMC1 FCL.050 export
      // for a pilot with zero flights in range. A single zero-size filler
      // keeps the loop running once so the holder block and column header
      // still print — a blank logbook page is a valid document; no output
      // at all is not.
      build: (context) => rows.isEmpty
          ? [pw.SizedBox()]
          : [for (final row in rows) _buildDataRow(row)],
    ),
  );

  return document;
}
