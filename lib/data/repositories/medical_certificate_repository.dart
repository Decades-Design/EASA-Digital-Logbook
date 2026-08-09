import '../../domain/pilot_record/medical_certificate.dart' as domain;
import '../database.dart';
import '../mappers/pilot_record_mapper.dart';
import '../ulid.dart';

/// Write and read access to held medical certificates. A current, editable
/// reference record like `aircraft` — no draft/committed lifecycle.
class MedicalCertificateRepository {
  MedicalCertificateRepository(this._db);

  final AppDatabase _db;

  /// Inserts a new certificate (returning its generated id), or replaces
  /// the row when [id] names one already stored.
  Future<String> upsert(
    domain.MedicalCertificate certificate, {
    String? id,
  }) async {
    final resolvedId = id ?? generateUlid();
    await _db
        .into(_db.medicalCertificatesTable)
        .insertOnConflictUpdate(
          medicalCertificateToRow(certificate, id: resolvedId),
        );
    return resolvedId;
  }

  Future<domain.MedicalCertificate?> find(String id) async {
    final row = await (_db.select(
      _db.medicalCertificatesTable,
    )..where((t) => t.id.equals(id))).getSingleOrNull();
    return row == null ? null : medicalCertificateFromRow(row);
  }

  Future<List<domain.MedicalCertificate>> findAll() async {
    final rows = await _db.select(_db.medicalCertificatesTable).get();
    return [for (final row in rows) medicalCertificateFromRow(row)];
  }

  Future<void> delete(String id) => (_db.delete(
    _db.medicalCertificatesTable,
  )..where((t) => t.id.equals(id))).go();
}
