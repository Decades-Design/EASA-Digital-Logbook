import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

import 'open_with_backup.dart';
import 'tables/aircraft_tables.dart';
import 'tables/custom_aerodrome_table.dart';
import 'tables/flight_tables.dart';
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
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 2;

  // SQLite does not enforce foreign keys — including this schema's
  // `onDelete: KeyAction.cascade` on the flight/aircraft child tables —
  // unless a connection turns it on explicitly. Without this, deleting a
  // draft flight silently orphans its route-leg and approach rows instead
  // of cascading, which is exactly what it looked like happen before this
  // was added.
  @override
  MigrationStrategy get migration => MigrationStrategy(
    // #51: adds pilot_profile and medical_certificates. Neither references
    // an existing table, so the upgrade is two plain CREATE TABLEs — no
    // data migration, nothing to backfill. ADR-0010's file-level backup
    // (`open_with_backup.dart`) still covers this against an interrupted
    // upgrade; this is the first real exercise of the framework it
    // describes, which until now had only run against a throwaway fixture.
    onUpgrade: (Migrator m, int from, int to) async {
      if (from < 2) {
        await m.createTable(pilotProfileTable);
        await m.createTable(medicalCertificatesTable);
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
