import 'dart:convert';

import '../../io/generic_csv/generic_csv_field.dart';
import '../../io/generic_csv/generic_csv_mapping.dart';
import '../database.dart';
import '../ulid.dart';

/// A saved mapping plus the id it's stored under — mirrors
/// `AircraftRepository`'s own `AircraftRecord` for the same reason: a
/// management screen listing every saved profile needs the id back too, to
/// edit or delete the one a pilot taps.
class CsvMappingProfileRecord {
  const CsvMappingProfileRecord({required this.id, required this.mapping});

  final String id;
  final GenericCsvMapping mapping;
}

/// Write and read access to saved generic-CSV mappings (#72). No
/// draft/committed lifecycle — a mapping is a current, editable reference
/// record, like `AircraftRepository`'s `Aircraft`.
class CsvMappingProfileRepository {
  CsvMappingProfileRepository(this._db);

  final AppDatabase _db;

  /// Inserts a new mapping (returning its generated id), or replaces the
  /// row when [id] names one already stored.
  Future<String> upsert(GenericCsvMapping mapping, {String? id}) async {
    final resolvedId = id ?? generateUlid();
    await _db
        .into(_db.csvMappingProfilesTable)
        .insertOnConflictUpdate(
          CsvMappingProfileRow(
            id: resolvedId,
            name: mapping.name,
            columnByField: jsonEncode({
              for (final entry in mapping.columnByField.entries)
                entry.key.name: entry.value,
            }),
            dateFormat: mapping.dateFormat.name,
            durationFormat: mapping.durationFormat.name,
          ),
        );
    return resolvedId;
  }

  Future<GenericCsvMapping?> find(String id) async {
    final row = await (_db.select(
      _db.csvMappingProfilesTable,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : _fromRow(row);
  }

  /// Every saved mapping, in no particular order — a picker screen sorts
  /// however it likes (by name, most recently used, ...); nothing here
  /// tracks usage recency to sort by.
  Future<List<CsvMappingProfileRecord>> listAll() async {
    final rows = await _db.select(_db.csvMappingProfilesTable).get();
    return [
      for (final row in rows)
        CsvMappingProfileRecord(id: row.id, mapping: _fromRow(row)),
    ];
  }

  Future<void> delete(String id) => (_db.delete(
    _db.csvMappingProfilesTable,
  )..where((t) => t.id.equals(id))).go();

  GenericCsvMapping _fromRow(CsvMappingProfileRow row) {
    final decoded = jsonDecode(row.columnByField) as Map<String, dynamic>;
    return GenericCsvMapping(
      name: row.name,
      columnByField: {
        for (final entry in decoded.entries)
          GenericCsvField.values.byName(entry.key): entry.value as String,
      },
      dateFormat: CsvDateFormat.values.byName(row.dateFormat),
      durationFormat: CsvDurationFormat.values.byName(row.durationFormat),
    );
  }
}
