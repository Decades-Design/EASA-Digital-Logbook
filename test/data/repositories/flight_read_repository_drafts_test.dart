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

  test('returns only drafts', () async {
    final draftId = await writes.createDraft(_flight(), aircraftId: aircraftId);
    final committedId = await writes.createDraft(
      _flight(),
      aircraftId: aircraftId,
    );
    await writes.commit(committedId);

    final result = await reads.watchDrafts().first;

    expect(result.map((r) => r.id), [draftId]);
  });

  test(
    're-emits when a draft is committed, and it disappears from the list',
    () async {
      final id = await writes.createDraft(_flight(), aircraftId: aircraftId);

      final stream = reads.watchDrafts();
      final emissions = stream.take(2).toList();
      await Future<void>.delayed(Duration.zero);

      await writes.commit(id);

      final results = await emissions;
      expect(results[0].map((r) => r.id), contains(id));
      expect(results[1].map((r) => r.id), isNot(contains(id)));
    },
  );
}
