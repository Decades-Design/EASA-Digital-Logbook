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

Flight _flight({int hour = 10}) => Flight(
  aircraftRegistration: 'G-ABCD',
  route: const ['EGKA', 'EGKB'],
  prePlannedNavigation: false,
  offBlocks: UtcInstant.utc(2026, 6, 1, hour),
  onBlocks: UtcInstant.utc(2026, 6, 1, hour + 1),
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

  test('applyImportBatch creates every flight as a draft tagged with one new '
      'batch id, and records the batch', () async {
    final batchId = await flights.applyImportBatch(
      sourceLabel: 'Test importer',
      flights: [
        (flight: _flight(hour: 9), aircraftId: aircraftId),
        (flight: _flight(hour: 11), aircraftId: aircraftId),
      ],
    );

    final drafts = await db.select(db.flightsTable).get();
    expect(drafts, hasLength(2));
    expect(drafts.every((row) => row.importBatchId == batchId), isTrue);
    expect(drafts.every((row) => row.committedAt == null), isTrue);

    final batches = await flights.listImportBatches();
    expect(batches, hasLength(1));
    expect(batches.single.id, batchId);
    expect(batches.single.sourceLabel, 'Test importer');
    expect(batches.single.flightCount, 2);
    expect(batches.single.isUndone, isFalse);
  });

  test('a failure partway through applyImportBatch writes nothing at all — '
      'not the batch row, not the flights already processed', () async {
    final badAircraftId = 'nonexistent-aircraft-id';

    await expectLater(
      flights.applyImportBatch(
        sourceLabel: 'Test importer',
        flights: [
          (flight: _flight(hour: 8), aircraftId: aircraftId),
          (flight: _flight(hour: 9), aircraftId: aircraftId),
          // This entry's aircraftId violates the flights.aircraft_id
          // foreign key — the failure injected midway through the batch.
          (flight: _flight(hour: 10), aircraftId: badAircraftId),
          (flight: _flight(hour: 11), aircraftId: aircraftId),
        ],
      ),
      throwsA(anything),
    );

    expect(await db.select(db.flightsTable).get(), isEmpty);
    expect(await db.select(db.importBatchesTable).get(), isEmpty);
    expect(await flights.listImportBatches(), isEmpty);
  });

  test(
    'undoImportBatch deletes every draft in the batch and marks it undone',
    () async {
      final batchId = await flights.applyImportBatch(
        sourceLabel: 'Test importer',
        flights: [
          (flight: _flight(hour: 9), aircraftId: aircraftId),
          (flight: _flight(hour: 11), aircraftId: aircraftId),
        ],
      );

      final result = await flights.undoImportBatch(batchId);

      expect(result.deletedDraftCount, 2);
      expect(result.tombstonedCommittedCount, 0);
      expect(await db.select(db.flightsTable).get(), isEmpty);

      final batches = await flights.listImportBatches();
      expect(batches.single.isUndone, isTrue);
      expect(batches.single.flightCount, 0);
    },
  );

  test('undoImportBatch tombstones an already-committed flight instead of '
      'deleting it, and reports the split', () async {
    final batchId = await flights.applyImportBatch(
      sourceLabel: 'Test importer',
      flights: [
        (flight: _flight(hour: 9), aircraftId: aircraftId),
        (flight: _flight(hour: 11), aircraftId: aircraftId),
      ],
    );
    final committedRow =
        await (db.select(db.flightsTable)..where(
              (t) => t.offBlocks.equals(
                UtcInstant.utc(2026, 6, 1, 9).millisecondsSinceEpoch,
              ),
            ))
            .getSingle();
    await flights.commit(committedRow.id);

    final result = await flights.undoImportBatch(batchId);

    expect(result.deletedDraftCount, 1);
    expect(result.tombstonedCommittedCount, 1);

    final remaining = await db.select(db.flightsTable).get();
    expect(remaining, hasLength(1));
    expect(remaining.single.id, committedRow.id);
    expect(remaining.single.tombstonedAt, isNotNull);
    expect(remaining.single.importBatchId, batchId);
  });

  test('undoImportBatch throws for an unknown batch id', () async {
    expect(
      () => flights.undoImportBatch('nonexistent-batch'),
      throwsStateError,
    );
  });

  test('undoImportBatch throws if the batch is already undone', () async {
    final batchId = await flights.applyImportBatch(
      sourceLabel: 'Test importer',
      flights: [(flight: _flight(), aircraftId: aircraftId)],
    );
    await flights.undoImportBatch(batchId);

    expect(() => flights.undoImportBatch(batchId), throwsStateError);
  });

  test(
    'editing a draft created by an import preserves its importBatchId',
    () async {
      final batchId = await flights.applyImportBatch(
        sourceLabel: 'Test importer',
        flights: [(flight: _flight(), aircraftId: aircraftId)],
      );
      final row = await db.select(db.flightsTable).getSingle();

      await flights.updateDraft(row.id, _flight(hour: 12));

      final updated = await (db.select(
        db.flightsTable,
      )..where((t) => t.id.equals(row.id))).getSingle();
      expect(updated.importBatchId, batchId);
    },
  );

  test('editing a committed flight created by an import preserves its '
      'importBatchId', () async {
    final batchId = await flights.applyImportBatch(
      sourceLabel: 'Test importer',
      flights: [(flight: _flight(), aircraftId: aircraftId)],
    );
    final row = await db.select(db.flightsTable).getSingle();
    await flights.commit(row.id);

    await flights.updateCommitted(row.id, _flight(hour: 12));

    final updated = await (db.select(
      db.flightsTable,
    )..where((t) => t.id.equals(row.id))).getSingle();
    expect(updated.importBatchId, batchId);
  });
}
