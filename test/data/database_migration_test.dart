import 'dart:io';

import 'package:drift/native.dart';
import 'package:easa_digital_log/data/database.dart';
import 'package:easa_digital_log/data/open_with_backup.dart';
import 'package:easa_digital_log/data/repositories/medical_certificate_repository.dart';
import 'package:easa_digital_log/data/repositories/pilot_profile_repository.dart';
import 'package:easa_digital_log/domain/model/calendar_date.dart';
import 'package:easa_digital_log/domain/pilot_record/medical_certificate.dart';
import 'package:easa_digital_log/domain/pilot_record/pilot_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// Creates a v1-shaped database file directly with sqlite3, seeded with one
/// aircraft row — the only way to get a real "v1 database" to migrate from,
/// since `AircraftsTable` only ever represents the *current* schema. Column
/// order and names mirror `lib/data/tables/aircraft_tables.dart` exactly;
/// only `aircraft` is seeded — the other seven v1 tables aren't needed to
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
    db.execute('PRAGMA user_version = 1');
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
      const profile = PilotProfile(dateOfBirth: CalendarDate(1990, 1, 1));
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
}
