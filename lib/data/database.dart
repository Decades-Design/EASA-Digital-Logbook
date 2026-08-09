import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'open_with_backup.dart';
import 'tables/aircraft_tables.dart';
import 'tables/custom_aerodrome_table.dart';
import 'tables/flight_tables.dart';
import 'tables/held_qualification_tables.dart';
import 'tables/pilot_record_tables.dart';

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
    PilotProfileTable,
    MedicalCertificatesTable,
    HeldAircraftQualificationsTable,
    HeldRatingsTable,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 4;

  // SQLite does not enforce foreign keys — including this schema's
  // `onDelete: KeyAction.cascade` on the flight/aircraft child tables —
  // unless a connection turns it on explicitly. Without this, deleting a
  // draft flight silently orphans its route-leg and approach rows instead
  // of cascading, which is exactly what it looked like happen before this
  // was added.
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (Migrator m, int from, int to) async {
      // #51: adds pilot_profile and medical_certificates. Neither
      // references an existing table, so the upgrade is two plain CREATE
      // TABLEs — no data migration, nothing to backfill.
      if (from < 2) {
        await m.createTable(pilotProfileTable);
        await m.createTable(medicalCertificatesTable);
      }
      // #52: adds held_aircraft_qualifications and held_ratings, same
      // shape of upgrade as #51's.
      if (from < 3) {
        await m.createTable(heldAircraftQualificationsTable);
        await m.createTable(heldRatingsTable);
      }
      // #121: adds alternativeComplianceEvents to the existing flights
      // table. Unlike the previous two steps, this alters a table that can
      // already hold real rows (M2's dev seed data) rather than creating a
      // new one — addColumn backfills the column's default ('', via the
      // table definition's withDefault) on every existing row, so no
      // explicit UPDATE is needed to keep old flights readable.
      if (from < 4) {
        await m.addColumn(
          flightsTable,
          flightsTable.alternativeComplianceEvents,
        );
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}

/// Opens [dbFile] as an [AppDatabase], guarded by [openWithBackup]. Querying
/// once (`SELECT 1`) forces drift's open-and-migrate sequence to run and
/// surface any error here, rather than lazily on whatever query a caller
/// happens to run first.
Future<AppDatabase> openAppDatabase(File dbFile) {
  return openWithBackup(dbFile, () async {
    final db = AppDatabase(NativeDatabase(dbFile));
    await db.customStatement('SELECT 1');
    return db;
  });
}
