import 'dart:io';

import 'package:drift/native.dart';
import 'package:easa_digital_log/data/database.dart';
import 'package:easa_digital_log/data/repositories/aircraft_repository.dart';
import 'package:easa_digital_log/data/repositories/flight_repository_drift.dart';
import 'package:easa_digital_log/domain/model/aircraft.dart';
import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';

/// #90's crash-kill test harness: a standalone process (not part of the
/// app, not itself a `_test.dart` so `flutter test` never auto-runs it) that
/// opens a real database, performs a real multi-statement write wrapped in
/// `db.transaction()`, prints `READY` once every statement has been issued
/// but before the transaction commits, then idles. The parent test
/// (`test/data/crash_kill_test.dart`) kills this process on that signal and
/// reopens the database to assert nothing partial survived — proving the
/// actual OS-level guarantee a killed process leaves, not a simulation of
/// one.
///
/// Usage: `dart test/support/crash_kill_helper.dart <db-path> <mode>`, where
/// `mode` is `single-write` (AC3) or `import-batch` (AC4). Both modes wrap
/// the real repository call in one more, outer transaction here — since
/// `db.transaction()` nests (the same primitive `applyImportBatch` already
/// relies on to nest `createDraft`), this lets every statement the real
/// method issues actually run before `READY`, while keeping the whole thing
/// uncommitted for the idle window the parent kills during.
Future<void> main(List<String> args) async {
  final dbFile = File(args[0]);
  final mode = args[1];
  final db = AppDatabase(NativeDatabase(dbFile));

  // Committed before the scenario starts -- a real precondition (an aircraft
  // already exists), not part of what this run is testing the atomicity of.
  final aircraftId = await AircraftRepository(db).upsert(
    const Aircraft(
      registration: 'G-CRASH',
      manufacturer: 'Test',
      model: 'Kill',
      category: AircraftCategory.aeroplane,
      engineType: EngineType.piston,
      engineCount: 1,
      operatingSurface: OperatingSurface.land,
      requiresMultiCrew: false,
    ),
  );
  final flights = DriftFlightRepository(db);

  await db.transaction(() async {
    switch (mode) {
      case 'single-write':
        await flights.createDraft(_flight(), aircraftId: aircraftId);
      case 'import-batch':
        await flights.applyImportBatch(
          sourceLabel: 'crash-kill-test',
          flights: List.generate(
            20,
            (_) => (flight: _flight(), aircraftId: aircraftId),
          ),
        );
      default:
        throw ArgumentError('unknown mode: $mode');
    }

    // Every statement above has been issued on this connection but the
    // transaction hasn't committed. Signal readiness, then idle -- the
    // parent test kills this process during the idle window, well before
    // COMMIT would ever run.
    stdout.writeln('READY');
    await stdout.flush();
    await Future<void>.delayed(const Duration(seconds: 30));
  });
}

Flight _flight() => Flight(
  aircraftRegistration: 'G-CRASH',
  route: const ['EGKA', 'EGKB'],
  prePlannedNavigation: false,
  offBlocks: UtcInstant.utc(2026, 1, 1, 10),
  onBlocks: UtcInstant.utc(2026, 1, 1, 11),
  capacity: const PilotCapacity(
    commandAuthority: true,
    soleManipulator: true,
    soleOccupant: true,
    multiPilotOperation: false,
    additionalCrewRequiredByRule: false,
    actingAsInstructor: false,
    actingAsExaminer: false,
    picusClaimed: false,
    picInterventionNotRequired: false,
  ),
  carryingPassengers: false,
  takeoffs: const CircuitCounts(dayFullStop: 1),
  landings: const CircuitCounts(dayFullStop: 1),
  ifrFlightPlanFiled: false,
  actualInstrumentTime: FlightDuration.zero,
  simulatedInstrumentTime: FlightDuration.zero,
  approaches: const [],
  holdingProceduresCount: 0,
  trackingPerformed: false,
  remarks: '',
);
