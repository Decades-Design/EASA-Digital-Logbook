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
  int get schemaVersion => 6;

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
      // Adds primaryJurisdictionId to pilot_profile — CLAUDE.md's "primary
      // jurisdiction must be an explicit settings value". The column's
      // withDefault backfills the one pre-existing singleton row to EASA;
      // a real pilot changes it in Settings same as any other preference.
      //
      // Guarded to `from >= 2`: a database upgrading from v1 hits the
      // `from < 2` branch above first, and `createTable` always builds from
      // *today's* Dart table definition — which already includes this
      // column — so running `addColumn` again on the same upgrade would
      // fail with "duplicate column name". Only a database whose
      // pilot_profile table was created by an *older* build (schema v2-v4,
      // genuinely missing the column) needs this step.
      if (from >= 2 && from < 5) {
        await m.addColumn(
          pilotProfileTable,
          pilotProfileTable.primaryJurisdictionId,
        );
      }
      // Adds homeBaseIcao to pilot_profile — the Aerodromes screen's
      // "furthest" figure. Nullable and never defaulted, so the column's
      // backfill leaves every existing row with no home base set rather than
      // guessing one.
      //
      // Guarded to `from >= 2`, same reasoning as the `primaryJurisdictionId`
      // step above: `from < 2`'s `createTable` already builds from today's
      // Dart schema, which already includes this column.
      if (from >= 2 && from < 6) {
        await m.addColumn(pilotProfileTable, pilotProfileTable.homeBaseIcao);
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
