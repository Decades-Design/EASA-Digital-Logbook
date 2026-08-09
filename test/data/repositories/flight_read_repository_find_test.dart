import 'package:drift/native.dart';
import 'package:easa_digital_log/data/database.dart';
import 'package:easa_digital_log/data/repositories/aircraft_repository.dart';
import 'package:easa_digital_log/data/repositories/flight_read_repository_drift.dart';
import 'package:easa_digital_log/data/repositories/flight_repository_drift.dart';
import 'package:easa_digital_log/domain/model/aircraft.dart';
import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:easa_digital_log/domain/projection/projection.dart';
import 'package:easa_digital_log/domain/projection/projection_result.dart';
import 'package:flutter_test/flutter_test.dart';

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

Flight _flight() {
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
    remarks: '',
  );
}

/// A fixed, recognisable result — this task tests wiring, not projection
/// correctness (M1's job).
class _StubProjection implements Projection {
  @override
  ProjectionResult project(Flight flight, Aircraft aircraft) {
    return const ProjectionResult(
      jurisdictionId: 'test.stub',
      quantities: {},
    );
  }

  @override
  ProjectionResult projectAggregate(Iterable<(Flight, Aircraft)> flights) {
    throw UnimplementedError();
  }
}

void main() {
  late AppDatabase db;
  late DriftFlightReadRepository reads;
  late DriftFlightRepository writes;
  late String aircraftId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    reads = DriftFlightReadRepository(db);
    writes = DriftFlightRepository(db);
    aircraftId = await AircraftRepository(db).upsert(
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
  });

  tearDown(() => db.close());

  test('find returns a committed flight, projected', () async {
    final id = await writes.createDraft(_flight(), aircraftId: aircraftId);
    await writes.commit(id);

    final result = await reads.find(id, projection: _StubProjection());

    expect(result, isNotNull);
    expect(result!.record.id, id);
    expect(result.record.flight, _flight());
    expect(result.record.aircraft.registration, 'G-ABCD');
    expect(result.projection.jurisdictionId, 'test.stub');
  });

  test('find returns a tombstoned flight', () async {
    final id = await writes.createDraft(_flight(), aircraftId: aircraftId);
    await writes.commit(id);
    await writes.tombstone(id);

    final result = await reads.find(id, projection: _StubProjection());

    expect(result, isNotNull);
  });

  test('find returns null for a draft', () async {
    final id = await writes.createDraft(_flight(), aircraftId: aircraftId);

    expect(await reads.find(id, projection: _StubProjection()), isNull);
  });

  test('find returns null for an unknown id', () async {
    expect(
      await reads.find('nonexistent', projection: _StubProjection()),
      isNull,
    );
  });

  test('findDraft returns a draft', () async {
    final id = await writes.createDraft(_flight(), aircraftId: aircraftId);

    final result = await reads.findDraft(id);

    expect(result, isNotNull);
    expect(result!.flight, _flight());
  });

  test('findDraft returns null for a committed flight', () async {
    final id = await writes.createDraft(_flight(), aircraftId: aircraftId);
    await writes.commit(id);

    expect(await reads.findDraft(id), isNull);
  });

  test(
    'find throws if a flight references an aircraft that no longer exists',
    () async {
      final id = await writes.createDraft(_flight(), aircraftId: aircraftId);
      await writes.commit(id);

      // FK enforcement (PRAGMA foreign_keys = ON, set in AppDatabase)
      // normally makes this state unreachable — deleting a referenced
      // aircraft is rejected. Turning it off here is the only way to
      // construct the dangling reference this defensive check exists for.
      await db.customStatement('PRAGMA foreign_keys = OFF');
      await (db.delete(
        db.aircraftsTable,
      )..where((t) => t.id.equals(aircraftId))).go();
      await db.customStatement('PRAGMA foreign_keys = ON');

      expect(
        () => reads.find(id, projection: _StubProjection()),
        throwsStateError,
      );
    },
  );
}
