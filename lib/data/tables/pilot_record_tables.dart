import 'package:drift/drift.dart';

/// Mirrors `PilotProfile` (#51) — always exactly one row, at the fixed id
/// [PilotProfileRepository.singletonId]: CLAUDE.md scopes this app to one
/// pilot's own legal record, never a list of pilots.
@DataClassName('PilotProfileRow')
class PilotProfileTable extends Table {
  @override
  String get tableName => 'pilot_profile';

  TextColumn get id => text()();
  TextColumn get dateOfBirth => text()();

  /// The [JurisdictionProfile.id] whose figures render everywhere that
  /// isn't the currency screen (CLAUDE.md: "let the user choose their
  /// primary jurisdiction must be a settings value, never a code path").
  /// Defaulted only for the migration backfill of the one pre-existing
  /// singleton row, never for a newly-created profile — `PilotProfile`'s
  /// own field is `required`.
  TextColumn get primaryJurisdictionId =>
      text().withDefault(const Constant('eu.easa.part-fcl'))();

  /// Mirrors `PilotProfile.homeBaseIcao` — nullable, never defaulted, since a
  /// pilot who hasn't set one should read back as unset, not backfilled.
  TextColumn get homeBaseIcao => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Mirrors `MedicalCertificate` (#51) — a current, editable reference
/// record like `aircraft`, not a draft/committed flight: a pilot corrects a
/// mistyped issue date the same way they correct a mistyped aircraft
/// registration.
@DataClassName('MedicalCertificateRow')
class MedicalCertificatesTable extends Table {
  @override
  String get tableName => 'medical_certificates';

  TextColumn get id => text()();
  TextColumn get certificateClass => text()();
  TextColumn get jurisdictionId => text()();
  TextColumn get issueDate => text()();

  @override
  Set<Column> get primaryKey => {id};
}
