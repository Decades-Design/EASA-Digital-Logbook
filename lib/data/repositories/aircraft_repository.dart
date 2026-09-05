import 'package:drift/drift.dart';

import '../../domain/model/aircraft.dart' as domain;
import '../database.dart';
import '../mappers/aircraft_mapper.dart';
import '../ulid.dart';

/// An aircraft plus the id it's stored under (#61) — `find`/`upsert` alone
/// are enough for a caller that already knows the id (the entry form
/// resolving a picked registration); a management screen listing every
/// aircraft needs the id back too, to edit or archive the one a pilot taps.
class AircraftRecord {
  const AircraftRecord({required this.id, required this.aircraft});

  final String id;
  final domain.Aircraft aircraft;
}

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

  /// Looks up a stored aircraft's id by its (unique) registration, so a
  /// caller minting a new row for a registration it hasn't seen before
  /// (the entry form's create path) can reuse the existing id instead of
  /// hitting the `registration` unique-constraint violation a blind
  /// `upsert` with a fresh id would throw.
  Future<String?> findIdByRegistration(String registration) async {
    final row =
        await (_db.select(_db.aircraftsTable)
              ..where((t) => t.registration.equals(registration)))
            .getSingleOrNull();
    return row?.id;
  }

  Future<domain.Aircraft?> find(String id) async {
    final row = await (_db.select(
      _db.aircraftsTable,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    if (row == null) {
      return null;
    }
    return _fromRow(row);
  }

  /// Every stored aircraft, active and archived alike (#61) — the
  /// management screen partitions by [domain.Aircraft.archived] itself,
  /// since both groups need to be visible there. Filtering archived ones
  /// out is the entry-form picker's own concern (#58/#61), not this
  /// repository's.
  Stream<List<AircraftRecord>> watchAll() {
    return _db.select(_db.aircraftsTable).watch().asyncMap(
      (rows) async => [
        for (final row in rows)
          AircraftRecord(id: row.id, aircraft: await _fromRow(row)),
      ],
    );
  }

  /// A plain flag flip, not a full [upsert] — an archive/unarchive action
  /// never touches [domain.Aircraft.requiredQualifications], so it skips
  /// upsert's delete-and-reinsert of the qualification child rows for no
  /// reason.
  Future<void> setArchived(String id, bool archived) {
    return (_db.update(
      _db.aircraftsTable,
    )..where((t) => t.id.equals(id))).write(
      AircraftsTableCompanion(archived: Value(archived)),
    );
  }

  Future<domain.Aircraft> _fromRow(AircraftRow row) async {
    final jurisdictionRows = await (_db.select(
      _db.aircraftQualificationJurisdictionsTable,
    )..where((t) => t.aircraftId.equals(row.id))).get();
    final qualificationRows = await (_db.select(
      _db.aircraftRequiredQualificationsTable,
    )..where((t) => t.aircraftId.equals(row.id))).get();

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
