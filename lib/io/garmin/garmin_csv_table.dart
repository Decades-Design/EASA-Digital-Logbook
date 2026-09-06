import 'package:csv/csv.dart';

/// Parses a plain single-table Garmin Pilot CSV export (#71) — one header
/// row followed by data rows — into `columnName -> rawValue` maps.
///
/// Unlike ForeFlight's `logbook_template.csv` (#69), which embeds two
/// tables in one file, Garmin exports the aircraft-types table and the
/// flight log as two entirely separate files, each with this same simple
/// shape — so one parser serves both, given the header columns each file
/// is expected to have.
///
/// Throws [FormatException] if the file is empty or missing any of
/// [requiredColumns] — a whole-file problem (wrong export entirely), not a
/// per-row one.
List<Map<String, String>> parseGarminCsvTable(
  String csvContent, {
  required List<String> requiredColumns,
  required String formatDescription,
}) {
  final allRows = Csv().decode(csvContent);
  if (allRows.isEmpty) {
    throw FormatException(
      'Empty file — this does not look like $formatDescription.',
    );
  }

  final headerNames = allRows.first
      .map((cell) => cell.toString().trim())
      .toList();
  for (final column in requiredColumns) {
    if (!headerNames.contains(column)) {
      throw FormatException(
        'No "$column" column found — this does not look like $formatDescription.',
      );
    }
  }

  final rows = <Map<String, String>>[];
  for (final row in allRows.skip(1)) {
    if (row.every((cell) => cell.toString().trim().isEmpty)) continue;
    final map = <String, String>{};
    for (var i = 0; i < headerNames.length; i++) {
      map[headerNames[i]] = i < row.length ? row[i].toString().trim() : '';
    }
    rows.add(map);
  }

  return rows;
}
