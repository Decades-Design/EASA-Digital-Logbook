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
}
