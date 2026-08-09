import 'package:drift/drift.dart';

import 'aircraft_tables.dart';

/// One row per flight, current state only. `committedAt`/`tombstonedAt`
/// double as both the state flag and the instant of that state change — see
/// the M2 design spec's "Lifecycle" section. Only
/// `FlightRepository`/`DriftFlightRepository` may write this table.
@DataClassName('FlightRow')
class FlightsTable extends Table {
  @override
  String get tableName => 'flights';

  TextColumn get id => text()();
  TextColumn get aircraftId => text().references(AircraftsTable, #id)();
  BoolColumn get prePlannedNavigation => boolean()();
  IntColumn get offBlocks => integer()();
  IntColumn get onBlocks => integer()();
  IntColumn get takeoff => integer().nullable()();
  IntColumn get landing => integer().nullable()();
  TextColumn get otherPilotName => text().nullable()();
  TextColumn get otherPilotCredentialNumber => text().nullable()();
  BoolColumn get carryingPassengers => boolean()();

  // Flattened CircuitCounts, ×2 (takeoffs, landings).
  IntColumn get takeoffsDayFullStop => integer()();
  IntColumn get takeoffsDayTouchAndGo => integer()();
  IntColumn get takeoffsNightFullStop => integer()();
  IntColumn get takeoffsNightTouchAndGo => integer()();
  IntColumn get landingsDayFullStop => integer()();
  IntColumn get landingsDayTouchAndGo => integer()();
  IntColumn get landingsNightFullStop => integer()();
  IntColumn get landingsNightTouchAndGo => integer()();

  BoolColumn get ifrFlightPlanFiled => boolean()();
  IntColumn get actualInstrumentMinutes => integer()();
  IntColumn get simulatedInstrumentMinutes => integer()();
  IntColumn get holdingProceduresCount => integer()();
  BoolColumn get trackingPerformed => boolean()();

  TextColumn get seriesGroupId => text().nullable()();
  TextColumn get airworthinessBasis => text().nullable()();
  TextColumn get remarks => text()();

  // Flattened PilotCapacity.
  BoolColumn get capacityCommandAuthority => boolean()();
  BoolColumn get capacitySoleManipulator => boolean()();
  BoolColumn get capacitySoleOccupant => boolean()();
  BoolColumn get capacityMultiPilotOperation => boolean()();
  BoolColumn get capacityAdditionalCrewRequiredByRule => boolean()();
  BoolColumn get capacityActingAsInstructor => boolean()();
  BoolColumn get capacityActingAsExaminer => boolean()();
  BoolColumn get capacityPicusClaimed => boolean()();
  BoolColumn get capacityPicInterventionNotRequired => boolean()();
  IntColumn get capacityManipulationTimeMinutes => integer().nullable()();
  BoolColumn get capacitySoloEndorsementHeld => boolean().nullable()();
  TextColumn get capacityEndorsingInstructorName => text().nullable()();

  // Flattened PilotCapacity.instructor (InstructorPresence?).
  TextColumn get capacityInstructorCapacity => text().nullable()();
  BoolColumn get capacityInstructorInfluencedFlight => boolean().nullable()();
  TextColumn get capacityInstructorName => text().nullable()();
  TextColumn get capacityInstructorCredentialNumber => text().nullable()();
  TextColumn get capacityInstructorCredentialExpiry => text().nullable()();

  TextColumn get capacityOtherPilotRole => text().nullable()();

  // Flattened PilotCapacity.countersignature (Countersignature?).
  TextColumn get capacityCountersignatureStatus => text().nullable()();
  TextColumn get capacityCountersignatureSignatoryName => text().nullable()();
  TextColumn get capacityCountersignatureSignatoryCredentialNumber =>
      text().nullable()();
  TextColumn get capacityCountersignatureSignatoryCredentialExpiry =>
      text().nullable()();
  IntColumn get capacityCountersignatureSignedAt => integer().nullable()();

  IntColumn get committedAt => integer().nullable()();
  IntColumn get tombstonedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('FlightRouteLegRow')
class FlightRouteLegsTable extends Table {
  @override
  String get tableName => 'flight_route_legs';

  TextColumn get id => text()();
  TextColumn get flightId =>
      text().references(FlightsTable, #id, onDelete: KeyAction.cascade)();
  IntColumn get sequence => integer()();
  TextColumn get identifier => text()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('FlightApproachRow')
class FlightApproachesTable extends Table {
  @override
  String get tableName => 'flight_approaches';

  TextColumn get id => text()();
  TextColumn get flightId =>
      text().references(FlightsTable, #id, onDelete: KeyAction.cascade)();
  TextColumn get type => text()();
  TextColumn get aerodromeIcao => text()();
  TextColumn get runway => text()();
  IntColumn get count => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// One row per edit event on a committed flight — not per changed field, so
/// a revision's `reason` and `recordedAt` apply to the whole edit. Never
/// cascades on flight deletion: a committed flight is never hard-deleted
/// (see "Deleting a committed flight" in the design spec), so its revisions
/// always outlive it.
@DataClassName('FlightRevisionRow')
class FlightRevisionsTable extends Table {
  @override
  String get tableName => 'flight_revisions';

  TextColumn get id => text()();
  TextColumn get flightId => text().references(FlightsTable, #id)();
  IntColumn get recordedAt => integer()();
  TextColumn get kind => text()();
  TextColumn get reason => text().nullable()();
  TextColumn get changedFields => text()();

  @override
  Set<Column> get primaryKey => {id};
}
