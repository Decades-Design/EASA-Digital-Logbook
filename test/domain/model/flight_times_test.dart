// flutter_test re-exports test/group/expect from package:test_api, so plain
// Dart tests need no separate package:test dependency.
import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/flight_times.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:flutter_test/flutter_test.dart';

PilotCapacity _capacity() => const PilotCapacity(
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

Flight _flight({UtcInstant? takeoff, UtcInstant? landing}) => Flight(
  aircraftRegistration: 'G-ABCD',
  route: const ['EGKA', 'EGKA'],
  prePlannedNavigation: false,
  offBlocks: UtcInstant.utc(2026, 1, 1, 9, 0),
  onBlocks: UtcInstant.utc(2026, 1, 1, 10, 30),
  takeoff: takeoff,
  landing: landing,
  capacity: _capacity(),
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
  group('FlightTimes.blockTime', () {
    test('is off-blocks to on-blocks, always available', () {
      final flight = _flight();

      expect(flight.blockTime, const FlightDuration(90));
    });
  });

  group('FlightTimes.airborneTime', () {
    test('is null when neither takeoff nor landing is recorded', () {
      final flight = _flight();

      expect(flight.airborneTime, isNull);
    });

    test('is null when only takeoff is recorded', () {
      final flight = _flight(takeoff: UtcInstant.utc(2026, 1, 1, 9, 5));

      expect(flight.airborneTime, isNull);
    });

    test('is null when only landing is recorded', () {
      final flight = _flight(landing: UtcInstant.utc(2026, 1, 1, 10, 25));

      expect(flight.airborneTime, isNull);
    });

    test('is takeoff to landing when both are recorded, distinct from '
        'block time', () {
      final flight = _flight(
        takeoff: UtcInstant.utc(2026, 1, 1, 9, 5),
        landing: UtcInstant.utc(2026, 1, 1, 10, 25),
      );

      expect(flight.airborneTime, const FlightDuration(80));
      expect(flight.airborneTime, isNot(flight.blockTime));
    });
  });
}
