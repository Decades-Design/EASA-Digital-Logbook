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
