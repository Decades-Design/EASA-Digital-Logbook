import '../model/calendar_date.dart';
import '../model/utc_instant.dart';

/// One completed export — folded into #73 from #70's own leftover
/// acceptance criterion: "a record of what has previously been exported,
/// to warn about overlap." [from]/[to] are the requested export range, not
/// the range of flights it actually contained.
class ExportRecord {
  const ExportRecord({
    required this.id,
    required this.format,
    required this.from,
    required this.to,
    required this.exportedAt,
  });

  final String id;
  final String format;
  final CalendarDate from;
  final CalendarDate to;
  final UtcInstant exportedAt;
}

/// Tracks previous exports so a future one can warn about overlap — #70:
/// "Importing the same file twice into ForeFlight creates duplicates, so
/// exports must be range-scoped." A pilot re-exporting a range they've
/// already exported (and likely already imported into the vendor app)
/// needs to be told that before doing it again, not left to notice only
/// once the vendor app shows duplicates.
abstract class ExportRecordRepository {
  /// Records that an export of [format] covering [from]..[to] just
  /// happened.
  Future<void> recordExport({
    required String format,
    required CalendarDate from,
    required CalendarDate to,
  });

  /// Every previously recorded export of [format] whose range overlaps
  /// [from]..[to], most recent first. Empty when nothing overlaps — never
  /// used to block an export, only to warn before one.
  Future<List<ExportRecord>> findOverlapping({
    required String format,
    required CalendarDate from,
    required CalendarDate to,
  });
}
