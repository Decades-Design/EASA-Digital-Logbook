import 'package:drift/drift.dart';

/// Mirrors `HeldAircraftQualification` (#52) — a current, editable
/// reference record like `aircraft`.
@DataClassName('HeldAircraftQualificationRow')
class HeldAircraftQualificationsTable extends Table {
  @override
  String get tableName => 'held_aircraft_qualifications';

  TextColumn get id => text()();
  TextColumn get qualification => text()();
  TextColumn get jurisdictionId => text()();
  TextColumn get dateGranted => text()();
  TextColumn get signatoryName => text().nullable()();
  TextColumn get signatoryCredentialNumber => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Mirrors `HeldRating` (#52) — a current, editable reference record like
/// `aircraft`.
@DataClassName('HeldRatingRow')
class HeldRatingsTable extends Table {
  @override
  String get tableName => 'held_ratings';

  TextColumn get id => text()();
  TextColumn get kind => text()();
  TextColumn get designator => text()();
  TextColumn get jurisdictionId => text()();
  TextColumn get issueDate => text()();
  TextColumn get expiryDate => text().nullable()();
  IntColumn get languageProficiencyLevel => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
