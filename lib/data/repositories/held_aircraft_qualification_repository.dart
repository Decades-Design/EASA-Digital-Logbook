import '../../domain/pilot_record/held_aircraft_qualification.dart' as domain;
import '../database.dart';
import '../mappers/held_qualification_mapper.dart';
import '../ulid.dart';

/// Write and read access to held aircraft-feature qualifications. A
/// current, editable reference record like `aircraft` — no
/// draft/committed lifecycle.
class HeldAircraftQualificationRepository {
  HeldAircraftQualificationRepository(this._db);

  final AppDatabase _db;

  Future<String> upsert(
    domain.HeldAircraftQualification held, {
    String? id,
  }) async {
    final resolvedId = id ?? generateUlid();
    await _db
        .into(_db.heldAircraftQualificationsTable)
        .insertOnConflictUpdate(
          heldAircraftQualificationToRow(held, id: resolvedId),
        );
    return resolvedId;
  }

  Future<domain.HeldAircraftQualification?> find(String id) async {
    final row = await (_db.select(
      _db.heldAircraftQualificationsTable,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : heldAircraftQualificationFromRow(row);
  }

  Future<List<domain.HeldAircraftQualification>> findAll() async {
    final rows = await _db.select(_db.heldAircraftQualificationsTable).get();
    return [for (final row in rows) heldAircraftQualificationFromRow(row)];
  }

  Future<void> delete(String id) => (_db.delete(
    _db.heldAircraftQualificationsTable,
  )..where((t) => t.id.equals(id))).go();
}
