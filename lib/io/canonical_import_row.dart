import '../domain/model/aircraft.dart';
import '../domain/model/flight.dart';

/// One flight parsed out of a vendor import file, mapped onto this app's own
/// domain model — [Flight] and [Aircraft] *are* the "canonical internal
/// model" CLAUDE.md's Import/export section requires every adapter to
/// produce (#68). There is no separate, parallel import-only model: raw
/// facts are raw facts regardless of where they came from, and duplicating
/// [Flight]'s field set in a second type would just be two places to keep in
/// sync. This class is the thin envelope an adapter wraps a mapped flight in
/// — the metadata needed to review and write it, not a reinterpretation of
/// it.
class CanonicalImportRow {
  const CanonicalImportRow({
    required this.sourceRowNumber,
    required this.flight,
    required this.aircraft,
    this.unmappedFields = const {},
    this.reviewNotes = const [],
  });

  /// 1-based position in the source file. The preview step (#73) and any
  /// per-row error report point back to this, not a database id — nothing
  /// has been written yet when this row is produced.
  final int sourceRowNumber;

  final Flight flight;

  /// Not yet resolved against `AircraftRepository`. **Adapters have no
  /// knowledge of the database** (this issue's own acceptance criterion) —
  /// turning this into a stored aircraft id (reusing an existing
  /// registration or creating a new record) is the import pipeline's job,
  /// the same way `NewFlightScreen._resolveAircraftId` already does it for
  /// a hand-entered flight.
  final Aircraft aircraft;

  /// Vendor fields with no home on [Flight] or [Aircraft] — preserved
  /// verbatim as `column label -> raw value`, so [mergeUnmappedFieldsIntoRemarks]
  /// can fold them into [Flight.remarks] rather than dropping them.
  /// CLAUDE.md: "Silently dropping a field the user has been maintaining
  /// for a decade is the worst possible import outcome."
  final Map<String, String> unmappedFields;

  /// Plain-language notes about a row this adapter could not map with full
  /// confidence — a default it had to guess at, an ambiguous type
  /// designator, anything the preview step (#73) should surface before the
  /// pilot commits to importing it. Never used to *block* the import, the
  /// same non-blocking spirit as #105's qualification-gap warning.
  final List<String> reviewNotes;
}

/// Folds [unmappedFields] into [remarks] as human-readable `label: value`
/// lines, preserving whatever the vendor tracked that this app has no raw
/// fact for. CLAUDE.md is explicit that dropping it silently is the worst
/// possible import outcome — this is the one place that promise is kept.
///
/// A no-op (returns [remarks] unchanged) when there is nothing to fold in,
/// or when every unmapped value is blank — a vendor's own CSV frequently
/// carries an empty column for every row, and an empty column contributes
/// nothing worth preserving.
String mergeUnmappedFieldsIntoRemarks(
  String remarks,
  Map<String, String> unmappedFields,
) {
  final lines = [
    for (final entry in unmappedFields.entries)
      if (entry.value.trim().isNotEmpty) '${entry.key}: ${entry.value.trim()}',
  ];
  if (lines.isEmpty) return remarks;

  final appended = lines.join('; ');
  return remarks.isEmpty ? appended : '$remarks — $appended';
}
