import 'package:easa_digital_log/data/mappers/flight_mapper.dart';
import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:flutter_test/flutter_test.dart';

Flight _sampleFlight() {
  return Flight(
    aircraftRegistration: 'G-ABCD',
    route: const ['EGKA', 'EGKB'],
    prePlannedNavigation: true,
    offBlocks: UtcInstant.utc(2026, 6, 1, 10, 0),
    onBlocks: UtcInstant.utc(2026, 6, 1, 11, 30),
    takeoff: UtcInstant.utc(2026, 6, 1, 10, 5),
    landing: UtcInstant.utc(2026, 6, 1, 11, 25),
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
    approaches: const [
      Approach(
        type: ApproachType.ils,
        aerodromeIcao: 'EGKB',
        runway: '20',
        count: 2,
      ),
    ],
    holdingProceduresCount: 0,
    trackingPerformed: false,
    remarks: '',
  );
}

void main() {
  group('flightToRow', () {
    test('flattens capacity, times and counts onto the row', () {
      final row = flightToRow(_sampleFlight(), id: 'f1', aircraftId: 'a1');

      expect(row.id, 'f1');
      expect(row.aircraftId, 'a1');
      expect(
        row.offBlocks,
        UtcInstant.utc(2026, 6, 1, 10, 0).millisecondsSinceEpoch,
      );
      expect(row.takeoffsDayFullStop, 1);
      expect(row.capacityCommandAuthority, isTrue);
      expect(row.capacityInstructorCapacity, isNull);
      expect(row.committedAt, isNull);
      expect(row.tombstonedAt, isNull);
    });

    test('carries committedAt/tombstonedAt through when supplied', () {
      final row = flightToRow(
        _sampleFlight(),
        id: 'f1',
        aircraftId: 'a1',
        committedAt: 1000,
        tombstonedAt: 2000,
      );

      expect(row.committedAt, 1000);
      expect(row.tombstonedAt, 2000);
    });
  });

  group('flightRouteLegRows', () {
    test('one row per route entry, in order', () {
      final rows = flightRouteLegRows('f1', _sampleFlight());

      expect(rows, hasLength(2));
      expect(rows[0].sequence, 0);
      expect(rows[0].identifier, 'EGKA');
      expect(rows[1].sequence, 1);
      expect(rows[1].identifier, 'EGKB');
      expect(rows.every((r) => r.flightId == 'f1'), isTrue);
    });
  });

  group('flightApproachRows', () {
    test('one row per approach', () {
      final rows = flightApproachRows('f1', _sampleFlight());

      expect(rows, hasLength(1));
      expect(rows.single.type, 'ils');
      expect(rows.single.count, 2);
    });
  });
}
