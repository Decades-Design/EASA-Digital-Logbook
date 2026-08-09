// flutter_test re-exports test/group/expect from package:test_api, so plain
// Dart tests need no separate package:test dependency.
import 'package:easa_digital_log/domain/model/calendar_date.dart';
import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/flight_logbook_date.dart';
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

Flight _flight({required UtcInstant offBlocks, required UtcInstant onBlocks}) =>
    Flight(
      aircraftRegistration: 'G-ABCD',
      route: const ['EGKA', 'EGLL'],
      prePlannedNavigation: false,
      offBlocks: offBlocks,
      onBlocks: onBlocks,
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
  group('Flight.logbookDate', () {
    test('a flight crossing the UTC midnight boundary files under the date '
        'of departure, not arrival', () {
      // docs/adr/0009-date-boundary-policy.md's own example: departs
      // 23:40Z, arrives 01:10Z the next UTC day.
      final flight = _flight(
        offBlocks: UtcInstant.utc(2026, 6, 15, 23, 40),
        onBlocks: UtcInstant.utc(2026, 6, 16, 1, 10),
      );

      expect(flight.logbookDate, const CalendarDate(2026, 6, 15));
    });

    test('a flight wholly within one UTC date files under that date, the '
        'ordinary case', () {
      final flight = _flight(
        offBlocks: UtcInstant.utc(2026, 6, 15, 9, 0),
        onBlocks: UtcInstant.utc(2026, 6, 15, 10, 30),
      );

      expect(flight.logbookDate, const CalendarDate(2026, 6, 15));
    });

    test('uses the UTC date even where a local wall clock at departure would '
        'read a different date entirely', () {
      // A departure at 2026-06-15T23:40 local time five hours behind UTC
      // (e.g. US Eastern, UTC-5) is stored — per rule 3 — as the UTC
      // instant 2026-06-16T04:40Z. The policy reads that stored UTC
      // instant only: it never attempts to reconstruct "what the pilot's
      // wall clock said," which nothing in this codebase records.
      final flight = _flight(
        offBlocks: UtcInstant.utc(2026, 6, 16, 4, 40),
        onBlocks: UtcInstant.utc(2026, 6, 16, 6, 10),
      );

      expect(
        flight.logbookDate,
        const CalendarDate(2026, 6, 16),
        reason:
            'the UTC date of off-blocks, not the 2026-06-15 a local '
            'wall clock at the departure point would have shown',
      );
    });
  });
}
