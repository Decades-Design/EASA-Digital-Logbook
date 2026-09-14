import 'package:flutter/services.dart' show rootBundle;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../domain/model/flight_duration.dart';
import 'amc1_fcl050_row.dart';
import 'amc1_fcl050_totals.dart';

/// One value slot within a header cell: a plain single column ([weight]
/// its own printed width), or a duration that must print as two physical
/// columns — whole hours, then minutes, [isDuration] true — with no label
/// of its own on either half. Confirmed against a reference transcript of
/// the real published template during #76's review: every duration-
/// bearing column (`MULTI-PILOT TIME`, `TOTAL TIME OF FLIGHT`, `NIGHT`,
/// `IFR`, each of `PILOT FUNCTION TIME`'s four, `TOTAL TIME OF SESSION`)
/// is split this way, unlike a place, a count, or free text.
class _LeafSpec {
  const _LeafSpec(this.label, this.weight, {this.isDuration = false});

  final String label;
  final double weight;
  final bool isDuration;
}

/// One printed header cell under a numbered `AMC1 FCL.050` group — either
/// a single cell with no further split ([_Leaf], vertically centred
/// across the full header height: `TOTAL TIME OF FLIGHT`, `NAME(S)
/// PIC`, ...), or one that splits into leaf sub-columns of its own
/// ([_Split]: `DEPARTURE` into `PLACE`/`TIME`, and so on). A group has
/// more than one cell only for group 5, whose `SINGLE-PILOT TIME`/
/// `MULTI-PILOT TIME` sit side by side under the same bare number — see
/// [_columnGroups]'s own dartdoc.
sealed class _HeaderCell {
  const _HeaderCell(this.heading);

  final String heading;
}

class _Leaf extends _HeaderCell {
  const _Leaf(super.heading, this.weight, {this.isDuration = false});

  final double weight;
  final bool isDuration;
}

class _Split extends _HeaderCell {
  const _Split(super.heading, this.subLeaves);

  final List<_LeafSpec> subLeaves;
}

/// Printed leaf count within one cell — 2 for a duration (hours,
/// minutes), 1 otherwise.
int _cellLeafCount(_HeaderCell cell) {
  if (cell is _Leaf) return cell.isDuration ? 2 : 1;
  final split = cell as _Split;
  return split.subLeaves.fold(
    0,
    (sum, leaf) => sum + (leaf.isDuration ? 2 : 1),
  );
}

/// One of `AMC1 FCL.050`'s twelve numbered column groups, transcribed
/// verbatim from `docs/amc1-fcl050-layout.md` §2 and cross-checked
/// against a reference transcript of the real published template during
/// #76's review — the authority for every heading, column weight and
/// duration-split decision here.
///
/// [cells] is a list of one, except group 5: the printed sheet gives
/// `SINGLE-PILOT TIME` (split `SE`/`ME`) and `MULTI-PILOT TIME`
/// (unsplit) side by side under the single bare number `5`, not one
/// combined heading spanning three leaves.
///
/// The real template splits the twelve groups across a landscape
/// **two-page spread** — groups 1–8 on the left page, 9–12 on the
/// right — not one page with all twenty-four leaves crammed onto it.
/// [_pageOneGroups] and [_pageTwoGroups] are that split. Every leaf's
/// [_LeafSpec.weight]/[_Leaf.weight] is the exact reference proportion,
/// scaled once per page against that page's own content width — the two
/// pages' weights each sum to 1020 independently, matching the reference
/// exactly.
class _ColumnGroup {
  const _ColumnGroup(this.number, this.cells);

  final int number;
  final List<_HeaderCell> cells;
}

const List<_ColumnGroup> _pageOneGroups = [
  _ColumnGroup(1, [_Leaf('DATE\n(dd/mm/yy)', 80)]),
  _ColumnGroup(2, [
    _Split('DEPARTURE', [_LeafSpec('PLACE', 50), _LeafSpec('TIME', 50)]),
  ]),
  _ColumnGroup(3, [
    _Split('ARRIVAL', [_LeafSpec('PLACE', 50), _LeafSpec('TIME', 50)]),
  ]),
  _ColumnGroup(4, [
    _Split('AIRCRAFT', [
      _LeafSpec('MAKE, MODEL,\nVARIANT', 100),
      _LeafSpec('REGISTRATION', 100),
    ]),
  ]),
  _ColumnGroup(5, [
    _Split('SINGLE-PILOT\nTIME', [_LeafSpec('SE', 40), _LeafSpec('ME', 40)]),
    _Leaf('MULTI-PILOT\nTIME', 80, isDuration: true),
  ]),
  _ColumnGroup(6, [_Leaf('TOTAL TIME\nOF FLIGHT', 80, isDuration: true)]),
  _ColumnGroup(7, [_Leaf('NAME(S) PIC', 200)]),
  _ColumnGroup(8, [
    _Split('LANDINGS', [_LeafSpec('DAY', 50), _LeafSpec('NIGHT', 50)]),
  ]),
];

const List<_ColumnGroup> _pageTwoGroups = [
  _ColumnGroup(9, [
    _Split('OPERATIONAL\nCONDITION TIME', [
      _LeafSpec('NIGHT', 90, isDuration: true),
      _LeafSpec('IFR', 90, isDuration: true),
    ]),
  ]),
  _ColumnGroup(10, [
    _Split('PILOT FUNCTION TIME', [
      _LeafSpec('PIC', 90, isDuration: true),
      _LeafSpec('CO-PILOT', 90, isDuration: true),
      _LeafSpec('DUAL', 90, isDuration: true),
      _LeafSpec('INSTRUCTOR', 90, isDuration: true),
    ]),
  ]),
  _ColumnGroup(11, [
    _Split('FSTD SESSION', [
      _LeafSpec('DATE\n(dd/mm/yy)', 80),
      _LeafSpec('TYPE', 60),
      _LeafSpec('TOTAL TIME\nOF SESSION', 100, isDuration: true),
    ]),
  ]),
  _ColumnGroup(12, [_Leaf('REMARKS AND\nENDORSEMENTS', 240)]),
];

const List<_ColumnGroup> _allGroups = [..._pageOneGroups, ..._pageTwoGroups];

/// The twelve group headings, in `AMC1 FCL.050` order, as one string each
/// (group 5's two cells joined the same way `docs/amc1-fcl050-layout.md`
/// §2 itself writes them) — public so a test can assert this file's
/// citation matches the source doc exactly, without parsing rendered PDF
/// bytes back out.
List<String> amc1Fcl050ColumnGroupHeadings() => [
  for (final group in _allGroups)
    group.cells.map((cell) => cell.heading.replaceAll('\n', ' ')).join(' / '),
];

/// Total printed leaf (sub-)columns across all twelve groups — 24 as
/// currently transcribed (a duration counts once here regardless of its
/// two printed hour/minute columns; see [amc1Fcl050PhysicalColumnCount]
/// for that count). Exposed for the same reason as
/// [amc1Fcl050ColumnGroupHeadings]: a test can catch an accidental leaf
/// miscount without rendering a page.
int amc1Fcl050LeafColumnCount() => _allGroups.fold(0, (sum, group) {
  return sum +
      group.cells.fold(0, (s, cell) {
        if (cell is _Leaf) return s + 1;
        return s + (cell as _Split).subLeaves.length;
      });
});

// ---- Page geometry. Every band below is built from absolute point
// widths, not `pw.Table`'s intrinsic/flex sizing, because a real header
// cell often has to span several leaf columns genuinely — "5" centred
// over SE+ME+MULTI-PILOT, "DEPARTURE" centred over PLACE+TIME, "NIGHT"
// centred over its own hours+minutes pair — and `pw.Table` has no
// colspan to do that with. Computing one absolute width per physical
// column up front and reusing it for the data grid's `FixedColumnWidth`
// *and* every header/totals/certification band's `Container` widths
// guarantees every band's grid lines land in exactly the same place,
// regardless of which widget system built it.

const _pageFormat = PdfPageFormat.a4;
const _pageMargin = 20.0;
const _numberRowHeight = 14.0;
const _headingRowHeight = 18.0;
// Tall enough for a two-line sub-heading label ("MAKE, MODEL,\nVARIANT",
// "DATE\n(dd/mm/yy)", "TOTAL TIME\nOF SESSION") at the sub-heading font
// size, not just the one-line labels ("SE", "PLACE") most of them are —
// too short here overflowed into the divider and the data row below it.
const _subHeaderRowHeight = 24.0;
const _headerHeight =
    _numberRowHeight + _headingRowHeight + _subHeaderRowHeight;
// A minimum, not a fixed height: a row with nothing (or a short remark)
// stays this compact, but `pw.Table` still lets the row grow past it —
// `_dataCell` uses `BoxConstraints.minHeight`, not a tight `height`, for
// exactly that reason — when a longer remark wraps onto more than one
// line.
const _dataRowHeight = 16.0;
const _dataCellFontSize = 9.0;
// A standard typographic approximation for single-spaced text — a line's
// own height is roughly 1.2x its font size.
const _textLineHeightFactor = 1.2;
const _totalsFontSize = 10.0;
// 1.5x a normal entry row's height, per the reference logbook design and
// the pilot's own print review — enough room to actually sign, not just
// print a total figure.
const _totalsRowHeight = _dataRowHeight * 1.5;
// The band beneath the grid is `docs/amc1-fcl050-layout.md` §3's three
// named rows (`TOTAL THIS PAGE` / `TOTAL FROM PREVIOUS PAGES` / `TOTAL
// TIME`, left-hand page only) — confirmed against a reference transcript
// of the real published template during #76's review, which merges the
// entire §4 certification block (statement, blank signing space, a
// signature line, `PILOT'S SIGNATURE`) into *one* remarks-column cell
// spanning all three rows' combined height, not a separate fourth row.
const _bottomBandRowCount = 3;
const _bottomBandHeight = _totalsRowHeight * _bottomBandRowCount;
// The page-number footer's own height (8pt text plus its own top
// padding) — reserved alongside the header and bottom band in
// [_packEntrySpreads]'s own budget so a tightly-packed page never leaves
// so little slack that the footer, the last child of the page's column,
// is the one pushed past the bottom edge and clipped.
const _footerHeight = 14.0;

double get _contentWidth => _pageFormat.landscape.width - _pageMargin * 2;

/// One printed grid column — the unit both the header bands and the data
/// table are built from. A duration [_LeafSpec]/[_Leaf] contributes two
/// of these (hours, then minutes), each carrying half its combined
/// [weight] and no label of its own; every other leaf contributes one.
class _PhysicalColumn {
  const _PhysicalColumn({
    required this.weight,
    required this.groupNumber,
    required this.isFirstOfGroup,
    required this.cell,
    required this.isFirstOfCell,
    required this.subHeadingLabel,
    required this.isFirstOfSubHeading,
  });

  final double weight;
  final int groupNumber;
  final bool isFirstOfGroup;
  final _HeaderCell cell;
  final bool isFirstOfCell;

  /// This leaf's own sub-column label — null for a [_Leaf] cell, which
  /// has none.
  final String? subHeadingLabel;

  /// True on the hours half of a duration pair (or on the only physical
  /// column of a non-duration leaf) — false on the minutes half, which
  /// repeats no label.
  final bool isFirstOfSubHeading;
}

List<_PhysicalColumn> _physicalColumns(List<_ColumnGroup> groups) {
  final columns = <_PhysicalColumn>[];

  // Deliberately a flat loop rather than a nested closure-calling helper:
  // an earlier version captured `firstOfGroup`/`firstOfCell` in a closure
  // evaluated *inside* a duration's own 2-iteration loop, so both its
  // physical columns read the same not-yet-flipped `true` — the bug
  // #76's print review caught as the bare group number appearing twice
  // ("6 6") on a split duration. Flipping the flags immediately after
  // each physical column is pushed, in the same loop that reads them,
  // makes that impossible to get wrong the same way again.
  for (final group in groups) {
    var firstOfGroup = true;
    for (final cell in group.cells) {
      var firstOfCell = true;
      final leafSpecs = cell is _Split
          ? cell.subLeaves
          : [
              _LeafSpec(
                '',
                (cell as _Leaf).weight,
                isDuration: cell.isDuration,
              ),
            ];
      for (final leafSpec in leafSpecs) {
        final parts = leafSpec.isDuration ? 2 : 1;
        for (var i = 0; i < parts; i++) {
          columns.add(
            _PhysicalColumn(
              weight: leafSpec.weight / parts,
              groupNumber: group.number,
              isFirstOfGroup: firstOfGroup,
              cell: cell,
              isFirstOfCell: firstOfCell,
              subHeadingLabel: cell is _Split ? leafSpec.label : null,
              isFirstOfSubHeading: i == 0,
            ),
          );
          firstOfGroup = false;
          firstOfCell = false;
        }
      }
    }
  }
  return columns;
}

/// Total physical (printed) grid columns for [groups] — 16 for page one,
/// 17 for page two, once every duration leaf's hour/minute split is
/// counted. Exposed alongside [amc1Fcl050LeafColumnCount] so a test can
/// pin both counts independently.
int amc1Fcl050PhysicalColumnCount(bool pageOne) =>
    _physicalColumns(pageOne ? _pageOneGroups : _pageTwoGroups).length;

/// Absolute point width per physical column, scaled from the reference
/// template's own unit weights (which sum to 1020 on each page
/// independently) against this page's actual content width.
List<double> _columnWidths(List<_ColumnGroup> groups) {
  final columns = _physicalColumns(groups);
  final totalWeight = columns.fold<double>(0, (sum, c) => sum + c.weight);
  final unit = _contentWidth / totalWeight;
  return [for (final c in columns) c.weight * unit];
}

Map<int, pw.TableColumnWidth> _tableColumnWidths(List<double> widths) => {
  for (var i = 0; i < widths.length; i++) i: pw.FixedColumnWidth(widths[i]),
};

// Two-tier border weight, transcribed from the reference logbook design
// (`Logbook Format.xlsx`): medium separates distinct sub-columns, groups,
// and the grid's own outer edges (including the header/body and
// body/totals-band boundaries); thin is reserved for the hours/minutes
// split within one duration value and for the divider between successive
// entry rows. First-pass point values, pending visual review of a
// generated sample.
const _thinBorderSide = pw.BorderSide(width: 0.5);
const _mediumBorderSide = pw.BorderSide(width: 1.5);

/// The vertical border weight at every boundary between and around
/// [columns] — index `i` is the boundary to the *left* of physical column
/// `i` (so `boundaries[0]` is the grid's own left edge and
/// `boundaries[columns.length]` its right edge). Thin only between the
/// hours and minutes halves of one duration ([_PhysicalColumn.
/// isFirstOfSubHeading] false marks the minutes half); medium everywhere
/// else, since every other adjacent pair is either a different named
/// sub-column (`PLACE`│`TIME`, `SE`│`ME`, `DAY`│`NIGHT`, ...), a group
/// boundary, or the grid's own edge.
List<pw.BorderSide> _columnBoundaries(List<_PhysicalColumn> columns) => [
  for (var boundary = 0; boundary <= columns.length; boundary++)
    if (boundary > 0 &&
        boundary < columns.length &&
        !columns[boundary].isFirstOfSubHeading)
      _thinBorderSide
    else
      _mediumBorderSide,
];

/// The four-sided border for physical column [i], reading left/right
/// weight from [boundaries] (`_columnBoundaries`, shared by every row of
/// the same grid) and taking top/bottom weight from the row itself —
/// medium at the header/body and body/totals-band boundaries, thin
/// between ordinary entry rows.
pw.Border _rowCellBorder(
  List<pw.BorderSide> boundaries,
  int i, {
  required pw.BorderSide topWeight,
  required pw.BorderSide bottomWeight,
}) => pw.Border(
  left: boundaries[i],
  right: boundaries[i + 1],
  top: topWeight,
  bottom: bottomWeight,
);

/// The three fonts the reference template uses, embedded once per
/// document build. `Open Sans` (headings, labels, totals) and `Ubuntu`
/// (the certification statement, explicitly 9pt in the reference) are
/// both openly licensed (Apache 2.0 / Ubuntu Font Licence) and bundled as
/// assets. Data cells use the reference's own choice of a monospaced
/// font for entered values — but the reference's actual font, Consolas,
/// is a proprietary Microsoft font this app has no licence to embed, so
/// [pw.Font.courier] (a standard, freely-available PDF font with the
/// same monospaced character) stands in for it.
class _Fonts {
  const _Fonts({
    required this.openSansRegular,
    required this.openSansBold,
    required this.ubuntuRegular,
  });

  final pw.Font openSansRegular;
  final pw.Font openSansBold;
  final pw.Font ubuntuRegular;

  pw.Font get monospace => pw.Font.courier();
}

Future<pw.Font> _loadFont(String assetPath) async {
  final data = await rootBundle.load(assetPath);
  return pw.Font.ttf(data);
}

Future<_Fonts> _loadFonts() async => _Fonts(
  openSansRegular: await _loadFont('assets/fonts/pdf/OpenSans-Regular.ttf'),
  openSansBold: await _loadFont('assets/fonts/pdf/OpenSans-Bold.ttf'),
  ubuntuRegular: await _loadFont('assets/fonts/pdf/Ubuntu-Regular.ttf'),
);

pw.Widget _numberCell(_Fonts fonts, String text, double width) => pw.Container(
  width: width,
  height: _numberRowHeight,
  alignment: pw.Alignment.center,
  decoration: const pw.BoxDecoration(
    border: pw.Border.fromBorderSide(_mediumBorderSide),
  ),
  child: pw.Text(
    text,
    style: pw.TextStyle(font: fonts.openSansBold, fontSize: 10),
  ),
);

/// One box per *group* (not physical column), spanning the sum of its own
/// physical columns' widths — a genuine visual merge, built with [pw.Row]
/// rather than [pw.Table] (which has no colspan) so the reference
/// template's bare group number can span the group's full width with no
/// internal divider, exactly as printed (`I2:L2` merged for group 5's
/// SE/ME/MULTI-PILOT span, for example) rather than repeated once per
/// printed sub-column.
pw.Widget _numberBand(
  _Fonts fonts,
  List<double> widths,
  List<_PhysicalColumn> columns,
) {
  final cellWidgets = <pw.Widget>[];
  for (var i = 0; i < columns.length; i++) {
    if (!columns[i].isFirstOfGroup) continue;
    var end = i + 1;
    while (end < columns.length && !columns[end].isFirstOfGroup) {
      end++;
    }
    final groupWidth = widths.sublist(i, end).fold<double>(0, (a, b) => a + b);
    cellWidgets.add(
      _numberCell(fonts, '${columns[i].groupNumber}', groupWidth),
    );
  }
  return pw.Row(children: cellWidgets);
}

/// The heading+sub-heading tier for one *cell* (not physical column),
/// spanning the sum of its own physical columns' widths — a genuine
/// visual merge, since [pw.Table] has no colspan. A [_Leaf] cell's
/// heading fills the box, centred top to bottom, since it has nothing to
/// split into. A [_Split] cell shows its heading centred across the
/// whole box's width in the upper zone, over a divider, over its own
/// per-leaf sub-headings — each of which is itself a further merge when
/// it is a duration (`NIGHT` centred over its own hours+minutes pair).
pw.Widget _cellHeadingContent(
  _Fonts fonts,
  _HeaderCell cell,
  List<_PhysicalColumn> cellColumns,
  List<double> cellColumnWidths,
) {
  // Smaller than the sub-heading tier below it: a group/cell heading is
  // often several words ("SINGLE-PILOT TIME") squeezed into a narrow
  // column that a single sub-heading word ("PLACE", "SE") never needs to
  // share — 10pt wrapped mid-word ("SINGLE-PILO" / "T") before this was
  // reduced.
  final headingStyle = pw.TextStyle(font: fonts.openSansRegular, fontSize: 6.5);
  final subHeadingStyle = pw.TextStyle(
    font: fonts.openSansRegular,
    fontSize: 9,
  );

  if (cell is _Leaf) {
    return pw.Center(
      child: pw.Padding(
        padding: const pw.EdgeInsets.symmetric(horizontal: 2),
        child: pw.Text(
          cell.heading,
          textAlign: pw.TextAlign.center,
          style: headingStyle,
        ),
      ),
    );
  }

  // Group the physical columns back into their own logical sub-headings,
  // so a duration's hours+minutes pair still shows one centred label.
  final subHeadingGroups = <List<int>>[];
  for (var i = 0; i < cellColumns.length; i++) {
    if (cellColumns[i].isFirstOfSubHeading) {
      subHeadingGroups.add([i]);
    } else {
      subHeadingGroups.last.add(i);
    }
  }

  return pw.Column(
    children: [
      pw.Container(
        height: _headingRowHeight,
        alignment: pw.Alignment.center,
        padding: const pw.EdgeInsets.symmetric(horizontal: 2),
        child: pw.Text(
          cell.heading,
          textAlign: pw.TextAlign.center,
          style: headingStyle,
        ),
      ),
      pw.Divider(height: 1, thickness: 0.5),
      pw.SizedBox(
        height: _subHeaderRowHeight - 1,
        child: pw.Row(
          children: [
            for (final group in subHeadingGroups)
              pw.Container(
                width: [
                  for (final i in group) cellColumnWidths[i],
                ].fold<double>(0.0, (a, b) => a + b),
                alignment: pw.Alignment.center,
                decoration: group.first == 0
                    ? null
                    : const pw.BoxDecoration(
                        border: pw.Border(left: _mediumBorderSide),
                      ),
                child: pw.Text(
                  cellColumns[group.first].subHeadingLabel ?? '',
                  textAlign: pw.TextAlign.center,
                  style: subHeadingStyle,
                ),
              ),
          ],
        ),
      ),
    ],
  );
}

/// The repeating column header for one page's groups: a bare group-number
/// row over the heading/sub-heading row, each cell genuinely spanning its
/// own physical columns.
pw.Widget _headingBand(
  _Fonts fonts,
  List<_ColumnGroup> groups,
  List<double> widths,
  List<_PhysicalColumn> columns,
) {
  final cellWidgets = <pw.Widget>[];
  var index = 0;
  for (final group in groups) {
    for (final cell in group.cells) {
      final count = _cellLeafCount(cell);
      final cellColumns = columns.sublist(index, index + count);
      final cellWidths = widths.sublist(index, index + count);
      final cellWidth = cellWidths.fold<double>(0, (a, b) => a + b);
      cellWidgets.add(
        pw.Container(
          width: cellWidth,
          height: _headingRowHeight + _subHeaderRowHeight,
          decoration: const pw.BoxDecoration(
            border: pw.Border.fromBorderSide(_mediumBorderSide),
          ),
          child: _cellHeadingContent(fonts, cell, cellColumns, cellWidths),
        ),
      );
      index += count;
    }
  }
  return pw.Row(children: cellWidgets);
}

/// [minHeight] is a *shared* row height, not a per-cell default — see
/// [_entryRowHeights]: page-one and page-two are built as two separate
/// `pw.Table`s, so without a height computed once (from whichever page's
/// content needs it, in practice only page-two's REMARKS AND
/// ENDORSEMENTS column ever wraps) and applied to both, a long remark
/// would grow that row on page-two alone and the facing pages would fall
/// out of alignment for every entry after it.
pw.Widget _dataCell(
  _Fonts fonts,
  String text,
  double width, {
  required pw.Border border,
  required double minHeight,
}) => pw.Container(
  width: width,
  constraints: pw.BoxConstraints(minHeight: minHeight),
  alignment: pw.Alignment.center,
  padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2),
  decoration: pw.BoxDecoration(border: border),
  child: pw.Text(
    text,
    textAlign: pw.TextAlign.center,
    style: pw.TextStyle(font: fonts.monospace, fontSize: _dataCellFontSize),
  ),
);

/// `HH:MM`, or blank for a zero duration — the printed sheet leaves a
/// column empty when nothing applies, matching how a paper logbook is
/// actually filled in (a pilot writes `1:30`, not `0:00`, for the
/// columns that don't apply to a given flight).
String _duration(FlightDuration value) =>
    value.inMinutes == 0 ? '' : value.toHoursMinutes();

/// The hours and minutes halves of [value]'s printed `HH:MM`, as the two
/// physical columns a duration leaf always splits into — `['', '']` for
/// a zero duration, matching [_duration]'s own "blank, not `0:00`" rule.
List<String> _durationParts(FlightDuration value) {
  final formatted = _duration(value);
  if (formatted.isEmpty) return ['', ''];
  final parts = formatted.split(':');
  return [parts[0], parts[1]];
}

/// Group 5's `SE`/`ME` sub-columns mark *which* applies rather than
/// repeating a duration already shown in full under `TOTAL TIME OF
/// FLIGHT` — the real published template ticks one of the two, exactly
/// as `MULTI-PILOT TIME` (which has no such duplicate elsewhere) still
/// prints its own duration. `X`, not the Unicode check mark: the default
/// Helvetica/Type1 font this document uses has no Unicode glyphs (it is
/// WinAnsi-encoded, 0-255 only — see the "has no Unicode support" note
/// `package:pdf` itself prints), so `✓` would render as a missing glyph
/// rather than a tick.
String _tick(FlightDuration value) => value.inMinutes == 0 ? '' : 'X';

/// Group 12's printed text: [row]'s own remarks, plus
/// [Amc1Fcl050Row.countersignature] (#78) on its own line when present —
/// sharing the one free-text cell rather than a separate structural
/// space, per `docs/amc1-fcl050-layout.md` §5. No leading blank line when
/// [Amc1Fcl050Row.remarks] is itself empty.
String _remarksCellText(Amc1Fcl050Row row) {
  final countersignature = row.countersignature;
  if (countersignature == null) return row.remarks;
  if (row.remarks.isEmpty) return countersignature;
  return '${row.remarks}\n$countersignature';
}

/// Groups 1–8's sixteen physical columns for one flight [row], as plain
/// strings in print order — public so a test can assert the field-to-
/// column mapping directly, without parsing rendered PDF content back
/// out. `SE`/`ME` are ticks ([_tick]); `MULTI-PILOT TIME` and `TOTAL TIME
/// OF FLIGHT` each split into two entries, hours then minutes
/// ([_durationParts]).
List<String> amc1Fcl050PageOneCellValues(Amc1Fcl050Row row) => [
  row.date,
  row.departurePlace,
  row.departureTime,
  row.arrivalPlace,
  row.arrivalTime,
  row.aircraftMakeModelVariant,
  row.aircraftRegistration,
  _tick(row.singlePilotSingleEngine),
  _tick(row.singlePilotMultiEngine),
  ..._durationParts(row.multiPilotTime),
  ..._durationParts(row.totalTimeOfFlight),
  row.namesPic,
  row.landingsDay == 0 ? '' : row.landingsDay.toString(),
  row.landingsNight == 0 ? '' : row.landingsNight.toString(),
];

/// Groups 9–12's seventeen physical columns for one flight [row], as
/// plain strings — see [amc1Fcl050PageOneCellValues]. Group 11 (FSTD
/// session) is always blank, since [row] never carries FSTD data
/// (`Amc1Fcl050Row`'s own dartdoc: no data model exists yet for #28).
List<String> amc1Fcl050PageTwoCellValues(Amc1Fcl050Row row) => [
  ..._durationParts(row.operationalNight),
  ..._durationParts(row.operationalIfr),
  ..._durationParts(row.pilotFunctionPic),
  ..._durationParts(row.pilotFunctionCoPilot),
  ..._durationParts(row.pilotFunctionDual),
  ..._durationParts(row.pilotFunctionInstructor),
  '', // FSTD date — no session data yet (#28).
  '', // FSTD type.
  '', '', // FSTD total time of session, hours/minutes.
  _remarksCellText(row),
];

/// Groups 1–8's physical columns for one flight row, or a blank row when
/// [row] is null — padding a short page to [_rowsPerEntryPage] rows, per
/// #76's own print-review instruction that the grid always fills the
/// page rather than shrinking to fit the data. [topWeight]/[bottomWeight]
/// are medium at the header/body and body/totals-band boundaries, thin
/// between ordinary entry rows — see [_rowCellBorder].
List<pw.Widget> _pageOneDataCells(
  _Fonts fonts,
  List<double> widths,
  List<pw.BorderSide> boundaries,
  Amc1Fcl050Row? row, {
  required pw.BorderSide topWeight,
  required pw.BorderSide bottomWeight,
  required double rowHeight,
}) {
  final values = row == null
      ? List.filled(widths.length, '')
      : amc1Fcl050PageOneCellValues(row);
  return [
    for (var i = 0; i < widths.length; i++)
      _dataCell(
        fonts,
        values[i],
        widths[i],
        border: _rowCellBorder(
          boundaries,
          i,
          topWeight: topWeight,
          bottomWeight: bottomWeight,
        ),
        minHeight: rowHeight,
      ),
  ];
}

/// Groups 9–12's physical columns for one flight row, or blank — see
/// [_pageOneDataCells].
List<pw.Widget> _pageTwoDataCells(
  _Fonts fonts,
  List<double> widths,
  List<pw.BorderSide> boundaries,
  Amc1Fcl050Row? row, {
  required pw.BorderSide topWeight,
  required pw.BorderSide bottomWeight,
  required double rowHeight,
}) {
  final values = row == null
      ? List.filled(widths.length, '')
      : amc1Fcl050PageTwoCellValues(row);
  return [
    for (var i = 0; i < widths.length; i++)
      _dataCell(
        fonts,
        values[i],
        widths[i],
        border: _rowCellBorder(
          boundaries,
          i,
          topWeight: topWeight,
          bottomWeight: bottomWeight,
        ),
        minHeight: rowHeight,
      ),
  ];
}

/// The number of wrapped lines [text] takes at [fontSize] within
/// [availableWidth] under [font] — a greedy, space-separated word-wrap
/// mirroring how `pw.Text` itself measures and breaks a line (word
/// widths via [PdfFont.stringMetrics], normalized to the em square and
/// scaled by [fontSize]), used to size a whole entry *row* — see
/// [_entryRowHeights] — before either page's `pw.Table` is built. A
/// single word wider than [availableWidth] is left to overflow its own
/// line rather than force-split, since REMARKS AND ENDORSEMENTS is
/// ordinary prose, not unbroken runs of text.
int _wrappedLineCount(
  PdfFont font,
  String text,
  double fontSize,
  double availableWidth,
) {
  if (text.isEmpty) return 1;
  var lineCount = 0;
  for (final paragraph in text.split('\n')) {
    if (paragraph.isEmpty) {
      lineCount += 1;
      continue;
    }
    final spaceWidth = font.stringMetrics(' ').width * fontSize;
    var linesInParagraph = 1;
    var lineWidth = 0.0;
    for (final word in paragraph.split(' ')) {
      final wordWidth = font.stringMetrics(word).width * fontSize;
      if (lineWidth == 0) {
        lineWidth = wordWidth;
      } else if (lineWidth + spaceWidth + wordWidth <= availableWidth) {
        lineWidth += spaceWidth + wordWidth;
      } else {
        linesInParagraph++;
        lineWidth = wordWidth;
      }
    }
    lineCount += linesInParagraph;
  }
  return lineCount;
}

/// [row]'s own required height — [_dataRowHeight] unless
/// [_remarksCellText] (remarks plus any countersignature line, #78) wraps
/// past one line within [remarksColumnWidth] (REMARKS AND ENDORSEMENTS,
/// page-two's own last column, is the only page-one/page-two cell
/// realistically long enough to wrap). Shared by [_packEntrySpreads] (to
/// decide how many rows fit a page *before* either page is built) and,
/// transitively, by both [_buildEntryPageOne] and [_buildEntryPageTwo]
/// via the heights [_packEntrySpreads] hands them — see [_dataCell]'s own
/// dartdoc for why both pages must agree on one shared value per row
/// rather than each measuring its own content.
double _entryRowHeight(
  PdfFont monospaceFont,
  Amc1Fcl050Row row,
  double remarksColumnWidth,
) {
  final availableWidth = remarksColumnWidth - 4; // _dataCell's own padding.
  final lineHeight = _dataCellFontSize * _textLineHeightFactor;
  final wrapped =
      _wrappedLineCount(
            monospaceFont,
            _remarksCellText(row),
            _dataCellFontSize,
            availableWidth,
          ) *
          lineHeight +
      4; // _dataCell's own vertical padding.
  return wrapped > _dataRowHeight ? wrapped : _dataRowHeight;
}

/// One two-page entry spread's real flights plus the blank rows padding
/// it out to fill the page — see [_packEntrySpreads].
class _EntrySpread {
  const _EntrySpread(this.rows, this.rowHeights);

  final List<Amc1Fcl050Row> rows;
  final List<double> rowHeights;
}

/// Packs [rows] into two-page entry spreads by each spread's own entry-row
/// height *budget* — the usable page height minus the fixed header,
/// bottom-band and footer heights — rather than a fixed row count that
/// assumes every row is [_dataRowHeight] tall. A row grown by a long
/// remark (see [_entryRowHeight]) eats into that budget like any other
/// row, so the grid this spread renders never overruns the physical page
/// and pushes the totals/certification band (`docs/amc1-fcl050-
/// layout.md` §3-4, required on *every* page) or the page-number footer
/// off the bottom edge — the bug a fixed count produced. Each spread is
/// padded with blank [_dataRowHeight] rows to
/// fill whatever budget its real rows didn't use, per #76's own
/// print-review instruction that the grid always fills the page. An
/// empty [rows] still produces exactly one blank spread. A single row
/// whose own required height exceeds the *entire* budget is still given
/// a spread of its own rather than dropped — flowing one remark's text
/// across multiple pages is out of scope here.
List<_EntrySpread> _packEntrySpreads(
  List<Amc1Fcl050Row> rows,
  PdfFont monospaceFont,
  double remarksColumnWidth,
) {
  final usableHeight = _pageFormat.landscape.height - _pageMargin * 2;
  final budget =
      usableHeight - _headerHeight - _bottomBandHeight - _footerHeight;

  final spreads = <_EntrySpread>[];
  var currentRows = <Amc1Fcl050Row>[];
  var currentHeights = <double>[];
  var currentHeight = 0.0;

  void closeSpread() {
    final remaining = budget - currentHeight;
    final padding = remaining > 0 ? (remaining / _dataRowHeight).floor() : 0;
    spreads.add(
      _EntrySpread(List.of(currentRows), [
        ...currentHeights,
        for (var i = 0; i < padding; i++) _dataRowHeight,
      ]),
    );
    currentRows = [];
    currentHeights = [];
    currentHeight = 0.0;
  }

  for (final row in rows) {
    final rowHeight = _entryRowHeight(monospaceFont, row, remarksColumnWidth);
    if (currentRows.isNotEmpty && currentHeight + rowHeight > budget) {
      closeSpread();
    }
    currentRows.add(row);
    currentHeights.add(rowHeight);
    currentHeight += rowHeight;
  }
  closeSpread();

  return spreads;
}

/// One two-page entry spread's own running totals (#77): [thisPage] sums
/// only [rows] — the flights printed on this spread — [broughtForward] is
/// the running total accumulated over every *prior* spread ([zero
/// Amc1Fcl050Totals] on the first, since an opening balance from a prior
/// paper logbook is issue #81's job, not this one's), and [totalToDate]
/// is their sum. Public so a test can assert reconciliation directly
/// against plain Dart values, without parsing rendered PDF content back
/// out.
class Amc1Fcl050SpreadTotals {
  const Amc1Fcl050SpreadTotals({
    required this.rows,
    required this.thisPage,
    required this.broughtForward,
    required this.totalToDate,
  });

  final List<Amc1Fcl050Row> rows;
  final Amc1Fcl050Totals thisPage;
  final Amc1Fcl050Totals broughtForward;
  final Amc1Fcl050Totals totalToDate;
}

/// Attaches running totals to already-packed [spreads] — a running
/// accumulator makes "brought forward on spread n equals total to date on
/// spread n-1" true *by construction*: each spread's own `totalToDate`
/// (see [Amc1Fcl050SpreadTotals]) becomes the very next spread's
/// `broughtForward`, rather than being re-derived and checked after the
/// fact.
List<Amc1Fcl050SpreadTotals> _spreadTotals(
  List<_EntrySpread> spreads, {
  Amc1Fcl050Totals openingBalance = Amc1Fcl050Totals.zero,
}) {
  var broughtForward = openingBalance;
  final results = <Amc1Fcl050SpreadTotals>[];
  for (final spread in spreads) {
    final thisPage = Amc1Fcl050Totals.fromRows(spread.rows);
    final totalToDate = broughtForward + thisPage;
    results.add(
      Amc1Fcl050SpreadTotals(
        rows: spread.rows,
        thisPage: thisPage,
        broughtForward: broughtForward,
        totalToDate: totalToDate,
      ),
    );
    broughtForward = totalToDate;
  }
  return results;
}

/// [rows] split into the same two-page entry spreads
/// [buildAmc1Fcl050Logbook] renders, each with its own running totals —
/// see [_spreadTotals]. Async only because pagination needs a [PdfFont]
/// for remarks text-wrap measurement, exactly like [_packEntrySpreads]
/// itself; this function does not render or return any PDF bytes.
Future<List<Amc1Fcl050SpreadTotals>> amc1Fcl050SpreadTotals(
  List<Amc1Fcl050Row> rows, {
  Amc1Fcl050Totals openingBalance = Amc1Fcl050Totals.zero,
}) async {
  final document = pw.Document();
  final monospaceFont = PdfFont.courier(document.document);
  final remarksColumnWidth = _columnWidths(_pageTwoGroups).last;
  final spreads = _packEntrySpreads(rows, monospaceFont, remarksColumnWidth);
  return _spreadTotals(spreads, openingBalance: openingBalance);
}

/// Groups 1–4's seven physical columns (DATE, DEPARTURE, ARRIVAL,
/// AIRCRAFT) split the way the reference logbook design splits them in
/// the bottom band: the leading [_bottomBandBlankColumnCount] (DATE,
/// DEPARTURE's PLACE and TIME, ARRIVAL's PLACE) stay blank across all
/// three total rows — one merged box, since nothing in them is ever
/// totalled — and the row's own label sits in the
/// [_bottomBandLabelColumnCount] after that (ARRIVAL's TIME, AIRCRAFT's
/// MAKE/MODEL/VARIANT and REGISTRATION), matching
/// `docs/amc1-fcl050-layout.md` §3's "rendered in the time columns"
/// rather than starting at DATE.
const _bottomBandBlankColumnCount = 4;
const _bottomBandLabelColumnCount = 3;

const _bottomBandLabels = [
  'TOTAL THIS PAGE',
  'TOTAL FROM PREVIOUS PAGES',
  'TOTAL TIME',
];

/// One structure-only cell of the totals band — blank (for #77 to fill
/// with a real figure later) unless [text] is given. [rowIndex] picks
/// this row's own top/bottom divider weight: medium at the very top (the
/// grid/totals-band boundary) and very bottom (the table's own bottom
/// edge), thin between the three total rows themselves — the same
/// convention [_pageOneDataCells] uses for the grid above.
pw.Widget _bottomBandCell(
  _Fonts fonts,
  List<pw.BorderSide> boundaries,
  int columnIndex,
  double width,
  int rowIndex, {
  String? text,
}) => pw.Container(
  width: width,
  height: _totalsRowHeight,
  decoration: pw.BoxDecoration(
    border: _rowCellBorder(
      boundaries,
      columnIndex,
      topWeight: rowIndex == 0 ? _mediumBorderSide : _thinBorderSide,
      bottomWeight: rowIndex == _bottomBandRowCount - 1
          ? _mediumBorderSide
          : _thinBorderSide,
    ),
  ),
  child: text == null
      ? null
      : pw.Padding(
          padding: const pw.EdgeInsets.only(left: 3),
          child: pw.Align(
            alignment: pw.Alignment.centerLeft,
            child: pw.Text(
              text,
              style: pw.TextStyle(
                font: fonts.openSansRegular,
                fontSize: _totalsFontSize,
              ),
            ),
          ),
        ),
);

/// The three-row totals grid for [gridWidths]/[gridColumns] — either the
/// plain uniform grid (right-hand page, [withLabels] false: every column
/// shows its own [rowValues] figure, one row per entry in
/// [_bottomBandLabels]) or the left-hand page's split layout: a single
/// box spanning all three rows across [_bottomBandBlankColumnCount]
/// leading columns (nothing to total there, so no per-row division), each
/// row's own label across the next [_bottomBandLabelColumnCount], and the
/// remaining columns showing their own [rowValues] figure. [rowValues] is
/// [_bottomBandRowCount] lists (`TOTAL THIS PAGE` / `TOTAL FROM PREVIOUS
/// PAGES` / `TOTAL TIME`, in that order — #77), each already shaped like
/// [gridColumns] by `amc1Fcl050Page{One,Two}TotalsValues`; an empty
/// string leaves a column blank rather than printing nothing visibly
/// different from a real blank.
pw.Widget _totalsGrid(
  _Fonts fonts,
  List<double> gridWidths,
  List<_PhysicalColumn> gridColumns,
  List<List<String>> rowValues, {
  required bool withLabels,
}) {
  final boundaries = _columnBoundaries(gridColumns);
  String? valueAt(int r, int i) =>
      rowValues[r][i].isEmpty ? null : rowValues[r][i];

  if (!withLabels) {
    return pw.Column(
      children: [
        for (var r = 0; r < _bottomBandRowCount; r++)
          pw.Row(
            children: [
              for (var i = 0; i < gridWidths.length; i++)
                _bottomBandCell(
                  fonts,
                  boundaries,
                  i,
                  gridWidths[i],
                  r,
                  text: valueAt(r, i),
                ),
            ],
          ),
      ],
    );
  }

  final blankWidth = gridWidths
      .take(_bottomBandBlankColumnCount)
      .fold<double>(0, (a, b) => a + b);
  final labelWidth = gridWidths
      .skip(_bottomBandBlankColumnCount)
      .take(_bottomBandLabelColumnCount)
      .fold<double>(0, (a, b) => a + b);

  final blankBlock = pw.Container(
    width: blankWidth,
    height: _bottomBandHeight,
    decoration: const pw.BoxDecoration(
      border: pw.Border.fromBorderSide(_mediumBorderSide),
    ),
  );

  final labelColumnStart = _bottomBandBlankColumnCount;
  final restColumnStart =
      _bottomBandBlankColumnCount + _bottomBandLabelColumnCount;

  final labelBlock = pw.Column(
    children: [
      for (var r = 0; r < _bottomBandRowCount; r++)
        _bottomBandCell(
          fonts,
          boundaries,
          labelColumnStart,
          labelWidth,
          r,
          text: _bottomBandLabels[r],
        ),
    ],
  );

  final restBlock = pw.Column(
    children: [
      for (var r = 0; r < _bottomBandRowCount; r++)
        pw.Row(
          children: [
            for (var i = restColumnStart; i < gridWidths.length; i++)
              _bottomBandCell(
                fonts,
                boundaries,
                i,
                gridWidths[i],
                r,
                text: valueAt(r, i),
              ),
          ],
        ),
    ],
  );

  return pw.Row(children: [blankBlock, labelBlock, restBlock]);
}

/// The whole `docs/amc1-fcl050-layout.md` §4 certification block, as one
/// piece: the statement at top, blank room to actually sign, a drawn
/// signature line, and the `PILOT'S SIGNATURE` label beneath it — matched
/// against a reference transcript of the real published template during
/// #76's review, which merges all of this into a *single* remarks-column
/// cell spanning [_bottomBandHeight] (every totals row's combined
/// height), not a separately-sized band of its own. `Ubuntu`, 9pt — the
/// reference's own explicit choice for this text, distinct from every
/// other label on the page.
pw.Widget _certificationBlock(_Fonts fonts) {
  final style = pw.TextStyle(font: fonts.ubuntuRegular, fontSize: 9);
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'I certify that the entries in this log are true.',
          style: style,
        ),
        pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: [
            pw.Container(
              height: 1,
              decoration: const pw.BoxDecoration(
                border: pw.Border(bottom: _thinBorderSide),
              ),
            ),
            pw.SizedBox(height: 2),
            pw.Text("PILOT'S SIGNATURE", style: style),
          ],
        ),
      ],
    ),
  );
}

/// The three-row band beneath the grid — see [_bottomBandRowCount]'s own
/// dartdoc for the certification block's merge. [hasRemarksColumn] is
/// true only for the right-hand page, the one page with a column 12 to
/// repurpose; the left-hand page renders the split blank/label layout
/// [_totalsGrid] describes, the right-hand page a uniform grid — both
/// showing [rowValues]' real figures (#77).
pw.Widget _bottomBand(
  _Fonts fonts,
  List<double> widths,
  List<_PhysicalColumn> columns,
  List<List<String>> rowValues, {
  required bool withLabels,
  required bool hasRemarksColumn,
}) {
  final gridWidths = hasRemarksColumn
      ? widths.sublist(0, widths.length - 1)
      : widths;
  final gridColumns = hasRemarksColumn
      ? columns.sublist(0, columns.length - 1)
      : columns;

  final totalsGrid = _totalsGrid(
    fonts,
    gridWidths,
    gridColumns,
    rowValues,
    withLabels: withLabels,
  );

  if (!hasRemarksColumn) return totalsGrid;

  final remarksWidth = widths.last;
  return pw.Row(
    children: [
      totalsGrid,
      pw.Container(
        width: remarksWidth,
        height: _bottomBandHeight,
        decoration: const pw.BoxDecoration(
          border: pw.Border.fromBorderSide(_mediumBorderSide),
        ),
        child: _certificationBlock(fonts),
      ),
    ],
  );
}

/// `Page <pageNumber> of <totalPages>` (#78) — public so a test can assert
/// the format directly, without rendering a document to read it back out.
String amc1Fcl050PageFooterText(int pageNumber, int totalPages) =>
    'Page $pageNumber of $totalPages';

pw.Widget _pageNumberFooter(int pageNumber, int totalPages) => pw.Align(
  alignment: pw.Alignment.bottomRight,
  child: pw.Padding(
    padding: const pw.EdgeInsets.only(top: 4),
    child: pw.Text(
      amc1Fcl050PageFooterText(pageNumber, totalPages),
      style: const pw.TextStyle(fontSize: 8),
    ),
  ),
);

/// Page 1 (`docs/amc1-fcl050-layout.md` §1): the holder's name and
/// licence number, centred, alone on their own page — matching the real
/// published template's own front matter exactly, rather than sharing a
/// page with the entry table.
pw.Page _buildFrontMatterPage({
  required String holderName,
  required String holderLicenceNumber,
  required int pageNumber,
  required int totalPages,
}) => pw.Page(
  pageFormat: _pageFormat.landscape,
  margin: const pw.EdgeInsets.all(40),
  build: (context) => pw.Column(
    children: [
      pw.Expanded(
        child: pw.Center(
          child: pw.Column(
            mainAxisAlignment: pw.MainAxisAlignment.center,
            children: [
              pw.Text(
                'PILOT LOGBOOK',
                style: pw.TextStyle(
                  fontSize: 20,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              pw.SizedBox(height: 60),
              pw.Text(
                "Holder's name(s)          $holderName",
                style: const pw.TextStyle(fontSize: 12),
              ),
              pw.SizedBox(height: 40),
              pw.Text(
                "Holder's licence number          $holderLicenceNumber",
                style: const pw.TextStyle(fontSize: 12),
              ),
            ],
          ),
        ),
      ),
      _pageNumberFooter(pageNumber, totalPages),
    ],
  ),
);

/// One of the six address blocks on page 2 — three blank rules to write
/// on, captioned `[space for address change]` for every block but the
/// first (the original address, per `docs/amc1-fcl050-layout.md` §1).
/// This app has no stored pilot address (out of scope for #76), so every
/// block renders blank, same as the official template's own unfilled
/// form.
pw.Widget _addressBlock({required bool showChangeCaption}) => pw.Padding(
  padding: const pw.EdgeInsets.all(10),
  child: pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.stretch,
    children: [
      for (var i = 0; i < 3; i++)
        pw.Container(
          margin: const pw.EdgeInsets.only(bottom: 16),
          decoration: const pw.BoxDecoration(
            border: pw.Border(bottom: _thinBorderSide),
          ),
          height: 16,
        ),
      if (showChangeCaption)
        pw.Text(
          '[space for address change]',
          style: pw.TextStyle(fontSize: 8, fontStyle: pw.FontStyle.italic),
        ),
    ],
  ),
);

/// Page 2: `HOLDER'S ADDRESS`, six blocks in a 2×3 grid — a career-long
/// address history the printed template absorbs without a reissue.
pw.Page _buildAddressPage({required int pageNumber, required int totalPages}) =>
    pw.Page(
      pageFormat: _pageFormat.landscape,
      margin: const pw.EdgeInsets.all(30),
      build: (context) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            "HOLDER'S ADDRESS:",
            style: pw.TextStyle(fontSize: 11, fontStyle: pw.FontStyle.italic),
          ),
          pw.SizedBox(height: 8),
          pw.Table(
            columnWidths: const {
              0: pw.FlexColumnWidth(),
              1: pw.FlexColumnWidth(),
            },
            children: [
              pw.TableRow(
                children: [
                  _addressBlock(showChangeCaption: false),
                  _addressBlock(showChangeCaption: true),
                ],
              ),
              pw.TableRow(
                children: [
                  _addressBlock(showChangeCaption: true),
                  _addressBlock(showChangeCaption: true),
                ],
              ),
              pw.TableRow(
                children: [
                  _addressBlock(showChangeCaption: true),
                  _addressBlock(showChangeCaption: true),
                ],
              ),
            ],
          ),
          pw.Expanded(child: pw.SizedBox()),
          _pageNumberFooter(pageNumber, totalPages),
        ],
      ),
    );

/// The left-hand page of one entry spread: groups 1–8, [pageRows] flights
/// (padded to [_rowsPerEntryPage] with blanks), and the labelled bottom
/// band — see [_bottomBand]'s own dartdoc for why it has no separate
/// certification section of its own.
pw.Page _buildEntryPageOne({
  required _Fonts fonts,
  required List<Amc1Fcl050Row> pageRows,
  required int rowsPerPage,
  required List<double> rowHeights,
  required Amc1Fcl050SpreadTotals spreadTotals,
  required int pageNumber,
  required int totalPages,
}) {
  final columns = _physicalColumns(_pageOneGroups);
  final widths = _columnWidths(_pageOneGroups);
  final boundaries = _columnBoundaries(columns);
  // TOTAL THIS PAGE / TOTAL FROM PREVIOUS PAGES / TOTAL TIME, in that
  // order — matching [_bottomBandLabels].
  final totalsRowValues = [
    amc1Fcl050PageOneTotalsValues(spreadTotals.thisPage),
    amc1Fcl050PageOneTotalsValues(spreadTotals.broughtForward),
    amc1Fcl050PageOneTotalsValues(spreadTotals.totalToDate),
  ];

  return pw.Page(
    pageFormat: _pageFormat.landscape,
    margin: const pw.EdgeInsets.all(_pageMargin),
    build: (context) => pw.Column(
      children: [
        _numberBand(fonts, widths, columns),
        _headingBand(fonts, _pageOneGroups, widths, columns),
        pw.Table(
          columnWidths: _tableColumnWidths(widths),
          children: [
            for (var i = 0; i < rowsPerPage; i++)
              pw.TableRow(
                children: _pageOneDataCells(
                  fonts,
                  widths,
                  boundaries,
                  i < pageRows.length ? pageRows[i] : null,
                  topWeight: i == 0 ? _mediumBorderSide : _thinBorderSide,
                  bottomWeight: i == rowsPerPage - 1
                      ? _mediumBorderSide
                      : _thinBorderSide,
                  rowHeight: rowHeights[i],
                ),
              ),
          ],
        ),
        _bottomBand(
          fonts,
          widths,
          columns,
          totalsRowValues,
          withLabels: true,
          hasRemarksColumn: false,
        ),
        pw.Expanded(child: pw.SizedBox()),
        _pageNumberFooter(pageNumber, totalPages),
      ],
    ),
  );
}

/// The right-hand page of the same spread: groups 9–12, the same flights'
/// remaining columns, and the unlabelled bottom band (the totals labels
/// live on the facing page) — whose remarks column carries the
/// certification block, printed on every page even unsigned (`docs/amc1-
/// fcl050-layout.md` §4).
pw.Page _buildEntryPageTwo({
  required _Fonts fonts,
  required List<Amc1Fcl050Row> pageRows,
  required int rowsPerPage,
  required List<double> rowHeights,
  required Amc1Fcl050SpreadTotals spreadTotals,
  required int pageNumber,
  required int totalPages,
}) {
  final columns = _physicalColumns(_pageTwoGroups);
  final widths = _columnWidths(_pageTwoGroups);
  final boundaries = _columnBoundaries(columns);
  final totalsRowValues = [
    amc1Fcl050PageTwoTotalsValues(spreadTotals.thisPage),
    amc1Fcl050PageTwoTotalsValues(spreadTotals.broughtForward),
    amc1Fcl050PageTwoTotalsValues(spreadTotals.totalToDate),
  ];

  return pw.Page(
    pageFormat: _pageFormat.landscape,
    margin: const pw.EdgeInsets.all(_pageMargin),
    build: (context) => pw.Column(
      children: [
        _numberBand(fonts, widths, columns),
        _headingBand(fonts, _pageTwoGroups, widths, columns),
        pw.Table(
          columnWidths: _tableColumnWidths(widths),
          children: [
            for (var i = 0; i < rowsPerPage; i++)
              pw.TableRow(
                children: _pageTwoDataCells(
                  fonts,
                  widths,
                  boundaries,
                  i < pageRows.length ? pageRows[i] : null,
                  topWeight: i == 0 ? _mediumBorderSide : _thinBorderSide,
                  bottomWeight: i == rowsPerPage - 1
                      ? _mediumBorderSide
                      : _thinBorderSide,
                  rowHeight: rowHeights[i],
                ),
              ),
          ],
        ),
        _bottomBand(
          fonts,
          widths,
          columns,
          totalsRowValues,
          withLabels: false,
          hasRemarksColumn: true,
        ),
        pw.Expanded(child: pw.SizedBox()),
        _pageNumberFooter(pageNumber, totalPages),
      ],
    ),
  );
}

/// Builds the `AMC1 FCL.050` landscape A4 logbook document (#76): a
/// numbered front-matter page, a numbered address page, then as many
/// numbered two-page entry spreads as [rows] needs — groups 1–8 on the
/// left of each spread, 9–12 on the right, exactly as the real published
/// template lays them out, each spread's grid always filled to its own
/// [_packEntrySpreads] row count regardless of how many flights it holds.
///
/// Running totals (`TOTAL THIS PAGE` / `FROM PREVIOUS PAGES` / `TOTAL
/// TIME`, #77) print real, reconciling figures — see
/// [Amc1Fcl050SpreadTotals] — computed from an opening balance of zero,
/// since carrying one in from a prior paper logbook is issue #81's job.
/// The certification block's wording (#78) is rendered now because the
/// AMC itself requires it on every page regardless of layout concerns;
/// an interactive signature is still out of scope.
///
/// Async: loads and embeds [_Fonts] once per call (see its own dartdoc).
Future<pw.Document> buildAmc1Fcl050Logbook({
  required String holderName,
  required String holderLicenceNumber,
  required List<Amc1Fcl050Row> rows,
  Amc1Fcl050Totals openingBalance = Amc1Fcl050Totals.zero,
}) async {
  final fonts = await _loadFonts();
  final document = pw.Document();
  var pageNumber = 1;

  // Courier's own low-level metrics, not `fonts.monospace` (a `pw.Font`
  // wrapper that only resolves against a page's own build `Context`) —
  // needed up front, before any page is built, to pack spreads and size
  // every row once for both of a spread's pages — see [_packEntrySpreads].
  final monospaceFont = PdfFont.courier(document.document);
  final remarksColumnWidth = _columnWidths(_pageTwoGroups).last;
  final spreads = _packEntrySpreads(rows, monospaceFont, remarksColumnWidth);
  final spreadTotals = _spreadTotals(spreads, openingBalance: openingBalance);
  // Front matter + address, then two pages per spread (#78) — known up
  // front since every spread is already packed before any page is built.
  final totalPages = 2 + spreads.length * 2;

  document.addPage(
    _buildFrontMatterPage(
      holderName: holderName,
      holderLicenceNumber: holderLicenceNumber,
      pageNumber: pageNumber++,
      totalPages: totalPages,
    ),
  );
  document.addPage(
    _buildAddressPage(pageNumber: pageNumber++, totalPages: totalPages),
  );

  for (var s = 0; s < spreads.length; s++) {
    final spread = spreads[s];
    final rowsPerPage = spread.rowHeights.length;
    document.addPage(
      _buildEntryPageOne(
        fonts: fonts,
        pageRows: spread.rows,
        rowsPerPage: rowsPerPage,
        rowHeights: spread.rowHeights,
        spreadTotals: spreadTotals[s],
        pageNumber: pageNumber++,
        totalPages: totalPages,
      ),
    );
    document.addPage(
      _buildEntryPageTwo(
        fonts: fonts,
        pageRows: spread.rows,
        rowsPerPage: rowsPerPage,
        rowHeights: spread.rowHeights,
        spreadTotals: spreadTotals[s],
        pageNumber: pageNumber++,
        totalPages: totalPages,
      ),
    );
  }

  return document;
}
