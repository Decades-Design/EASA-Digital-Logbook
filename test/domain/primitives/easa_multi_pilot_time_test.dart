// flutter_test re-exports test/group/expect from package:test_api, so plain
// Dart tests need no separate package:test dependency.
import 'package:easa_digital_log/domain/model/aircraft.dart';
import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:easa_digital_log/domain/primitives/easa_multi_pilot_time.dart';
import 'package:flutter_test/flutter_test.dart';

const _block = FlightDuration(90); // 1:30

Aircraft _aircraft({
  required int engineCount,
  bool requiresMultiCrew = false,
}) => Aircraft(
  registration: 'G-ABCD',
  manufacturer: 'Test',
  model: 'Test',
  category: AircraftCategory.aeroplane,
  engineType: EngineType.piston,
  engineCount: engineCount,
  operatingSurface: OperatingSurface.land,
  requiresMultiCrew: requiresMultiCrew,
);

Flight _flight({required bool multiPilotOperation}) => Flight(
  aircraftRegistration: 'G-ABCD',
  route: const ['EGKA', 'EGKA'],
  prePlannedNavigation: false,
  offBlocks: UtcInstant.utc(2026, 1, 1, 9, 0),
  onBlocks: UtcInstant.utc(2026, 1, 1, 10, 30),
  capacity: PilotCapacity(
    commandAuthority: true,
    soleManipulator: true,
    soleOccupant: !multiPilotOperation,
    multiPilotOperation: multiPilotOperation,
    additionalCrewRequiredByRule: multiPilotOperation,
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

void main() {
  group('easaMultiPilotTime', () {
    test('a single-pilot, single-engine flight credits that bucket only', () {
      final result = easaMultiPilotTime(
        _flight(multiPilotOperation: false),
        _aircraft(engineCount: 1),
        _block,
      );

      expect(result['singlePilotSingleEngine']?.value, _block);
      expect(result['singlePilotMultiEngine']?.value, FlightDuration.zero);
      expect(result['multiPilot']?.value, FlightDuration.zero);
    });

    test('a single-pilot, multi-engine flight credits that bucket only', () {
      final result = easaMultiPilotTime(
        _flight(multiPilotOperation: false),
        _aircraft(engineCount: 2),
        _block,
      );

      expect(result['singlePilotMultiEngine']?.value, _block);
      expect(result['singlePilotSingleEngine']?.value, FlightDuration.zero);
      expect(result['multiPilot']?.value, FlightDuration.zero);
    });

    test('a multi-crew operation in a single-pilot-certified aircraft is '
        'multi-pilot time — actual crew composition, not aircraft '
        'certification, decides the split', () {
      final result = easaMultiPilotTime(
        _flight(multiPilotOperation: true),
        _aircraft(engineCount: 1, requiresMultiCrew: false),
        _block,
      );

      expect(result['multiPilot']?.value, _block);
      expect(result['multiPilot']?.creditable, isTrue);
      expect(result['singlePilotSingleEngine']?.value, FlightDuration.zero);
      expect(result['singlePilotMultiEngine']?.value, FlightDuration.zero);
    });

    test('the three quantities always sum to block time', () {
      for (final multiPilotOperation in [true, false]) {
        for (final engineCount in [1, 2]) {
          final result = easaMultiPilotTime(
            _flight(multiPilotOperation: multiPilotOperation),
            _aircraft(engineCount: engineCount),
            _block,
          );

          final total =
              result['multiPilot']!.value +
              result['singlePilotSingleEngine']!.value +
              result['singlePilotMultiEngine']!.value;
          expect(total, _block);
        }
      }
    });
  });
}
