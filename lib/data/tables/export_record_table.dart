import 'package:drift/drift.dart';

/// One row per completed export — folded into #73 from #70's own leftover
/// acceptance criterion: "a record of what has previously been exported, to
/// warn about overlap." `rangeFrom`/`rangeTo` are `CalendarDate.toString()`
/// (`YYYY-MM-DD`), not epoch millis — an export range is a calendar
/// concept, never an instant (rule 3 is about stored *times*; a date range
/// selection is deliberately compared as dates, not as UTC instants, so a
/// pilot picking "January" means the same thing regardless of what hour
/// they happen to run the export).
@DataClassName('ExportRecordRow')
class ExportRecordsTable extends Table {
  @override
  String get tableName => 'export_records';

  TextColumn get id => text()();

  /// A human-readable label for what was exported, e.g. the exporter's own
  /// format name — supplied by the caller, never hardcoded here (see
  /// `import_batch_table.dart`'s identical note).
  TextColumn get format => text()();

  TextColumn get rangeFrom => text()();
  TextColumn get rangeTo => text()();
  IntColumn get exportedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
