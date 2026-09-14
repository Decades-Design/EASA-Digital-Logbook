import 'dart:convert';

import 'package:drift/drift.dart' show OrderingTerm;
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

Flight _draft({String remarks = ''}) {
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

  Future<String> committedFlight() async {
    final id = await flights.createDraft(_draft(), aircraftId: aircraftId);
    await flights.commit(id);
    return id;
  }

  // sealedByExportId references exportRecordsTable (#83), so sealForExport
  // tests need a real row there for the FK to accept — an id that only
  // exists as a bare string would fail with a foreign key constraint error
  // regardless of sealForExport's own logic.
  Future<void> insertExportRecord(String id) => db
      .into(db.exportRecordsTable)
      .insert(
        ExportRecordRow(
          id: id,
          format: 'test',
          rangeFrom: '2026-06-01',
          rangeTo: '2026-06-30',
          exportedAt: DateTime.now().toUtc().millisecondsSinceEpoch,
        ),
      );

  test('commit sets committedAt and nothing else changes', () async {
    final id = await flights.createDraft(
      _draft(remarks: 'first'),
      aircraftId: aircraftId,
    );
    await flights.commit(id);

    final row = await (db.select(
      db.flightsTable,
    )..where((t) => t.id.equals(id))).getSingle();
    expect(row.committedAt, isNotNull);
    expect(row.remarks, 'first');
  });

  test('commit throws if already committed', () async {
    final id = await committedFlight();
    expect(() => flights.commit(id), throwsStateError);
  });

  test('updateCommitted writes exactly one edit revision with the correct old '
      'values, and the row reflects the new values', () async {
    final id = await flights.createDraft(
      _draft(remarks: 'first'),
      aircraftId: aircraftId,
    );
    await flights.commit(id);

    await flights.updateCommitted(
      id,
      _draft(remarks: 'corrected'),
      reason: 'typo',
    );

    final row = await (db.select(
      db.flightsTable,
    )..where((t) => t.id.equals(id))).getSingle();
    expect(row.remarks, 'corrected');

    final revisions = await (db.select(
      db.flightRevisionsTable,
    )..where((t) => t.flightId.equals(id))).get();
    expect(revisions, hasLength(1));
    expect(revisions.single.kind, 'edit');
    expect(revisions.single.reason, 'typo');

    final changed =
        jsonDecode(revisions.single.changedFields) as Map<String, dynamic>;
    expect(changed['remarks'], 'first');
  });

  test('updateCommitted captures a route-only change too, which _diffRows '
      'alone (flat FlightsTable columns only) never sees', () async {
    final id = await flights.createDraft(_draft(), aircraftId: aircraftId);
    await flights.commit(id);

    await flights.updateCommitted(
      id,
      Flight(
        aircraftRegistration: 'G-ABCD',
        route: const ['EGKA', 'EGTB', 'EGKB'],
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
      ),
    );

    final revisions = await (db.select(
      db.flightRevisionsTable,
    )..where((t) => t.flightId.equals(id))).get();
    expect(revisions, hasLength(1));
    final changed =
        jsonDecode(revisions.single.changedFields) as Map<String, dynamic>;
    expect(changed['route'], ['EGKA', 'EGKB']);
  });

  test(
    'two edits recorded back-to-back never tie on recordedAt, even though '
    'an in-memory database has no real clock latency between them — the '
    'gap reconstructRowAsOf needs strict ordering to tell revisions apart',
    () async {
      final id = await committedFlight();

      await flights.updateCommitted(id, _draft(remarks: 'first'));
      await flights.updateCommitted(id, _draft(remarks: 'second'));

      final revisions =
          await (db.select(db.flightRevisionsTable)
                ..where((t) => t.flightId.equals(id))
                ..orderBy([(t) => OrderingTerm.asc(t.recordedAt)]))
              .get();
      expect(revisions, hasLength(2));
      expect(revisions[0].recordedAt, lessThan(revisions[1].recordedAt));
    },
  );

  test('updateCommitted throws on a draft', () async {
    final id = await flights.createDraft(_draft(), aircraftId: aircraftId);
    expect(() => flights.updateCommitted(id, _draft()), throwsStateError);
  });

  test('updateCommitted throws on a tombstoned flight', () async {
    final id = await committedFlight();
    await flights.tombstone(id);
    expect(() => flights.updateCommitted(id, _draft()), throwsStateError);
  });

  test('tombstone sets tombstonedAt and writes a tombstone revision', () async {
    final id = await committedFlight();
    await flights.tombstone(id, reason: 'duplicate entry');

    final row = await (db.select(
      db.flightsTable,
    )..where((t) => t.id.equals(id))).getSingle();
    expect(row.tombstonedAt, isNotNull);

    final revisions = await (db.select(
      db.flightRevisionsTable,
    )..where((t) => t.flightId.equals(id))).get();
    expect(revisions.single.kind, 'tombstone');
    expect(revisions.single.reason, 'duplicate entry');
  });

  test('tombstone throws on a draft', () async {
    final id = await flights.createDraft(_draft(), aircraftId: aircraftId);
    expect(() => flights.tombstone(id), throwsStateError);
  });

  test(
    'a tombstoned flight is excluded from a basic active-flights query',
    () async {
      final id = await committedFlight();
      await flights.tombstone(id);

      final active = await (db.select(
        db.flightsTable,
      )..where((t) => t.tombstonedAt.isNull())).get();
      expect(active.map((r) => r.id), isNot(contains(id)));
    },
  );

  test('restore clears tombstonedAt and writes a restore revision', () async {
    final id = await committedFlight();
    await flights.tombstone(id);

    await flights.restore(id, reason: 'reinstated');

    final row = await (db.select(
      db.flightsTable,
    )..where((t) => t.id.equals(id))).getSingle();
    expect(row.tombstonedAt, isNull);

    final revisions = await (db.select(
      db.flightRevisionsTable,
    )..where((t) => t.flightId.equals(id))).get();
    expect(revisions.last.kind, 'restore');
  });

  test('restore throws if not tombstoned', () async {
    final id = await committedFlight();
    expect(() => flights.restore(id), throwsStateError);
  });

  test('sealForExport commits every draft flight passed and sets '
      'sealedByExportId, leaving an already-committed flight in the list '
      'untouched', () async {
    final draftId = await flights.createDraft(_draft(), aircraftId: aircraftId);
    final alreadyCommittedId = await committedFlight();
    await insertExportRecord('export-1');

    await flights.sealForExport(
      flightIds: [draftId, alreadyCommittedId],
      exportRecordId: 'export-1',
    );

    final draftRow = await (db.select(
      db.flightsTable,
    )..where((t) => t.id.equals(draftId))).getSingle();
    expect(draftRow.committedAt, isNotNull);
    expect(draftRow.sealedByExportId, 'export-1');

    final alreadyCommittedRow = await (db.select(
      db.flightsTable,
    )..where((t) => t.id.equals(alreadyCommittedId))).getSingle();
    expect(
      alreadyCommittedRow.sealedByExportId,
      isNull,
      reason: 'this flight was committed before the export, not by it',
    );
  });

  test(
    'sealForExport is atomic: nothing is sealed if any flight id is unknown',
    () async {
      final draftId = await flights.createDraft(
        _draft(),
        aircraftId: aircraftId,
      );
      await insertExportRecord('export-1');

      await expectLater(
        () => flights.sealForExport(
          flightIds: [draftId, 'no-such-flight'],
          exportRecordId: 'export-1',
        ),
        throwsA(anything),
      );

      final draftRow = await (db.select(
        db.flightsTable,
      )..where((t) => t.id.equals(draftId))).getSingle();
      expect(
        draftRow.committedAt,
        isNull,
        reason: 'the whole transaction must roll back, sealing nothing',
      );
    },
  );
}
