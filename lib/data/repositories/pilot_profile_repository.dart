import '../../domain/pilot_record/pilot_profile.dart' as domain;
import '../database.dart';
import '../mappers/pilot_record_mapper.dart';

/// Write and read access to the single [domain.PilotProfile] this
/// installation holds. No draft/committed lifecycle, no id parameter on
/// [save] — CLAUDE.md scopes this app to one pilot, so there is exactly
/// one row, always at [singletonId].
class PilotProfileRepository {
  PilotProfileRepository(this._db);

  final AppDatabase _db;

  static const singletonId = 'singleton';

  Future<void> save(domain.PilotProfile profile) => _db
      .into(_db.pilotProfileTable)
      .insertOnConflictUpdate(pilotProfileToRow(profile, id: singletonId));

  Future<domain.PilotProfile?> find() async {
    final row = await (_db.select(
      _db.pilotProfileTable,
    )..where((t) => t.id.equals(singletonId))).getSingleOrNull();
    return row == null ? null : pilotProfileFromRow(row);
  }
}
