import '../../domain/pilot_record/held_rating.dart' as domain;
import '../database.dart';
import '../mappers/held_qualification_mapper.dart';
import '../ulid.dart';

/// Write and read access to held ratings and certificates. A current,
/// editable reference record like `aircraft` — no draft/committed
/// lifecycle.
class HeldRatingRepository {
  HeldRatingRepository(this._db);

  final AppDatabase _db;

  Future<String> upsert(domain.HeldRating held, {String? id}) async {
    final resolvedId = id ?? generateUlid();
    await _db
        .into(_db.heldRatingsTable)
        .insertOnConflictUpdate(heldRatingToRow(held, id: resolvedId));
    return resolvedId;
  }

  Future<domain.HeldRating?> find(String id) async {
    final row = await (_db.select(
      _db.heldRatingsTable,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : heldRatingFromRow(row);
  }

  Future<List<domain.HeldRating>> findAll() async {
    final rows = await _db.select(_db.heldRatingsTable).get();
    return [for (final row in rows) heldRatingFromRow(row)];
  }

  Future<void> delete(String id) =>
      (_db.delete(_db.heldRatingsTable)..where((t) => t.id.equals(id))).go();
}
