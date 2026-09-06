import 'dart:io';

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
import 'package:easa_digital_log/domain/repository/flight_read_repository.dart';
import 'package:easa_digital_log/io/foreflight/foreflight_adapter.dart';
import 'package:easa_digital_log/io/foreflight/foreflight_exporter.dart';
import 'package:flutter_test/flutter_test.dart';

/// Exercises the ForeFlight exporter (#70) against a real ForeFlight
/// importer (#69) round trip — the acceptance criterion is equivalence,
/// not a snapshot of the CSV text, so these tests re-import what they
/// export and compare the resulting domain objects rather than strings.
void main() {
  final registry = JurisdictionRegistry(
    ['assets/jurisdictions/us.faa.part61.yaml'].map(
      (path) => parseJurisdictionProfileYaml(File(path).readAsStringSync()),
    ),
  );
  final faaProjection = JurisdictionProjection(
    registry: registry,
    primitives: defaultPrimitives,
    aerodromes: AerodromeDirectory(const []),
    jurisdictionId: 'us.faa.part61',
  );

  const aircraft = Aircraft(
    registration: 'N100AB',
    manufacturer: 'Cessna',
    model: 'C172P Skyhawk',
    icaoTypeDesignator: 'C172',
    category: AircraftCategory.aeroplane,
    engineType: EngineType.piston,
    engineCount: 1,
    operatingSurface: OperatingSurface.land,
    requiresMultiCrew: false,
  );

  test('a plain solo PIC flight round-trips through export then re-import', () {
    final offBlocks = UtcInstant.utc(2026, 3, 15, 14, 0);
    final onBlocks = offBlocks.add(const Duration(minutes: 90));
    final flight = Flight(
      aircraftRegistration: 'N100AB',
      route: const ['KABC', 'KDEF'],
      prePlannedNavigation: false,
      offBlocks: offBlocks,
      onBlocks: onBlocks,
      takeoff: offBlocks.add(const Duration(minutes: 2)),
      landing: onBlocks.subtract(const Duration(minutes: 2)),
      capacity: const PilotCapacity(
        commandAuthority: true,
        soleManipulator: true,
        soleOccupant: true,
        multiPilotOperation: false,
        additionalCrewRequiredByRule: false,
        actingAsInstructor: false,
        actingAsExaminer: false,
        picusClaimed: false,
        picInterventionNotRequired: false,
      ),
      carryingPassengers: false,
      takeoffs: const CircuitCounts(dayFullStop: 1),
      landings: const CircuitCounts(dayFullStop: 1),
      ifrFlightPlanFiled: true,
      actualInstrumentTime: const FlightDuration(30),
      simulatedInstrumentTime: FlightDuration.zero,
      approaches: const [
        Approach(type: ApproachType.ils, aerodromeIcao: 'KDEF', runway: '27'),
      ],
      holdingProceduresCount: 1,
      trackingPerformed: false,
      remarks: 'Great flight, no issues',
    );

    final csv = exportForeFlightCsv(
      flights: [FlightRecord(id: 'f1', flight: flight, aircraft: aircraft)],
      faaProjection: faaProjection,
    );

    final result = ForeFlightAdapter().parse({
      ForeFlightAdapter.logbookKey: csv,
    });

    expect(result.errors, isEmpty);
    expect(result.rows, hasLength(1));
    final reimported = result.rows.single.flight;
    final reimportedAircraft = result.rows.single.aircraft;

    expect(reimportedAircraft, aircraft);

    expect(reimported.aircraftRegistration, flight.aircraftRegistration);
    expect(reimported.route, flight.route);
    expect(reimported.offBlocks, flight.offBlocks);
    expect(reimported.onBlocks, flight.onBlocks);
    expect(reimported.takeoff, flight.takeoff);
    expect(reimported.landing, flight.landing);
    expect(reimported.capacity.commandAuthority, isTrue);
    expect(reimported.capacity.soleManipulator, isTrue);
    expect(reimported.capacity.soleOccupant, isTrue);
    expect(reimported.takeoffs, flight.takeoffs);
    expect(reimported.landings, flight.landings);
    expect(reimported.ifrFlightPlanFiled, isTrue);
    expect(reimported.actualInstrumentTime, flight.actualInstrumentTime);
    expect(reimported.simulatedInstrumentTime, flight.simulatedInstrumentTime);
    expect(reimported.approaches, flight.approaches);
    expect(reimported.holdingProceduresCount, flight.holdingProceduresCount);
    // PilotComments is not one of foreflight_flight_mapper.dart's own
    // `_mappedColumns` — round-tripping it lands in unmappedFields, the
    // same place a real vendor field the importer doesn't recognise
    // would, not back in Flight.remarks directly.
    expect(
      result.rows.single.unmappedFields['PilotComments'],
      'Great flight, no issues',
    );
  });

  test('a flight with no optional data round-trips with every optional field '
      'blank, not fabricated', () {
    final offBlocks = UtcInstant.utc(2026, 4, 1, 9, 0);
    final onBlocks = offBlocks.add(const Duration(minutes: 45));
    final flight = Flight(
      aircraftRegistration: 'N100AB',
      route: const ['KABC', 'KABC'],
      prePlannedNavigation: false,
      offBlocks: offBlocks,
      onBlocks: onBlocks,
      capacity: const PilotCapacity(
        commandAuthority: true,
        soleManipulator: true,
        soleOccupant: true,
        multiPilotOperation: false,
        additionalCrewRequiredByRule: false,
        actingAsInstructor: false,
        actingAsExaminer: false,
        picusClaimed: false,
        picInterventionNotRequired: false,
      ),
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

    final csv = exportForeFlightCsv(
      flights: [FlightRecord(id: 'f1', flight: flight, aircraft: aircraft)],
      faaProjection: faaProjection,
    );

    final result = ForeFlightAdapter().parse({
      ForeFlightAdapter.logbookKey: csv,
    });

    expect(result.errors, isEmpty);
    final reimported = result.rows.single.flight;
    expect(reimported.takeoff, isNull);
    expect(reimported.landing, isNull);
    expect(reimported.approaches, isEmpty);
    expect(reimported.holdingProceduresCount, 0);
    expect(reimported.ifrFlightPlanFiled, isFalse);
  });

  test(
    'column order and header names match a real ForeFlight export exactly',
    () {
      final offBlocks = UtcInstant.utc(2026, 1, 1, 10, 0);
      final flight = Flight(
        aircraftRegistration: 'N100AB',
        route: const ['KABC', 'KDEF'],
        prePlannedNavigation: false,
        offBlocks: offBlocks,
        onBlocks: offBlocks.add(const Duration(minutes: 30)),
        capacity: const PilotCapacity(
          commandAuthority: true,
          soleManipulator: true,
          soleOccupant: true,
          multiPilotOperation: false,
          additionalCrewRequiredByRule: false,
          actingAsInstructor: false,
          actingAsExaminer: false,
          picusClaimed: false,
          picInterventionNotRequired: false,
        ),
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

      final csv = exportForeFlightCsv(
        flights: [FlightRecord(id: 'f1', flight: flight, aircraft: aircraft)],
        faaProjection: faaProjection,
      );
      final lines = csv.split('\n');

      expect(
        lines[0],
        'ForeFlight Logbook Import,This row is required for importing into '
        'ForeFlight. Do not delete or modify.',
      );
      expect(lines[2], 'Aircraft Table');
      expect(
        lines[3],
        'AircraftID,TypeCode,Year,Make,Model,GearType,EngineType,'
        'equipType (FAA),aircraftClass (FAA),complexAircraft (FAA),taa (FAA),'
        'highPerformance (FAA),pressurized (FAA)',
      );
      expect(lines[6], 'Flights Table ');
      expect(
        lines[7],
        'Date,AircraftID,From,To,Route,TimeOut,TimeOff,TimeOn,TimeIn,OnDuty,'
        'OffDuty,TotalTime,PIC,SIC,Night,Solo,CrossCountry,PICUS,MultiPilot,'
        'IFR,Examiner,NVG,NVG Ops,Distance,ActualInstrument,'
        'SimulatedInstrument,HobbsStart,HobbsEnd,TachStart,TachEnd,Holds,'
        'Approach1,Approach2,Approach3,Approach4,Approach5,Approach6,'
        'DualGiven,DualReceived,SimulatedFlight,GroundTraining,'
        'GroundTrainingGiven,InstructorName,InstructorComments,Person1,'
        'Person2,Person3,Person4,Person5,Person6,PilotComments,'
        'Flight Review (FAA),IPC (FAA),Checkride (FAA),FAA 61.58 (FAA),'
        'NVG Proficiency (FAA),Takeoff Day,Takeoff Day Towered,'
        'Landing Full-Stop Day,Landing Full-Stop Day Towered,DayTakeoffs,'
        'DayLandingsFullStop,NightTakeoffs,NightLandingsFullStop,AllLandings',
      );
    },
  );

  test('the export filename embeds the requested date range', () {
    final name = foreFlightExportFilename(
      from: const CalendarDate(2026, 1, 1),
      to: const CalendarDate(2026, 6, 30),
    );

    expect(name, 'logbook_template_2026-01-01_to_2026-06-30.csv');
  });
}
