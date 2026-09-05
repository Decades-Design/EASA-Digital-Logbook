import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:easa_digital_log/ui/entry/flight_diff.dart';
import 'package:flutter_test/flutter_test.dart';

Flight _flight({
  UtcInstant? onBlocks,
  String remarks = '',
  bool ifrFlightPlanFiled = false,
}) => Flight(
  aircraftRegistration: 'G-ABCD',
  route: const ['EGKA', 'EGKA'],
  prePlannedNavigation: false,
  offBlocks: UtcInstant.utc(2026, 3, 1, 9, 0),
  onBlocks: onBlocks ?? UtcInstant.utc(2026, 3, 1, 10, 0),
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
  ifrFlightPlanFiled: ifrFlightPlanFiled,
  actualInstrumentTime: FlightDuration.zero,
  simulatedInstrumentTime: FlightDuration.zero,
  approaches: const [],
  holdingProceduresCount: 0,
  trackingPerformed: false,
  remarks: remarks,
);

void main() {
  test('an identical flight produces no changes', () {
    final flight = _flight();
    expect(diffFlightsForDisplay(flight, flight), isEmpty);
  });

  test('reports only the fields that actually changed', () {
    final before = _flight(remarks: 'Nav exercise');
    final after = _flight(
      onBlocks: UtcInstant.utc(2026, 3, 1, 10, 30),
      remarks: 'Nav exercise',
      ifrFlightPlanFiled: true,
    );

    final changes = diffFlightsForDisplay(before, after);
    final labels = changes.map((c) => c.label).toSet();

    expect(labels, {'On-blocks', 'Block time', 'IFR flight plan filed'});
    expect(
      changes.firstWhere((c) => c.label == 'IFR flight plan filed').before,
      'No',
    );
    expect(
      changes.firstWhere((c) => c.label == 'IFR flight plan filed').after,
      'Yes',
    );
  });
}
