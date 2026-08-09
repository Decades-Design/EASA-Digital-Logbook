import 'package:drift/drift.dart';

import 'tables/aircraft_tables.dart';
import 'tables/custom_aerodrome_table.dart';
import 'tables/flight_tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    AircraftsTable,
    AircraftQualificationJurisdictionsTable,
    AircraftRequiredQualificationsTable,
    CustomAerodromesTable,
    FlightsTable,
    FlightRouteLegsTable,
    FlightApproachesTable,
    FlightRevisionsTable,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 1;

  // SQLite does not enforce foreign keys — including this schema's
  // `onDelete: KeyAction.cascade` on the flight/aircraft child tables —
  // unless a connection turns it on explicitly. Without this, deleting a
  // draft flight silently orphans its route-leg and approach rows instead
  // of cascading, which is exactly what it looked like happen before this
  // was added.
  @override
  MigrationStrategy get migration => MigrationStrategy(
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
