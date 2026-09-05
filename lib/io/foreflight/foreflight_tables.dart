import 'package:csv/csv.dart';

/// The two embedded tables ForeFlight's `logbook_template.csv` always
/// contains, in order — Aircraft, then Flights (#69) — each row already
/// zipped against its own table's header into a `columnName -> rawValue`
/// map. Values are plain strings, untouched; interpreting them (parsing a
/// duration, classifying a capacity) is the mapper's job, not this file's.
class ForeFlightTables {
  const ForeFlightTables({
    required this.aircraftRows,
    required this.flightRows,
    required this.flightDataStartLine,
  });

  final List<Map<String, String>> aircraftRows;
  final List<Map<String, String>> flightRows;

  /// 1-based position of the first row in [flightRows] within the
  /// *decoded* file — not an index into [flightRows] itself, which knows
  /// nothing about the aircraft table or header rows preceding it, and not
  /// necessarily the exact line number in a text editor: `package:csv`
  /// drops fully-blank lines (the separators between the preamble, the
  /// aircraft table and the flights table) rather than emitting an empty
  /// row for them, so this undercounts the true file line by however many
  /// blank separator lines preceded it. Close enough for a pilot to find
  /// the right row by counting, not a byte-exact file offset.
  final int flightDataStartLine;
}

/// Marks the start of the aircraft table. ForeFlight always emits this
/// exact text in the first cell of its own header row.
const _aircraftTableMarker = 'Aircraft Table';

/// Marks the start of the flights table. Observed with a trailing space in
/// real exports (`'Flights Table '`) — matched by prefix, not equality, so
/// a version without the trailing space still works.
const _flightsTableMarkerPrefix = 'Flights Table';

/// Splits [csvContent] into its two embedded tables.
///
/// Throws [FormatException] if either table marker is missing — a file
/// that doesn't have this shape at all is not a ForeFlight export, and
/// silently returning an empty result would look like "nothing to
/// import" rather than "this isn't the right file".
ForeFlightTables parseForeFlightTables(String csvContent) {
  final allRows = Csv().decode(csvContent);

  final aircraftMarkerIndex = allRows.indexWhere(
    (row) =>
        row.isNotEmpty && row.first.toString().trim() == _aircraftTableMarker,
  );
  if (aircraftMarkerIndex == -1) {
    throw const FormatException(
      'No "Aircraft Table" marker found — this does not look like a '
      "ForeFlight logbook_template.csv export.",
    );
  }

  final flightsMarkerIndex = allRows.indexWhere(
    (row) =>
        row.isNotEmpty &&
        row.first.toString().trimRight().startsWith(_flightsTableMarkerPrefix),
    aircraftMarkerIndex + 1,
  );
  if (flightsMarkerIndex == -1) {
    throw const FormatException(
      'No "Flights Table" marker found after the aircraft table — this '
      "does not look like a complete ForeFlight logbook_template.csv "
      'export.',
    );
  }

  final aircraftHeaderRow = allRows[aircraftMarkerIndex + 1];
  final aircraftDataRows = allRows.sublist(
    aircraftMarkerIndex + 2,
    flightsMarkerIndex,
  );

  final flightsHeaderRow = allRows[flightsMarkerIndex + 1];
  final flightDataRows = allRows.sublist(flightsMarkerIndex + 2);

  return ForeFlightTables(
    aircraftRows: _zipRows(aircraftHeaderRow, aircraftDataRows),
    flightRows: _zipRows(flightsHeaderRow, flightDataRows),
    // +1 for 1-based, +1 to move past the flights header row itself.
    flightDataStartLine: flightsMarkerIndex + 2 + 1,
  );
}

bool _isBlankRow(List<dynamic> row) =>
    row.every((cell) => cell.toString().trim().isEmpty);

/// Zips each data row against [header] into a `columnName -> value` map,
/// stopping at a blank row (both tables are padded to a shared column
/// width with a blank separator row between them, not a fixed row count).
List<Map<String, String>> _zipRows(
  List<dynamic> header,
  List<List<dynamic>> dataRows,
) {
  final headerNames = header.map((cell) => cell.toString().trim()).toList();
  final rows = <Map<String, String>>[];

  for (final row in dataRows) {
    if (_isBlankRow(row)) break;
    final map = <String, String>{};
    for (var i = 0; i < headerNames.length; i++) {
      map[headerNames[i]] = i < row.length ? row[i].toString().trim() : '';
    }
    rows.add(map);
  }

  return rows;
}
