import 'dart:io';

import 'package:drift/native.dart';
import 'package:easa_digital_log/data/database.dart';
import 'package:easa_digital_log/data/open_with_backup.dart';
import 'package:easa_digital_log/data/repositories/held_rating_repository.dart';
import 'package:easa_digital_log/data/repositories/medical_certificate_repository.dart';
import 'package:easa_digital_log/data/repositories/pilot_profile_repository.dart';
import 'package:easa_digital_log/domain/model/calendar_date.dart';
import 'package:easa_digital_log/domain/pilot_record/held_rating.dart';
import 'package:easa_digital_log/domain/pilot_record/medical_certificate.dart';
import 'package:easa_digital_log/domain/pilot_record/pilot_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// The `flights` table's shape from v1 through v3 -- unchanged by #51/#52,
/// only altered by #121 (v4). Column names mirror
/// `lib/data/tables/flight_tables.dart`'s drift-generated snake_case
/// exactly. Shared by [_seedV1Database] and [_seedV3Database]: a real v1
/// install has this table even though neither #51's nor #52's migration
/// step touches it, and skipping its creation would make #121's `addColumn`
/// step fail with "no such table" the moment a seed test exercises it.
const String _createFlightsTableV1ThroughV3 = '''
  CREATE TABLE flights (
    id TEXT NOT NULL,
    aircraft_id TEXT NOT NULL REFERENCES aircraft (id),
    pre_planned_navigation INTEGER NOT NULL,
    off_blocks INTEGER NOT NULL,
    on_blocks INTEGER NOT NULL,
    takeoff INTEGER NULL,
    landing INTEGER NULL,
    other_pilot_name TEXT NULL,
    other_pilot_credential_number TEXT NULL,
    carrying_passengers INTEGER NOT NULL,
    takeoffs_day_full_stop INTEGER NOT NULL,
    takeoffs_day_touch_and_go INTEGER NOT NULL,
    takeoffs_night_full_stop INTEGER NOT NULL,
    takeoffs_night_touch_and_go INTEGER NOT NULL,
    landings_day_full_stop INTEGER NOT NULL,
    landings_day_touch_and_go INTEGER NOT NULL,
    landings_night_full_stop INTEGER NOT NULL,
    landings_night_touch_and_go INTEGER NOT NULL,
    ifr_flight_plan_filed INTEGER NOT NULL,
    actual_instrument_minutes INTEGER NOT NULL,
    simulated_instrument_minutes INTEGER NOT NULL,
    holding_procedures_count INTEGER NOT NULL,
    tracking_performed INTEGER NOT NULL,
    series_group_id TEXT NULL,
    airworthiness_basis TEXT NULL,
    remarks TEXT NOT NULL,
    capacity_command_authority INTEGER NOT NULL,
    capacity_sole_manipulator INTEGER NOT NULL,
    capacity_sole_occupant INTEGER NOT NULL,
    capacity_multi_pilot_operation INTEGER NOT NULL,
    capacity_additional_crew_required_by_rule INTEGER NOT NULL,
    capacity_acting_as_instructor INTEGER NOT NULL,
    capacity_acting_as_examiner INTEGER NOT NULL,
    capacity_picus_claimed INTEGER NOT NULL,
    capacity_pic_intervention_not_required INTEGER NOT NULL,
    capacity_manipulation_time_minutes INTEGER NULL,
    capacity_solo_endorsement_held INTEGER NULL,
    capacity_endorsing_instructor_name TEXT NULL,
    capacity_instructor_capacity TEXT NULL,
    capacity_instructor_influenced_flight INTEGER NULL,
    capacity_instructor_name TEXT NULL,
    capacity_instructor_credential_number TEXT NULL,
    capacity_instructor_credential_expiry TEXT NULL,
    capacity_other_pilot_role TEXT NULL,
    capacity_countersignature_status TEXT NULL,
    capacity_countersignature_signatory_name TEXT NULL,
    capacity_countersignature_signatory_credential_number TEXT NULL,
    capacity_countersignature_signatory_credential_expiry TEXT NULL,
    capacity_countersignature_signed_at INTEGER NULL,
    committed_at INTEGER NULL,
    tombstoned_at INTEGER NULL,
    PRIMARY KEY (id)
  )
''';

/// Creates a v1-shaped database file directly with sqlite3, seeded with one
/// aircraft row — the only way to get a real "v1 database" to migrate from,
/// since `AircraftsTable` only ever represents the *current* schema. Column
/// order and names mirror `lib/data/tables/aircraft_tables.dart` exactly.
/// `flights` is created empty (no row) — enough for #121's `addColumn` step
/// to have a table to alter; the other five v1 tables aren't needed to
/// prove #51's migration step behaves, and hand-duplicating their DDL here
/// would just be more surface area to drift out of sync with the real
/// tables for no extra coverage.
void _seedV1Database(String path) {
  final db = sqlite3.sqlite3.open(path);
  try {
    db.execute('''
      CREATE TABLE aircraft (
        id TEXT NOT NULL,
        registration TEXT NOT NULL UNIQUE,
        manufacturer TEXT NOT NULL,
        model TEXT NOT NULL,
        icao_type_designator TEXT NULL,
        category TEXT NOT NULL,
        engine_type TEXT NOT NULL,
        engine_count INTEGER NOT NULL,
        operating_surface TEXT NOT NULL,
        requires_multi_crew INTEGER NOT NULL,
        type_rating_designator TEXT NULL,
        PRIMARY KEY (id)
      )
    ''');
    db.execute(
      'INSERT INTO aircraft (id, registration, manufacturer, model, '
      'category, engine_type, engine_count, operating_surface, '
      'requires_multi_crew) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        'aircraft-1',
        'G-ABCD',
        'Cessna',
        '152',
        'aeroplane',
        'piston',
        1,
        'land',
        0,
      ],
    );
    db.execute(_createFlightsTableV1ThroughV3);
    db.execute('PRAGMA user_version = 1');
  } finally {
    db.close();
  }
}

/// As [_seedV1Database], but already at v2 (the `pilot_profile` and
/// `medical_certificates` tables from #51 already exist and have a row),
/// to exercise the migration path a pilot who upgrades straight from v2 —
/// not from the very first v1 release — actually takes: the `from < 2`
/// block must be skipped and only `from < 3` must run.
void _seedV2Database(String path) {
  final db = sqlite3.sqlite3.open(path);
  try {
    db.execute('''
      CREATE TABLE pilot_profile (
        id TEXT NOT NULL,
        date_of_birth TEXT NOT NULL,
        PRIMARY KEY (id)
      )
    ''');
    db.execute('INSERT INTO pilot_profile (id, date_of_birth) VALUES (?, ?)', [
      'singleton',
      '1990-01-01',
    ]);
    // #121's `from < 4` step alters `flights` regardless of which earlier
    // version this database started at, so every seed at v3 or below needs
    // the table present, empty or not.
    db.execute(_createFlightsTableV1ThroughV3);
    db.execute('PRAGMA user_version = 2');
  } finally {
    db.close();
  }
}

/// As [_seedV2Database], but at v3, with a `flights` row already on
/// disk — to prove #121's `addColumn` step preserves existing flight data
/// and backfills the new column's default rather than, say, requiring every
/// row to be rewritten by the app first. `held_*` is omitted for the same
/// reason [_seedV1Database] omits the other v1 tables: irrelevant to the one
/// step under test here, and the `from < 3` migration block never runs for a
/// database already at v3, so its absence doesn't trip anything.
///
/// `pilot_profile` **is** included, at its pre-v5 shape (no
/// `primary_jurisdiction_id`) — a real v3 database always has this table
/// from its earlier v1->v2 upgrade, and the later `from < 5` step in
/// `database.dart` alters it, so a seed that omitted it would fail that
/// step with "no such table" rather than exercising it honestly.
void _seedV3Database(String path) {
  final db = sqlite3.sqlite3.open(path);
  try {
    db.execute('''
      CREATE TABLE pilot_profile (
        id TEXT NOT NULL,
        date_of_birth TEXT NOT NULL,
        PRIMARY KEY (id)
      )
    ''');
    db.execute('INSERT INTO pilot_profile (id, date_of_birth) VALUES (?, ?)', [
      'singleton',
      '1990-01-01',
    ]);
    db.execute('''
      CREATE TABLE aircraft (
        id TEXT NOT NULL,
        registration TEXT NOT NULL UNIQUE,
        manufacturer TEXT NOT NULL,
        model TEXT NOT NULL,
        icao_type_designator TEXT NULL,
        category TEXT NOT NULL,
        engine_type TEXT NOT NULL,
        engine_count INTEGER NOT NULL,
        operating_surface TEXT NOT NULL,
        requires_multi_crew INTEGER NOT NULL,
        type_rating_designator TEXT NULL,
        PRIMARY KEY (id)
      )
    ''');
    db.execute(
      'INSERT INTO aircraft (id, registration, manufacturer, model, '
      'category, engine_type, engine_count, operating_surface, '
      'requires_multi_crew) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        'aircraft-1',
        'G-ABCD',
        'Cessna',
        '152',
        'aeroplane',
        'piston',
        1,
        'land',
        0,
      ],
    );
    db.execute(_createFlightsTableV1ThroughV3);
    db.execute(
      'INSERT INTO flights (id, aircraft_id, pre_planned_navigation, '
      'off_blocks, on_blocks, carrying_passengers, takeoffs_day_full_stop, '
      'takeoffs_day_touch_and_go, takeoffs_night_full_stop, '
      'takeoffs_night_touch_and_go, landings_day_full_stop, '
      'landings_day_touch_and_go, landings_night_full_stop, '
      'landings_night_touch_and_go, ifr_flight_plan_filed, '
      'actual_instrument_minutes, simulated_instrument_minutes, '
      'holding_procedures_count, tracking_performed, remarks, '
      'capacity_command_authority, capacity_sole_manipulator, '
      'capacity_sole_occupant, capacity_multi_pilot_operation, '
      'capacity_additional_crew_required_by_rule, '
      'capacity_acting_as_instructor, capacity_acting_as_examiner, '
      'capacity_picus_claimed, capacity_pic_intervention_not_required) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '
      '?, ?, ?, ?, ?, ?, ?, ?)',
      [
        'flight-1',
        'aircraft-1',
        0,
        1000,
        2000,
        0,
        1,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        'a pre-existing flight',
        1,
        1,
        1,
        0,
        0,
        0,
        0,
        0,
        0,
      ],
    );
    db.execute('PRAGMA user_version = 3');
  } finally {
    db.close();
  }
}

/// As [_seedV3Database], but at v5 with `primary_jurisdiction_id` already
/// present (from the earlier v4->v5 step) — isolates the v5->v6 step under
/// test here, the same way [_seedV3Database] isolates v3->v4. Proves the new
/// step adds `home_base_icao` and backfills it to null rather than guessing a
/// value, and leaves the pre-existing `primary_jurisdiction_id` untouched.
void _seedV5Database(String path) {
  final db = sqlite3.sqlite3.open(path);
  try {
    db.execute('''
      CREATE TABLE pilot_profile (
        id TEXT NOT NULL,
        date_of_birth TEXT NOT NULL,
        primary_jurisdiction_id TEXT NOT NULL DEFAULT 'eu.easa.part-fcl',
        PRIMARY KEY (id)
      )
    ''');
    db.execute(
      'INSERT INTO pilot_profile (id, date_of_birth, primary_jurisdiction_id) '
      'VALUES (?, ?, ?)',
      ['singleton', '1990-01-01', 'us.faa.part61'],
    );
    db.execute('PRAGMA user_version = 5');
  } finally {
    db.close();
  }
}

void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('database_migration_test');
    dbFile = File(p.join(tempDir.path, 'app.sqlite'));
  });

  tearDown(() => tempDir.delete(recursive: true));

  test(
    '#51: migrating a real v1 database to v2 preserves existing data and '
    'adds pilot_profile/medical_certificates, usable through their repositories',
    () async {
      _seedV1Database(dbFile.path);

      final db = await openWithBackup(dbFile, () async {
        final database = AppDatabase(NativeDatabase(dbFile));
        await database.customStatement('SELECT 1');
        return database;
      });
      addTearDown(db.close);

      final aircraftRows = await db.select(db.aircraftsTable).get();
      expect(aircraftRows, hasLength(1));
      expect(aircraftRows.single.registration, 'G-ABCD');

      final pilotProfiles = PilotProfileRepository(db);
      const profile = PilotProfile(
        dateOfBirth: CalendarDate(1990, 1, 1),
        primaryJurisdictionId: 'eu.easa.part-fcl',
      );
      await pilotProfiles.save(profile);
      expect(await pilotProfiles.find(), profile);

      final medicalCertificates = MedicalCertificateRepository(db);
      const certificate = MedicalCertificate(
        certificateClass: MedicalCertificateClass.easaClass2,
        jurisdictionId: 'eu.easa.part-fcl',
        issueDate: CalendarDate(2024, 1, 1),
      );
      final id = await medicalCertificates.upsert(certificate);
      expect(await medicalCertificates.find(id), certificate);
    },
  );

  test(
    '#52: migrating a real v2 database to v3 preserves existing pilot_profile '
    'data and adds held_ratings, without re-running the v1->v2 step',
    () async {
      _seedV2Database(dbFile.path);

      final db = await openWithBackup(dbFile, () async {
        final database = AppDatabase(NativeDatabase(dbFile));
        await database.customStatement('SELECT 1');
        return database;
      });
      addTearDown(db.close);

      final pilotProfiles = PilotProfileRepository(db);
      expect(
        await pilotProfiles.find(),
        // primaryJurisdictionId didn't exist at v2 -- the v4->v5 addColumn
        // step backfills its default, same proof-of-backfill shape as
        // #121's alternativeComplianceEvents column above.
        const PilotProfile(
          dateOfBirth: CalendarDate(1990, 1, 1),
          primaryJurisdictionId: 'eu.easa.part-fcl',
        ),
      );

      final heldRatings = HeldRatingRepository(db);
      const rating = HeldRating(
        kind: HeldRatingKind.instrumentRating,
        designator: 'IR',
        jurisdictionId: 'eu.easa.part-fcl',
        issueDate: CalendarDate(2024, 1, 1),
        expiryDate: CalendarDate(2025, 1, 1),
      );
      final id = await heldRatings.upsert(rating);
      expect(await heldRatings.find(id), rating);
    },
  );

  test('#121: migrating a real v3 database to v4 preserves an existing flight '
      'and backfills alternativeComplianceEvents to empty', () async {
    _seedV3Database(dbFile.path);

    final db = await openWithBackup(dbFile, () async {
      final database = AppDatabase(NativeDatabase(dbFile));
      await database.customStatement('SELECT 1');
      return database;
    });
    addTearDown(db.close);

    final flightRows = await db.select(db.flightsTable).get();
    expect(flightRows, hasLength(1));
    expect(flightRows.single.id, 'flight-1');
    expect(flightRows.single.remarks, 'a pre-existing flight');
    expect(flightRows.single.alternativeComplianceEvents, isEmpty);
  });

  test('migrating a real v5 database to v6 preserves primaryJurisdictionId and '
      'backfills homeBaseIcao to null', () async {
    _seedV5Database(dbFile.path);

    final db = await openWithBackup(dbFile, () async {
      final database = AppDatabase(NativeDatabase(dbFile));
      await database.customStatement('SELECT 1');
      return database;
    });
    addTearDown(db.close);

    final pilotProfiles = PilotProfileRepository(db);
    expect(
      await pilotProfiles.find(),
      const PilotProfile(
        dateOfBirth: CalendarDate(1990, 1, 1),
        primaryJurisdictionId: 'us.faa.part61',
      ),
    );
  });
}
