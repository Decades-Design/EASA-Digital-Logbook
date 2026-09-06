import 'package:drift/drift.dart';

import '../../domain/model/calendar_date.dart';
import '../../domain/model/utc_instant.dart';
import '../../domain/repository/export_record_repository.dart';
import '../database.dart';
import '../ulid.dart';

class DriftExportRecordRepository implements ExportRecordRepository {
  DriftExportRecordRepository(this._db);

  final AppDatabase _db;

  @override
  Future<void> recordExport({
    required String format,
    required CalendarDate from,
    required CalendarDate to,
  }) async {
    await _db
        .into(_db.exportRecordsTable)
        .insert(
          ExportRecordRow(
            id: generateUlid(),
            format: format,
            rangeFrom: from.toString(),
            rangeTo: to.toString(),
            exportedAt: DateTime.now().toUtc().millisecondsSinceEpoch,
          ),
        );
  }

  @override
  Future<List<ExportRecord>> findOverlapping({
    required String format,
    required CalendarDate from,
    required CalendarDate to,
  }) async {
    final rows =
        await (_db.select(_db.exportRecordsTable)
              ..where((t) => t.format.equals(format))
              ..orderBy([(t) => OrderingTerm.desc(t.exportedAt)]))
            .get();

    final overlapping = <ExportRecord>[];
    for (final row in rows) {
      final rowFrom = CalendarDate.parse(row.rangeFrom);
      final rowTo = CalendarDate.parse(row.rangeTo);
      // Two ranges overlap iff each starts on or before the other ends.
      if (from <= rowTo && rowFrom <= to) {
        overlapping.add(
          ExportRecord(
            id: row.id,
            format: row.format,
            from: rowFrom,
            to: rowTo,
            exportedAt: UtcInstant.fromDateTime(
              DateTime.fromMillisecondsSinceEpoch(row.exportedAt, isUtc: true),
            ),
          ),
        );
      }
    }
    return overlapping;
  }
}
