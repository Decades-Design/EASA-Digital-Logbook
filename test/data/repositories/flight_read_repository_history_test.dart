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
  String remarks = '',
}) {
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
    remarks: remarks,
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

  test('returns null for a draft', () async {
    final id = await writes.createDraft(_flight(), aircraftId: aircraftId);

    expect(await reads.revisionHistory(id), isNull);
  });

  test('returns null for an unknown id', () async {
    expect(await reads.revisionHistory('nonexistent'), isNull);
  });

  test(
    'a committed flight with no edits has just the synthetic commit entry',
    () async {
      final id = await writes.createDraft(_flight(), aircraftId: aircraftId);
      await writes.commit(id);

      final history = await reads.revisionHistory(id);

      expect(history, isNotNull);
      expect(history!.isTombstoned, isFalse);
      expect(history.entries, hasLength(1));
      expect(history.entries.single.kind, FlightRevisionKind.commit);
      expect(history.entries.single.before, isNull);
      expect(history.entries.single.after, _flight());
    },
  );

  test('an edit to a flat field appears newest-first, with the reason and '
      'exact before/after values', () async {
    final id = await writes.createDraft(_flight(), aircraftId: aircraftId);
    await writes.commit(id);
    await writes.updateCommitted(
      id,
      _flight(remarks: 'landed long'),
      reason: 'forgot to note it at the time',
    );

    final history = await reads.revisionHistory(id);

    expect(history!.entries, hasLength(2));
    final edit = history.entries[0];
    final commit = history.entries[1];

    expect(edit.kind, FlightRevisionKind.edit);
    expect(edit.reason, 'forgot to note it at the time');
    expect(edit.before, _flight());
    expect(edit.after, _flight(remarks: 'landed long'));

    expect(commit.kind, FlightRevisionKind.commit);
    expect(commit.after, _flight());
  });

  test('a route-only edit is captured in history — the gap where '
      '_diffRows alone never sees child-table changes', () async {
    final id = await writes.createDraft(_flight(), aircraftId: aircraftId);
    await writes.commit(id);
    await writes.updateCommitted(
      id,
      _flight(route: const ['EGKA', 'EGTB', 'EGKB']),
    );

    final history = await reads.revisionHistory(id);

    expect(history!.entries, hasLength(2));
    final edit = history.entries[0];
    expect(edit.before!.route, ['EGKA', 'EGKB']);
    expect(edit.after.route, ['EGKA', 'EGTB', 'EGKB']);
  });

  test(
    'chains two edits, each reconstructing the correct intermediate state',
    () async {
      final id = await writes.createDraft(_flight(), aircraftId: aircraftId);
      await writes.commit(id);
      await writes.updateCommitted(id, _flight(remarks: 'first edit'));
      await writes.updateCommitted(id, _flight(remarks: 'second edit'));

      final history = await reads.revisionHistory(id);

      expect(history!.entries, hasLength(3));
      expect(history.entries[0].after.remarks, 'second edit');
      expect(history.entries[0].before!.remarks, 'first edit');
      expect(history.entries[1].after.remarks, 'first edit');
      expect(history.entries[1].before!.remarks, '');
      expect(history.entries[2].kind, FlightRevisionKind.commit);
      expect(history.entries[2].after.remarks, '');
    },
  );

  test(
    'a tombstoned flight reports isTombstoned and a tombstone entry',
    () async {
      final id = await writes.createDraft(_flight(), aircraftId: aircraftId);
      await writes.commit(id);
      await writes.tombstone(id, reason: 'duplicate entry');

      final history = await reads.revisionHistory(id);

      expect(history!.isTombstoned, isTrue);
      expect(history.entries, hasLength(2));
      expect(history.entries[0].kind, FlightRevisionKind.tombstone);
      expect(history.entries[0].reason, 'duplicate entry');
    },
  );

  test('restoring a tombstoned flight clears isTombstoned', () async {
    final id = await writes.createDraft(_flight(), aircraftId: aircraftId);
    await writes.commit(id);
    await writes.tombstone(id);
    await writes.restore(id);

    final history = await reads.revisionHistory(id);

    expect(history!.isTombstoned, isFalse);
    expect(history.entries, hasLength(3));
    expect(history.entries[0].kind, FlightRevisionKind.restore);
    expect(history.entries[1].kind, FlightRevisionKind.tombstone);
  });
}
