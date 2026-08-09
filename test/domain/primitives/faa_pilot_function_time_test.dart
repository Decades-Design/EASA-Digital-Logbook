// flutter_test re-exports test/group/expect from package:test_api, so plain
// Dart tests need no separate package:test dependency.
import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/instructor_presence.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:easa_digital_log/domain/primitives/faa_pilot_function_time.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/decoders/pilot_capacity_fixture.dart';

const _block = FlightDuration(90); // 1:30, matching the EASA test's fixture

Flight _flightWith(PilotCapacity capacity) => Flight(
  aircraftRegistration: 'N12345',
  route: const ['KJFK', 'KJFK'],
  prePlannedNavigation: false,
  offBlocks: UtcInstant.utc(2026, 1, 1, 9, 0),
  onBlocks: UtcInstant.utc(2026, 1, 1, 10, 30),
  capacity: capacity,
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

/// (minutes, creditable). Default when a name is absent from a fixture's
/// entry below is (0, true).
typedef _Expected = (int, bool);

const _full = (90, true);

/// Every one of the sixteen capacity scenarios, FAA outcome — transcribed
/// from the same "Expected projections" comments the EASA table reads,
/// so the two side by side are exactly what #19's acceptance criteria ask
/// for ("table-driven tests mirroring the EASA test matrix").
final Map<String, Map<String, _Expected>> _expected = {
  'pic_sole_occupant': {'loggedPic': _full, 'actingPic': _full, 'solo': _full},
  'pic_with_passengers': {'loggedPic': _full, 'actingPic': _full},
  'sole_manipulator_receiving_instruction': {
    'loggedPic': _full,
    'dualReceived': _full,
  },
  'dual_received_not_manipulating': {'dualReceived': _full},
  'spic': {'loggedPic': _full, 'actingPic': _full},
  'picus_countersigned': {'loggedPic': _full},
  'picus_pending': {'loggedPic': _full},
  'picus_refused': {'loggedPic': _full},
  'co_pilot_sic': {'sic': _full},
  'flight_instructor': {'loggedPic': _full, 'actingPic': _full},
  'examiner': {'actingPic': _full},
  'skill_test_with_examiner': {'loggedPic': _full},
  'mid_flight_takeover': {'loggedPic': (45, true), 'actingPic': _full},
  'second_pilot_single_pilot_aircraft': {},
  'student_solo': {'loggedPic': _full, 'actingPic': _full, 'solo': _full},
  'safety_pilot': {'loggedPic': _full, 'actingPic': _full},
};

const List<String> _allQuantityNames = [
  'loggedPic',
  'actingPic',
  'dualReceived',
  'sic',
  'solo',
];

void main() {
  group('faaPilotFunctionTime, table-driven over every capacity fixture', () {
    for (final entry in _expected.entries) {
      final fixture = entry.key;
      final overrides = entry.value;

      test(fixture, () {
        final capacity = pilotCapacityFromFixture(fixture);
        final result = faaPilotFunctionTime(_flightWith(capacity), _block);

        for (final name in _allQuantityNames) {
          final (expectedMinutes, expectedCreditable) =
              overrides[name] ?? (0, true);
          final quantity = result[name];
          expect(quantity, isNotNull, reason: '$fixture: missing "$name"');
          expect(
            quantity!.value,
            FlightDuration(expectedMinutes),
            reason: '$fixture: "$name" value',
          );
          expect(
            quantity.creditable,
            expectedCreditable,
            reason: '$fixture: "$name" creditability',
          );
        }
      });
    }

    test('every fixture is covered by this table', () {
      const knownFixtures = [
        'co_pilot_sic',
        'dual_received_not_manipulating',
        'examiner',
        'flight_instructor',
        'mid_flight_takeover',
        'pic_sole_occupant',
        'pic_with_passengers',
        'picus_countersigned',
        'picus_pending',
        'picus_refused',
        'safety_pilot',
        'second_pilot_single_pilot_aircraft',
        'skill_test_with_examiner',
        'sole_manipulator_receiving_instruction',
        'spic',
        'student_solo',
      ];
      expect(_expected.keys.toSet(), knownFixtures.toSet());
    });
  });

  group('logging PIC versus acting PIC', () {
    test('an examiner acts as PIC but does not log it', () {
      // §91.3 command authority is independent of §61.51(e)(1)(i) sole
      // manipulation. #19's own acceptance criteria call this distinction
      // out explicitly.
      final result = faaPilotFunctionTime(
        _flightWith(pilotCapacityFromFixture('examiner')),
        _block,
      );

      expect(result['actingPic']!.value, _block);
      expect(result['loggedPic']!.value, FlightDuration.zero);
    });

    test('the candidate on a checkride logs PIC but does not act as it', () {
      final result = faaPilotFunctionTime(
        _flightWith(pilotCapacityFromFixture('skill_test_with_examiner')),
        _block,
      );

      expect(result['loggedPic']!.value, _block);
      expect(result['actingPic']!.value, FlightDuration.zero);
    });
  });

  group('the safety pilot case, both seats', () {
    test('the flying pilot logs PIC, acts as PIC, and is not solo', () {
      final result = faaPilotFunctionTime(
        _flightWith(pilotCapacityFromFixture('safety_pilot')),
        _block,
      );

      expect(result['loggedPic']!.value, _block);
      expect(result['actingPic']!.value, _block);
      expect(result['solo']!.value, FlightDuration.zero);
    });
  });

  group('mid-flight takeover', () {
    test(
      'logged PIC is exactly the manipulated portion, acting PIC is the whole flight',
      () {
        final result = faaPilotFunctionTime(
          _flightWith(pilotCapacityFromFixture('mid_flight_takeover')),
          _block,
        );

        expect(result['loggedPic']!.value, const FlightDuration(45));
        expect(result['actingPic']!.value, _block);
      },
    );
  });

  group('dual received excludes an examiner', () {
    test('an examiner who actively flew is not "training received" — no '
        'fixture covers this, so it is asserted directly', () {
      // skill_test_with_examiner.yaml has influencedFlight: false, so it
      // cannot distinguish "examiner, not gated" from "gated on
      // InstructorCapacity.flightInstructor" — both give dualReceived: 0
      // there either way. This fixture is the one that can tell them
      // apart: an examiner who *did* influence the flight.
      const capacity = PilotCapacity(
        commandAuthority: false,
        soleManipulator: true,
        soleOccupant: false,
        multiPilotOperation: false,
        additionalCrewRequiredByRule: false,
        actingAsInstructor: false,
        actingAsExaminer: false,
        picusClaimed: false,
        picInterventionNotRequired: false,
        instructor: InstructorPresence(
          capacity: InstructorCapacity.flightExaminer,
          influencedFlight: true,
        ),
      );

      final result = faaPilotFunctionTime(_flightWith(capacity), _block);

      expect(
        result['dualReceived']!.value,
        FlightDuration.zero,
        reason:
            '§61.51(h) is training received, not an examiner flying '
            'part of a checkride',
      );
    });
  });
}
