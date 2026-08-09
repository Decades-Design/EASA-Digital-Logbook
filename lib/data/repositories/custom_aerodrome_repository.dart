import '../../domain/model/aerodrome.dart' as domain;
import '../database.dart';
import '../mappers/custom_aerodrome_mapper.dart';
import '../ulid.dart';

/// Write access to pilot-defined aerodromes. Plain reference data, no
/// lifecycle — same shape as [AircraftRepository].
class CustomAerodromeRepository {
  CustomAerodromeRepository(this._db);

  final AppDatabase _db;

  Future<String> upsert(domain.Aerodrome aerodrome, {String? id}) async {
    final resolvedId = id ?? generateUlid();
    await _db
        .into(_db.customAerodromesTable)
        .insertOnConflictUpdate(
          customAerodromeToRow(aerodrome, id: resolvedId),
        );
    return resolvedId;
  }

  Future<domain.Aerodrome?> find(String id) async {
    final row = await (_db.select(
      _db.customAerodromesTable,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : customAerodromeFromRow(row);
  }

  Future<void> delete(String id) => (_db.delete(
    _db.customAerodromesTable,
  )..where((t) => t.id.equals(id))).go();
}
