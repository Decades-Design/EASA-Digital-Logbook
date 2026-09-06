import 'package:drift/drift.dart';

/// One saved generic-CSV column mapping (#72) — "mapping saved as a named
/// profile for reuse". [columnByField] is JSON, `Map<String, String>`
/// keyed by `GenericCsvField.name`: a small, evolving enum is easier to
/// keep in sync with a single JSON blob than with one nullable TEXT column
/// per field, and nothing here ever queries a single mapped column
/// individually. No lifecycle beyond plain CRUD — a mapping profile is
/// reference data, like `Aircraft`, not a `Flight`.
@DataClassName('CsvMappingProfileRow')
class CsvMappingProfilesTable extends Table {
  @override
  String get tableName => 'csv_mapping_profiles';

  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get columnByField => text()();
  TextColumn get dateFormat => text()();
  TextColumn get durationFormat => text()();

  @override
  Set<Column> get primaryKey => {id};
}
