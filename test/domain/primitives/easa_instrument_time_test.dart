// flutter_test re-exports test/group/expect from package:test_api, so plain
// Dart tests need no separate package:test dependency.
import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:easa_digital_log/domain/primitives/easa_instrument_time.dart';
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
  required bool ifrFlightPlanFiled,
  FlightDuration actualInstrumentTime = FlightDuration.zero,
  FlightDuration simulatedInstrumentTime = FlightDuration.zero,
}) => Flight(
  aircraftRegistration: 'G-ABCD',
  route: const ['EGKA', 'EGKA'],
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
  group('easaInstrumentTime', () {
    test('an IFR flight plan filed credits the whole block as IFR time', () {
      final result = easaInstrumentTime(
        _flight(ifrFlightPlanFiled: true),
        _block,
      );

      expect(result['ifr']?.value, _block);
      expect(result['ifr']?.creditable, isTrue);
    });

    test('no IFR flight plan filed is zero IFR time', () {
      final result = easaInstrumentTime(
        _flight(ifrFlightPlanFiled: false),
        _block,
      );

      expect(result['ifr']?.value, FlightDuration.zero);
      expect(result['ifr']?.creditable, isTrue);
    });

    test('an IFR flight plan filed credits full IFR time even with no actual '
        'or simulated instrument time recorded — the operational condition, '
        'not the meteorological one', () {
      final result = easaInstrumentTime(
        _flight(
          ifrFlightPlanFiled: true,
          actualInstrumentTime: FlightDuration.zero,
          simulatedInstrumentTime: FlightDuration.zero,
        ),
        _block,
      );

      expect(result['ifr']?.value, _block);
    });
  });
}
