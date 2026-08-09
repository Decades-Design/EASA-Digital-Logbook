import '../../domain/model/aircraft.dart' as domain;
import '../database.dart';
import '../mappers/aircraft_mapper.dart';
import '../ulid.dart';

/// Write access to aircraft reference data. No draft/committed lifecycle —
/// `Aircraft` is "a current, editable reference record," unlike `Flight`.
class AircraftRepository {
  AircraftRepository(this._db);

  final AppDatabase _db;

  /// Inserts a new aircraft (returning its generated id), or replaces the
  /// row and its qualification rows when [id] names one already stored.
  Future<String> upsert(domain.Aircraft aircraft, {String? id}) {
    final resolvedId = id ?? generateUlid();

    return _db.transaction(() async {
      await _db
          .into(_db.aircraftsTable)
          .insertOnConflictUpdate(aircraftToRow(aircraft, id: resolvedId));

      await (_db.delete(
        _db.aircraftQualificationJurisdictionsTable,
      )..where((t) => t.aircraftId.equals(resolvedId))).go();
      await (_db.delete(
        _db.aircraftRequiredQualificationsTable,
      )..where((t) => t.aircraftId.equals(resolvedId))).go();

      for (final entry in aircraft.requiredQualifications.entries) {
        await _db
            .into(_db.aircraftQualificationJurisdictionsTable)
            .insert(
              AircraftQualificationJurisdictionRow(
                aircraftId: resolvedId,
                jurisdictionId: entry.key,
              ),
            );
        for (final qualification in entry.value) {
          await _db
              .into(_db.aircraftRequiredQualificationsTable)
              .insert(
                AircraftRequiredQualificationRow(
                  aircraftId: resolvedId,
                  jurisdictionId: entry.key,
                  qualification: qualification.name,
                ),
              );
        }
      }

      return resolvedId;
    });
  }

  Future<domain.Aircraft?> find(String id) async {
    final row = await (_db.select(
      _db.aircraftsTable,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) {
      return null;
    }

    final jurisdictionRows = await (_db.select(
      _db.aircraftQualificationJurisdictionsTable,
    )..where((t) => t.aircraftId.equals(id))).get();
    final qualificationRows = await (_db.select(
      _db.aircraftRequiredQualificationsTable,
    )..where((t) => t.aircraftId.equals(id))).get();

    final requiredQualifications = <String, Set<domain.AircraftQualification>>{
      for (final j in jurisdictionRows)
        j.jurisdictionId: <domain.AircraftQualification>{},
    };
    for (final q in qualificationRows) {
      requiredQualifications[q.jurisdictionId]!.add(
        domain.AircraftQualification.values.byName(q.qualification),
      );
    }

    return aircraftFromRow(row, requiredQualifications);
  }

  Future<void> delete(String id) =>
      (_db.delete(_db.aircraftsTable)..where((t) => t.id.equals(id))).go();
}
