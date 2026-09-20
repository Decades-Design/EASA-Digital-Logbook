import 'package:drift/native.dart';
import 'package:easa_digital_log/data/database.dart';
import 'package:easa_digital_log/data/repositories/aircraft_repository.dart';
import 'package:easa_digital_log/data/repositories/flight_read_repository_drift.dart';
import 'package:easa_digital_log/data/repositories/flight_repository_drift.dart';
import 'package:easa_digital_log/domain/jurisdiction/jurisdiction_profile.dart';
import 'package:easa_digital_log/domain/jurisdiction/jurisdiction_registry.dart';
import 'package:easa_digital_log/domain/model/aerodrome_directory.dart';
import 'package:easa_digital_log/domain/model/aircraft.dart';
import 'package:easa_digital_log/domain/model/calendar_date.dart';
import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:easa_digital_log/domain/primitives/default_primitives.dart';
import 'package:easa_digital_log/domain/projection/jurisdiction_projection.dart';
import 'package:easa_digital_log/export/amc1_fcl050_export_plan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

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
  late JurisdictionProjection easaProjection;
  late DriftFlightRepository flights;
  late DriftFlightReadRepository flightReads;
  late String aircraftId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final yaml = File(
      'assets/jurisdictions/eu.easa.part-fcl.yaml',
    ).readAsStringSync();
    easaProjection = JurisdictionProjection(
      registry: JurisdictionRegistry([parseJurisdictionProfileYaml(yaml)]),
      primitives: defaultPrimitives,
      aerodromes: AerodromeDirectory(const []),
      jurisdictionId: 'eu.easa.part-fcl',
    );
    flights = DriftFlightRepository(db);
    flightReads = DriftFlightReadRepository(db);
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

  // Task 3's implementer found that FlightsTable.sealedByExportId is a real
  // foreign key to export_records.id, enforced by PRAGMA foreign_keys = ON.
  // sealForExport with a bare exportRecordId string and no corresponding row
  // throws SqliteException(787) before any of the behavior under test runs.
  // This mirrors DriftExportRecordRepository.recordExport's row shape so the
  // three acceptance tests below exercise sealing itself, not an unrelated FK
  // failure.
  Future<void> insertExportRecord(String id) => db
      .into(db.exportRecordsTable)
      .insert(
        ExportRecordRow(
          id: id,
          format: 'test',
          rangeFrom: '2026-01-01',
          rangeTo: '2026-01-31',
          exportedAt: DateTime.now().toUtc().millisecondsSinceEpoch,
        ),
      );

  test(
    'export seals exactly the flights in range, not flights outside it',
    () async {
      final inRangeId = await flights.createDraft(
        _flightOn(DateTime.utc(2026, 1, 15, 9)),
        aircraftId: aircraftId,
      );
      final outOfRangeId = await flights.createDraft(
        _flightOn(DateTime.utc(2026, 3, 1, 9)),
        aircraftId: aircraftId,
      );

      final plan = await buildAmc1Fcl050ExportPlan(
        flightReadRepository: flightReads,
        easaProjection: easaProjection,
        from: const CalendarDate(2026, 1, 1),
        to: const CalendarDate(2026, 1, 31),
      );
      expect(plan.draftFlightIds, [inRangeId]);

      await insertExportRecord('export-1');
      await flights.sealForExport(
        flightIds: plan.draftFlightIds,
        exportRecordId: 'export-1',
      );

      final inRangeRow = await (db.select(
        db.flightsTable,
      )..where((t) => t.id.equals(inRangeId))).getSingle();
      expect(inRangeRow.committedAt, isNotNull);
      expect(inRangeRow.sealedByExportId, 'export-1');

      final outOfRangeRow = await (db.select(
        db.flightsTable,
      )..where((t) => t.id.equals(outOfRangeId))).getSingle();
      expect(outOfRangeRow.committedAt, isNull);
      expect(outOfRangeRow.sealedByExportId, isNull);
    },
  );

  test('a failed export seals nothing', () async {
    final draftId = await flights.createDraft(
      _flightOn(DateTime.utc(2026, 1, 15, 9)),
      aircraftId: aircraftId,
    );

    final plan = await buildAmc1Fcl050ExportPlan(
      flightReadRepository: flightReads,
      easaProjection: easaProjection,
      from: const CalendarDate(2026, 1, 1),
      to: const CalendarDate(2026, 1, 31),
    );
    expect(plan.draftFlightIds, [draftId]);

    // A failed export never reaches sealForExport at all -- the real
    // screen (Task 8) only calls it after a successful file write. Model
    // that failure by simply not calling it, and confirm the flight is
    // still draft. sealForExport's own mid-call atomicity (a partially
    // invalid flightIds list rolling back everything) is Task 3's own
    // "unknown flight id" test, not duplicated here.
    final row = await (db.select(
      db.flightsTable,
    )..where((t) => t.id.equals(draftId))).getSingle();
    expect(row.committedAt, isNull);
  });

  test('re-exporting an already-sealed range changes no state', () async {
    final draftId = await flights.createDraft(
      _flightOn(DateTime.utc(2026, 1, 15, 9)),
      aircraftId: aircraftId,
    );

    final firstPlan = await buildAmc1Fcl050ExportPlan(
      flightReadRepository: flightReads,
      easaProjection: easaProjection,
      from: const CalendarDate(2026, 1, 1),
      to: const CalendarDate(2026, 1, 31),
    );
    await insertExportRecord('export-1');
    await flights.sealForExport(
      flightIds: firstPlan.draftFlightIds,
      exportRecordId: 'export-1',
    );
    final afterFirstSeal = await (db.select(
      db.flightsTable,
    )..where((t) => t.id.equals(draftId))).getSingle();

    final secondPlan = await buildAmc1Fcl050ExportPlan(
      flightReadRepository: flightReads,
      easaProjection: easaProjection,
      from: const CalendarDate(2026, 1, 1),
      to: const CalendarDate(2026, 1, 31),
    );
    expect(secondPlan.draftCount, 0);
    await insertExportRecord('export-2');
    await flights.sealForExport(
      flightIds: secondPlan.draftFlightIds,
      exportRecordId: 'export-2',
    );

    final afterSecondSeal = await (db.select(
      db.flightsTable,
    )..where((t) => t.id.equals(draftId))).getSingle();
    expect(afterSecondSeal.committedAt, afterFirstSeal.committedAt);
    expect(afterSecondSeal.sealedByExportId, afterFirstSeal.sealedByExportId);
  });
}
