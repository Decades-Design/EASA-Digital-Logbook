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

  test('opening balance sums committed flights before the range; content '
      'rows are committed+draft flights in range; draft count is only '
      'drafts in range', () async {
    final beforeRangeId = await flights.createDraft(
      _flightOn(DateTime.utc(2025, 12, 15, 9)),
      aircraftId: aircraftId,
    );
    await flights.commit(beforeRangeId);
    final inRangeCommittedId = await flights.createDraft(
      _flightOn(DateTime.utc(2026, 1, 10, 9)),
      aircraftId: aircraftId,
    );
    await flights.commit(inRangeCommittedId);
    final inRangeDraftId = await flights.createDraft(
      _flightOn(DateTime.utc(2026, 1, 20, 9)),
      aircraftId: aircraftId,
    );
    final afterRangeId = await flights.createDraft(
      _flightOn(DateTime.utc(2026, 3, 1, 9)),
      aircraftId: aircraftId,
    );
    await flights.commit(afterRangeId);

    final plan = await buildAmc1Fcl050ExportPlan(
      flightReadRepository: flightReads,
      easaProjection: easaProjection,
      from: const CalendarDate(2026, 1, 1),
      to: const CalendarDate(2026, 1, 31),
    );

    expect(plan.draftFlightIds, [inRangeDraftId]);
    expect(
      plan.contentRows,
      hasLength(2),
    ); // in-range committed + in-range draft
    // The one before-range flight's block time is exactly the 1-hour
    // offBlocks-to-onBlocks span _flightOn always sets.
    expect(plan.openingBalance.totalTimeOfFlight.inMinutes, 60);
  });
}
