import 'package:drift/native.dart';
import 'package:easa_digital_log/data/database.dart';
import 'package:easa_digital_log/data/repositories/aircraft_repository.dart';
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

Flight _draft({List<String> route = const ['EGKA', 'EGKB']}) {
  return Flight(
    aircraftRegistration: 'G-ABCD',
    route: route,
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
  late DriftFlightRepository flights;
  late String aircraftId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    flights = DriftFlightRepository(db);
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

  test('createDraft writes the flight and its route legs, uncommitted', () async {
    final id = await flights.createDraft(_draft(), aircraftId: aircraftId);

    final row = await (db.select(
      db.flightsTable,
    )..where((t) => t.id.equals(id))).getSingle();
    expect(row.committedAt, isNull);
    expect(row.tombstonedAt, isNull);

    final legs = await (db.select(
      db.flightRouteLegsTable,
    )..where((t) => t.flightId.equals(id))).get();
    expect(legs.map((l) => l.identifier), ['EGKA', 'EGKB']);
  });

  test('updateDraft overwrites the row and replaces route legs', () async {
    final id = await flights.createDraft(_draft(), aircraftId: aircraftId);

    await flights.updateDraft(id, _draft(route: ['EGKB']));

    final legs = await (db.select(
      db.flightRouteLegsTable,
    )..where((t) => t.flightId.equals(id))).get();
    expect(legs.map((l) => l.identifier), ['EGKB']);
  });

  test('updateDraft throws on a committed flight', () async {
    final id = await flights.createDraft(_draft(), aircraftId: aircraftId);
    await flights.commit(id);

    expect(() => flights.updateDraft(id, _draft()), throwsStateError);
  });

  test('deleteDraft removes the row and its children', () async {
    final id = await flights.createDraft(_draft(), aircraftId: aircraftId);

    await flights.deleteDraft(id);

    expect(
      await (db.select(
        db.flightsTable,
      )..where((t) => t.id.equals(id))).getSingleOrNull(),
      isNull,
    );
    expect(
      await (db.select(
        db.flightRouteLegsTable,
      )..where((t) => t.flightId.equals(id))).get(),
      isEmpty,
    );
  });

  test('deleteDraft throws on a committed flight', () async {
    final id = await flights.createDraft(_draft(), aircraftId: aircraftId);
    await flights.commit(id);

    expect(() => flights.deleteDraft(id), throwsStateError);
  });

  test('draft create/edit/delete writes no revision', () async {
    final id = await flights.createDraft(_draft(), aircraftId: aircraftId);
    await flights.updateDraft(id, _draft(route: ['EGKB']));

    final revisions = await (db.select(
      db.flightRevisionsTable,
    )..where((t) => t.flightId.equals(id))).get();
    expect(revisions, isEmpty);
  });
}
