import 'dart:io';

import 'package:drift/native.dart';
import 'package:easa_digital_log/data/database.dart';
import 'package:easa_digital_log/data/database_backup.dart';
import 'package:easa_digital_log/data/repositories/aircraft_repository.dart';
import 'package:easa_digital_log/data/repositories/flight_repository_drift.dart';
import 'package:easa_digital_log/domain/model/aircraft.dart';
import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _capacity = PilotCapacity(
  commandAuthority: true,
  soleManipulator: true,
  soleOccupant: true,
  multiPilotOperation: false,
  additionalCrewRequiredByRule: false,
  actingAsInstructor: false,
  actingAsExaminer: false,
  picusClaimed: false,
  picInterventionNotRequired: false,
);

Flight _flight({String remarks = ''}) {
  return Flight(
    aircraftRegistration: 'G-ABCD',
    route: const ['EGKA', 'EGKB'],
    prePlannedNavigation: false,
    offBlocks: UtcInstant.utc(2026, 6, 1, 10),
    onBlocks: UtcInstant.utc(2026, 6, 1, 11),
    capacity: _capacity,
    carryingPassengers: false,
    takeoffs: const CircuitCounts(dayFullStop: 1),
    landings: const CircuitCounts(dayFullStop: 1),
    ifrFlightPlanFiled: false,
    actualInstrumentTime: FlightDuration.zero,
    simulatedInstrumentTime: FlightDuration.zero,
    approaches: const [],
    holdingProceduresCount: 0,
    trackingPerformed: false,
    remarks: remarks,
  );
}

Future<List<Object?>> _snapshot(AppDatabase db) async {
  final flights = await db.select(db.flightsTable).get();
  final revisions = await db.select(db.flightRevisionsTable).get();
  final aircraft = await db.select(db.aircraftsTable).get();
  return [
    flights.map((r) => r.toJson()).toList(),
    revisions.map((r) => r.toJson()).toList(),
    aircraft.map((r) => r.toJson()).toList(),
  ];
}

void main() {
  late Directory tempDir;
  late File dbFile;
  late File backupFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('database_backup_test');
    dbFile = File(p.join(tempDir.path, 'live.sqlite'));
    backupFile = File(p.join(tempDir.path, 'backup.sqlite'));
  });

  tearDown(() => tempDir.delete(recursive: true));

  test('export, wipe, restore round-trips flights, revisions and aircraft '
      'exactly', () async {
    var db = AppDatabase(NativeDatabase(dbFile));
    final aircraftId = await AircraftRepository(db).upsert(
      const Aircraft(
        registration: 'G-ABCD',
        manufacturer: 'Cessna',
        model: '152',
        category: AircraftCategory.aeroplane,
        engineType: EngineType.piston,
        engineCount: 1,
        operatingSurface: OperatingSurface.land,
        requiresMultiCrew: false,
      ),
    );
    final flights = DriftFlightRepository(db);

    // Exercise the full lifecycle: a draft, a committed flight with a
    // revision, and a tombstoned flight — so the round trip actually
    // proves revision history and entry states survive, not just a bare
    // row.
    await flights.createDraft(
      _flight(remarks: 'still a draft'),
      aircraftId: aircraftId,
    );

    final committedId = await flights.createDraft(
      _flight(remarks: 'original'),
      aircraftId: aircraftId,
    );
    await flights.commit(committedId);
    await flights.updateCommitted(
      committedId,
      _flight(remarks: 'corrected'),
      reason: 'test correction',
    );

    final tombstonedId = await flights.createDraft(
      _flight(remarks: 'to be voided'),
      aircraftId: aircraftId,
    );
    await flights.commit(tombstonedId);
    await flights.tombstone(tombstonedId, reason: 'test void');

    final before = await _snapshot(db);

    await exportDatabaseBackup(db, backupFile);
    expect(await backupFile.exists(), isTrue);

    await db.close();
    await dbFile.delete();

    await restoreDatabaseBackup(backupFile, dbFile);
    expect(await dbFile.readAsBytes(), await backupFile.readAsBytes());

    db = AppDatabase(NativeDatabase(dbFile));
    final after = await _snapshot(db);
    await db.close();

    expect(after, equals(before));
  });

  test('restoreDatabaseBackup throws when the backup file is missing', () {
    expect(
      () => restoreDatabaseBackup(backupFile, dbFile),
      throwsArgumentError,
    );
  });

  test('restoreDatabaseBackup replaces an existing live file and its stale '
      'journal', () async {
    await backupFile.writeAsString('backup content');
    await dbFile.writeAsString('stale live content');
    final journal = File('${dbFile.path}-journal');
    await journal.writeAsString('stale journal');

    await restoreDatabaseBackup(backupFile, dbFile);

    expect(await dbFile.readAsString(), 'backup content');
    expect(await journal.exists(), isFalse);
  });

  group('isBackupOverdue', () {
    test('true when no backup has ever been taken', () {
      expect(isBackupOverdue(null, DateTime.utc(2026, 1, 1)), isTrue);
    });

    test('false just under the interval', () {
      final lastBackup = DateTime.utc(2026, 1, 1);
      final now = lastBackup.add(const Duration(days: 29));
      expect(isBackupOverdue(lastBackup, now), isFalse);
    });

    test('true at and beyond the interval', () {
      final lastBackup = DateTime.utc(2026, 1, 1);
      expect(
        isBackupOverdue(lastBackup, lastBackup.add(const Duration(days: 30))),
        isTrue,
      );
      expect(
        isBackupOverdue(lastBackup, lastBackup.add(const Duration(days: 45))),
        isTrue,
      );
    });

    test('honours a custom interval', () {
      final lastBackup = DateTime.utc(2026, 1, 1);
      expect(
        isBackupOverdue(
          lastBackup,
          lastBackup.add(const Duration(days: 8)),
          interval: const Duration(days: 7),
        ),
        isTrue,
      );
    });
  });
}
