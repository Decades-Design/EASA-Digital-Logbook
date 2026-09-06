import 'package:csv/csv.dart';

import 'generic_csv_field.dart';

/// A named, reusable assignment of this app's canonical fields to a
/// spreadsheet's own column headers (#72) — the acceptance criterion's
/// "mapping saved as a named profile for reuse". Persisted by
/// `CsvMappingProfileRepository`; this class itself is a plain value type
/// with no I/O.
class GenericCsvMapping {
  const GenericCsvMapping({
    required this.name,
    required this.columnByField,
    required this.dateFormat,
    required this.durationFormat,
  });

  final String name;

  /// Canonical field -> the CSV's own header text for it. A field absent
  /// from this map is unmapped — optional fields default to zero/blank;
  /// [requiredGenericCsvFields] must all be present for the mapping to be
  /// usable at all.
  final Map<GenericCsvField, String> columnByField;

  final CsvDateFormat dateFormat;
  final CsvDurationFormat durationFormat;
}

/// Reads just the header row of [csvContent] — #72's "headers detected"
/// criterion. Returns an empty list for an empty file rather than
/// throwing; there's nothing to map either way.
List<String> detectCsvHeaders(String csvContent) {
  final rows = Csv().decode(csvContent);
  if (rows.isEmpty) return const [];
  return rows.first.map((cell) => cell.toString().trim()).toList();
}
