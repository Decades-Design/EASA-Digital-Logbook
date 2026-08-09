// flutter_test re-exports test/group/expect from package:test_api, so plain
// Dart tests need no separate package:test dependency.
import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:easa_digital_log/domain/primitives/faa_instrument_time.dart';
import 'package:flutter_test/flutter_test.dart';

const _block = FlightDuration(90); // 1:30

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

Flight _flight({
  bool ifrFlightPlanFiled = false,
  FlightDuration actualInstrumentTime = FlightDuration.zero,
  FlightDuration simulatedInstrumentTime = FlightDuration.zero,
}) => Flight(
  aircraftRegistration: 'N12345',
  route: const ['KJFK', 'KJFK'],
  prePlannedNavigation: false,
  offBlocks: UtcInstant.utc(2026, 1, 1, 9, 0),
  onBlocks: UtcInstant.utc(2026, 1, 1, 10, 30),
  capacity: _capacity(),
  carryingPassengers: false,
  takeoffs: const CircuitCounts(dayFullStop: 1),
  landings: const CircuitCounts(dayFullStop: 1),
  ifrFlightPlanFiled: ifrFlightPlanFiled,
  actualInstrumentTime: actualInstrumentTime,
  simulatedInstrumentTime: simulatedInstrumentTime,
  approaches: const [],
  holdingProceduresCount: 0,
  trackingPerformed: false,
  remarks: '',
);

void main() {
  group('faaInstrumentTime', () {
    test('actual and simulated instrument time pass through independently', () {
      final result = faaInstrumentTime(
        _flight(
          actualInstrumentTime: const FlightDuration(20),
          simulatedInstrumentTime: const FlightDuration(60),
        ),
        _block,
      );

      expect(result['actualInstrument']?.value, const FlightDuration(20));
      expect(result['actualInstrument']?.creditable, isTrue);
      expect(result['simulatedInstrument']?.value, const FlightDuration(60));
      expect(result['simulatedInstrument']?.creditable, isTrue);
    });

    test('zero recorded instrument time is zero, not an error', () {
      final result = faaInstrumentTime(_flight(), _block);

      expect(result['actualInstrument']?.value, FlightDuration.zero);
      expect(result['simulatedInstrument']?.value, FlightDuration.zero);
    });

    test('an IFR flight plan filed with no instrument time recorded still '
        'yields zero FAA instrument time — §61.51(g)(1) has no concept of an '
        'IFR flight plan', () {
      final result = faaInstrumentTime(
        _flight(ifrFlightPlanFiled: true),
        _block,
      );

      expect(result['actualInstrument']?.value, FlightDuration.zero);
      expect(result['simulatedInstrument']?.value, FlightDuration.zero);
    });
  });
}
