import 'package:easa_digital_log/domain/model/aircraft.dart';
import 'package:easa_digital_log/domain/model/calendar_date.dart';
import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:easa_digital_log/domain/repository/flight_read_repository.dart';

/// A flight with every field defaulted to something inert, overriding only
/// what a given currency test cares about. Deliberately not a
/// `test/fixtures/` YAML fixture: these are synthetic mechanism probes for
/// the generic evaluator and its rules, not realistic scenarios worth a
/// shared, named fixture -- #53's golden, hand-verified fixture logbook is
/// where that investment belongs.
Flight currencyTestFlight({
  required CalendarDate date,
  CircuitCounts? landings,
  CircuitCounts? takeoffs,
  List<Approach> approaches = const [],
  int holdingProceduresCount = 0,
  String aircraftRegistration = 'G-TEST',
}) {
  final offBlocks = UtcInstant.utc(date.year, date.month, date.day, 10);
  return Flight(
    aircraftRegistration: aircraftRegistration,
    route: const ['EGXX'],
    prePlannedNavigation: false,
    offBlocks: offBlocks,
    onBlocks: offBlocks.add(const Duration(hours: 1)),
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
    takeoffs: takeoffs ?? const CircuitCounts(),
    landings: landings ?? const CircuitCounts(),
    ifrFlightPlanFiled: false,
    actualInstrumentTime: FlightDuration.zero,
    simulatedInstrumentTime: FlightDuration.zero,
    approaches: approaches,
    holdingProceduresCount: holdingProceduresCount,
    trackingPerformed: false,
    remarks: '',
  );
}

const testAircraft = Aircraft(
  registration: 'G-TEST',
  manufacturer: 'Cessna',
  model: '152',
  category: AircraftCategory.aeroplane,
  engineType: EngineType.piston,
  engineCount: 1,
  operatingSurface: OperatingSurface.land,
  requiresMultiCrew: false,
);

FlightRecord currencyTestRecord(
  String id,
  Flight flight, {
  Aircraft? aircraft,
}) => FlightRecord(id: id, flight: flight, aircraft: aircraft ?? testAircraft);
