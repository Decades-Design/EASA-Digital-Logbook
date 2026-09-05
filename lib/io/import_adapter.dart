import 'canonical_import_row.dart';

/// One source row an [ImportAdapter] could not turn into a
/// [CanonicalImportRow] — #74's own home for *why* a row wasn't imported,
/// not just that it wasn't. [rowNumber] is 1-based, matching
/// [CanonicalImportRow.sourceRowNumber] so a report can point back to the
/// exact line in the file the pilot opened it from.
class ImportRowError {
  const ImportRowError({required this.rowNumber, required this.message});

  final int rowNumber;
  final String message;

  @override
  String toString() => 'row $rowNumber: $message';
}

/// Everything one call to [ImportAdapter.parse] produced: every row it
/// could map, and every row it couldn't, with why. Never partial for one
/// row — a row that fails validation is entirely in [errors], never
/// half-populated in [rows] (#74: "per-row validation with no silent
/// coercion").
class ImportParseResult {
  const ImportParseResult({required this.rows, required this.errors});

  final List<CanonicalImportRow> rows;
  final List<ImportRowError> errors;

  bool get hasErrors => errors.isNotEmpty;
}

/// What every vendor-specific importer (#69 ForeFlight, #71 Garmin, #72
/// generic CSV) implements.
///
/// Pure and synchronous on purpose: an adapter **has no knowledge of the
/// database** (this issue's own acceptance criterion) — it turns file
/// content into an [ImportParseResult] and nothing else. Resolving an
/// aircraft registration to a stored id, detecting duplicates (#75), and
/// actually writing anything are the import pipeline's job, layered on top
/// of this, never the adapter's own.
abstract class ImportAdapter {
  /// A short, human-readable name for this format, shown in the import
  /// picker UI — e.g. "ForeFlight (logbook_template.csv)".
  String get displayName;

  ImportParseResult parse(String source);
}
