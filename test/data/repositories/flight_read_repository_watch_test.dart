import 'package:drift/native.dart';
import 'package:easa_digital_log/data/database.dart';
import 'package:easa_digital_log/data/repositories/aircraft_repository.dart';
import 'package:easa_digital_log/data/repositories/flight_read_repository_drift.dart';
import 'package:easa_digital_log/data/repositories/flight_repository_drift.dart';
import 'package:easa_digital_log/domain/model/aircraft.dart';
import 'package:easa_digital_log/domain/model/calendar_date.dart';
import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:easa_digital_log/domain/projection/projection.dart';
import 'package:easa_digital_log/domain/projection/projection_result.dart';
import 'package:easa_digital_log/domain/repository/flight_read_repository.dart';
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

Flight _flight({
  List<String> route = const ['EGKA', 'EGKB'],
  UtcInstant? offBlocks,
  PilotCapacity capacity = _capacity,
  List<Approach> approaches = const [],
}) {
  final off = offBlocks ?? UtcInstant.utc(2026, 6, 1, 10);
  return Flight(
    aircraftRegistration: 'G-ABCD',
    route: route,
    prePlannedNavigation: false,
    offBlocks: off,
    onBlocks: off.add(const Duration(hours: 1)),
    capacity: capacity,
    carryingPassengers: false,
    takeoffs: const CircuitCounts(dayFullStop: 1),
    landings: const CircuitCounts(dayFullStop: 1),
    ifrFlightPlanFiled: false,
    actualInstrumentTime: FlightDuration.zero,
    simulatedInstrumentTime: FlightDuration.zero,
    approaches: approaches,
    holdingProceduresCount: 0,
    trackingPerformed: false,
    remarks: '',
  );
}

class _StubProjection implements Projection {
  @override
  ProjectionResult project(Flight flight, Aircraft aircraft) {
    return const ProjectionResult(jurisdictionId: 'test.stub', quantities: {});
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
  late String secondAircraftId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    reads = DriftFlightReadRepository(db);
    writes = DriftFlightRepository(db);
    final aircraft = AircraftRepository(db);
    aircraftId = await aircraft.upsert(
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
    secondAircraftId = await aircraft.upsert(
      const Aircraft(
        registration: 'G-WXYZ',
        manufacturer: 'Piper',
        model: 'PA-28',
        category: AircraftCategory.aeroplane,
        engineType: EngineType.piston,
        engineCount: 1,
        operatingSurface: OperatingSurface.land,
        requiresMultiCrew: false,
      ),
    );
  });

  tearDown(() => db.close());

  Future<String> commitFlight(Flight flight, {String? aircraft}) async {
    final id = await writes.createDraft(
      flight,
      aircraftId: aircraft ?? aircraftId,
    );
    await writes.commit(id);
    return id;
  }

  test('excludes drafts and tombstoned flights by default', () async {
    final draftId = await writes.createDraft(_flight(), aircraftId: aircraftId);
    final activeId = await commitFlight(_flight());
    final tombstonedId = await commitFlight(_flight());
    await writes.tombstone(tombstonedId);

    final result = await reads
        .watchFlights(projection: _StubProjection())
        .first;
    final ids = result.map((p) => p.record.id).toSet();

    expect(ids, {activeId});
    expect(ids, isNot(contains(draftId)));
    expect(ids, isNot(contains(tombstonedId)));
  });

  test('filters by aircraftId', () async {
    final matchId = await commitFlight(_flight());
    await commitFlight(_flight(), aircraft: secondAircraftId);

    final result = await reads
        .watchFlights(
          projection: _StubProjection(),
          query: FlightQuery(aircraftId: aircraftId),
        )
        .first;

    expect(result.map((p) => p.record.id), [matchId]);
  });

  test('filters by date range', () async {
    final inRangeId = await commitFlight(
      _flight(offBlocks: UtcInstant.utc(2026, 6, 15, 9)),
    );
    await commitFlight(_flight(offBlocks: UtcInstant.utc(2026, 7, 1, 9)));

    final result = await reads
        .watchFlights(
          projection: _StubProjection(),
          query: const FlightQuery(
            from: CalendarDate(2026, 6, 1),
            to: CalendarDate(2026, 6, 30),
          ),
        )
        .first;

    expect(result.map((p) => p.record.id), [inRangeId]);
  });

  test('filters by aerodrome via a route leg', () async {
    final matchId = await commitFlight(_flight(route: const ['EGKA', 'EGSU']));
    await commitFlight(_flight(route: const ['EGKA', 'EGKB']));

    final result = await reads
        .watchFlights(
          projection: _StubProjection(),
          query: const FlightQuery(aerodromeIdentifier: 'EGSU'),
        )
        .first;

    expect(result.map((p) => p.record.id), [matchId]);
  });

  test('filters by aerodrome via an approach-only match', () async {
    final matchId = await commitFlight(
      _flight(
        route: const ['EGKA', 'EGKB'],
        approaches: const [
          Approach(
            type: ApproachType.ils,
            aerodromeIcao: 'EGHI',
            runway: '20',
            count: 1,
          ),
        ],
      ),
    );
    await commitFlight(_flight());

    final result = await reads
        .watchFlights(
          projection: _StubProjection(),
          query: const FlightQuery(aerodromeIdentifier: 'EGHI'),
        )
        .first;

    expect(result.map((p) => p.record.id), [matchId]);
  });

  test('filters by capacity', () async {
    final instructorId = await commitFlight(
      _flight(capacity: _capacity.copyWith(actingAsInstructor: true)),
    );
    await commitFlight(_flight());

    final result = await reads
        .watchFlights(
          projection: _StubProjection(),
          query: const FlightQuery(
            capacity: CapacityFilter(actingAsInstructor: true),
          ),
        )
        .first;

    expect(result.map((p) => p.record.id), [instructorId]);
  });

  test('combines aircraft and date range filters', () async {
    final matchId = await commitFlight(
      _flight(offBlocks: UtcInstant.utc(2026, 6, 15, 9)),
    );
    await commitFlight(
      _flight(offBlocks: UtcInstant.utc(2026, 6, 15, 9)),
      aircraft: secondAircraftId,
    );
    await commitFlight(_flight(offBlocks: UtcInstant.utc(2026, 7, 15, 9)));

    final result = await reads
        .watchFlights(
          projection: _StubProjection(),
          query: FlightQuery(
            aircraftId: aircraftId,
            from: const CalendarDate(2026, 6, 1),
            to: const CalendarDate(2026, 6, 30),
          ),
        )
        .first;

    expect(result.map((p) => p.record.id), [matchId]);
  });

  test('re-emits when a matching flight is committed', () async {
    // Two separate writes happen after listening starts (createDraft, then
    // commit) — Drift's per-write table invalidation is coarse, so this can
    // produce an intermediate emission between them (still empty, since a
    // draft doesn't match the filter) before the one that actually shows
    // the committed flight. Assert on the first and last emission only,
    // not on an exact count.
    final stream = reads.watchFlights(projection: _StubProjection());
    final emissions = stream.take(3).toList();
    await Future<void>.delayed(Duration.zero);

    final id = await writes.createDraft(_flight(), aircraftId: aircraftId);
    await writes.commit(id);

    final results = await emissions;
    expect(results.first, isEmpty);
    expect(results.last.map((p) => p.record.id), contains(id));
  });

  test('re-emits when a flight is tombstoned', () async {
    final id = await commitFlight(_flight());

    final stream = reads.watchFlights(projection: _StubProjection());
    final emissions = stream.take(2).toList();
    await Future<void>.delayed(Duration.zero);

    await writes.tombstone(id);

    final results = await emissions;
    expect(results[0].map((p) => p.record.id), contains(id));
    expect(results[1].map((p) => p.record.id), isNot(contains(id)));
  });
}
