import 'package:drift/drift.dart';

/// Mirrors `Aircraft` (#12) — "a current, editable reference record," no
/// draft/committed lifecycle, unlike `flights`.
@DataClassName('AircraftRow')
class AircraftsTable extends Table {
  @override
  String get tableName => 'aircraft';

  TextColumn get id => text()();
  TextColumn get registration => text().unique()();
  TextColumn get manufacturer => text()();
  TextColumn get model => text()();
  TextColumn get icaoTypeDesignator => text().nullable()();
  TextColumn get category => text()();
  TextColumn get engineType => text()();
  IntColumn get engineCount => integer()();
  TextColumn get operatingSurface => text()();
  BoolColumn get requiresMultiCrew => boolean()();
  TextColumn get typeRatingDesignator => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// One row per jurisdiction an aircraft has been configured for, present
/// even when [AircraftRequiredQualificationsTable] holds no rows for it —
/// the absent-vs-empty distinction `aircraft_test.dart` guards. See the M2
/// design spec's "aircraft_qualification_jurisdictions" section.
@DataClassName('AircraftQualificationJurisdictionRow')
class AircraftQualificationJurisdictionsTable extends Table {
  @override
  String get tableName => 'aircraft_qualification_jurisdictions';

  TextColumn get aircraftId =>
      text().references(AircraftsTable, #id, onDelete: KeyAction.cascade)();
  TextColumn get jurisdictionId => text()();

  @override
  Set<Column> get primaryKey => {aircraftId, jurisdictionId};
}

@DataClassName('AircraftRequiredQualificationRow')
class AircraftRequiredQualificationsTable extends Table {
  @override
  String get tableName => 'aircraft_required_qualifications';

  TextColumn get aircraftId =>
      text().references(AircraftsTable, #id, onDelete: KeyAction.cascade)();
  TextColumn get jurisdictionId => text()();
  TextColumn get qualification => text()();

  @override
  Set<Column> get primaryKey => {aircraftId, jurisdictionId, qualification};
}
