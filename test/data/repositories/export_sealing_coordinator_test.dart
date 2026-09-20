import 'package:drift/native.dart';
import 'package:easa_digital_log/data/database.dart';
import 'package:easa_digital_log/data/repositories/aircraft_repository.dart';
import 'package:easa_digital_log/data/repositories/export_record_repository_drift.dart';
import 'package:easa_digital_log/data/repositories/export_sealing_coordinator_drift.dart';
import 'package:easa_digital_log/data/repositories/flight_repository_drift.dart';
import 'package:easa_digital_log/domain/model/aircraft.dart';
import 'package:easa_digital_log/domain/model/calendar_date.dart';
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

Flight _flightOn(DateTime offBlocksUtc) => Flight(
  aircraftRegistration: 'G-ABCD',
  route: const ['EGKA', 'EGKB'],
  prePlannedNavigation: false,
  offBlocks: UtcInstant.fromDateTime(offBlocksUtc),
  onBlocks: UtcInstant.fromDateTime(offBlocksUtc.add(const Duration(hours: 1))),
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
  late DriftExportRecordRepository exportRecords;
  late DriftExportSealingCoordinator coordinator;
  late String aircraftId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    flights = DriftFlightRepository(db);
    exportRecords = DriftExportRecordRepository(db);
    coordinator = DriftExportSealingCoordinator(db, exportRecords, flights);
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

  test(
    'recordExportAndSeal records the export and seals every draft flight',
    () async {
      final draftId = await flights.createDraft(
        _flightOn(DateTime.utc(2026, 1, 15, 9)),
        aircraftId: aircraftId,
      );

      final exportRecordId = await coordinator.recordExportAndSeal(
        format: 'AMC1 FCL.050',
        from: const CalendarDate(2026, 1, 1),
        to: const CalendarDate(2026, 1, 31),
        draftFlightIds: [draftId],
      );

      expect(exportRecordId, isNotEmpty);
      final overlapping = await exportRecords.findOverlapping(
        format: 'AMC1 FCL.050',
        from: const CalendarDate(2026, 1, 1),
        to: const CalendarDate(2026, 1, 31),
      );
      expect(overlapping.single.id, exportRecordId);

      final flightRow = await (db.select(
        db.flightsTable,
      )..where((t) => t.id.equals(draftId))).getSingle();
      expect(flightRow.committedAt, isNotNull);
      expect(flightRow.sealedByExportId, exportRecordId);
    },
  );

  test(
    'a sealing failure rolls back the export record too — no stray ledger '
    'entry survives a partial failure (#83\'s residual atomicity gap)',
    () async {
      final draftId = await flights.createDraft(
        _flightOn(DateTime.utc(2026, 1, 15, 9)),
        aircraftId: aircraftId,
      );

      await expectLater(
        coordinator.recordExportAndSeal(
          format: 'AMC1 FCL.050',
          from: const CalendarDate(2026, 1, 1),
          to: const CalendarDate(2026, 1, 31),
          draftFlightIds: [draftId, 'no-such-flight'],
        ),
        throwsStateError,
      );

      // Neither half of the operation happened: no ledger row...
      final overlapping = await exportRecords.findOverlapping(
        format: 'AMC1 FCL.050',
        from: const CalendarDate(2026, 1, 1),
        to: const CalendarDate(2026, 1, 31),
      );
      expect(overlapping, isEmpty);

      // ...and the flight that would have been sealed is still a draft.
      final flightRow = await (db.select(
        db.flightsTable,
      )..where((t) => t.id.equals(draftId))).getSingle();
      expect(flightRow.committedAt, isNull);
      expect(flightRow.sealedByExportId, isNull);
    },
  );
}
