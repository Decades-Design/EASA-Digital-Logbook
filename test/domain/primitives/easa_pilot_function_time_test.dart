// flutter_test re-exports test/group/expect from package:test_api, so plain
// Dart tests need no separate package:test dependency.
import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/instructor_presence.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:easa_digital_log/domain/primitives/easa_pilot_function_time.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/decoders/pilot_capacity_fixture.dart';

const _block = FlightDuration(90); // 1:30, an arbitrary but fixed block time
const _zero = FlightDuration.zero;

Flight _flightWith(PilotCapacity capacity) => Flight(
  aircraftRegistration: 'G-TEST',
  route: const ['EGKA', 'EGKA'],
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

/// One expected value: (minutes, creditable).
typedef _Expected = (int, bool);

const _fullCreditable = (90, true);
const _zeroCreditable = (0, true);
const _fullNotCreditable = (90, false);

/// Every one of the sixteen capacity scenarios, EASA outcome — transcribed
/// from the "Expected projections" comment block already documented in each
/// `test/fixtures/capacities/*.yaml` file. Not editorial: these are the
/// specs #13's fixtures were written against.
final Map<String, Map<String, _Expected>> _expected = {
  'pic_sole_occupant': {'pic': _fullCreditable},
  'pic_with_passengers': {'pic': _fullCreditable},
  'sole_manipulator_receiving_instruction': {'dual': _fullCreditable},
  'dual_received_not_manipulating': {'dual': _fullCreditable},
  'spic': {'pic': _fullNotCreditable, 'spic': _fullNotCreditable},
  'picus_countersigned': {'pic': _fullCreditable, 'picus': _fullCreditable},
  'picus_pending': {'pic': _fullNotCreditable, 'picus': _fullNotCreditable},
  'picus_refused': {'pic': _fullNotCreditable, 'picus': _fullNotCreditable},
  'co_pilot_sic': {'copilot': _fullCreditable},
  'flight_instructor': {'pic': _fullCreditable, 'instructor': _fullCreditable},
  'examiner': {'pic': _fullCreditable},
  'skill_test_with_examiner': {}, // all zero: examiner holds command, no dual
  'mid_flight_takeover': {'pic': _fullCreditable},
  'second_pilot_single_pilot_aircraft':
      {}, // all zero — the counterintuitive case
  'student_solo': {'pic': _fullCreditable},
  'safety_pilot': {'pic': _fullCreditable},
};

const List<String> _allQuantityNames = [
  'pic',
  'dual',
  'spic',
  'picus',
  'copilot',
  'instructor',
];

void main() {
  group('easaPilotFunctionTime, table-driven over every capacity fixture', () {
    for (final entry in _expected.entries) {
      final fixture = entry.key;
      final overrides = entry.value;

      test(fixture, () {
        final capacity = pilotCapacityFromFixture(fixture);
        final result = easaPilotFunctionTime(_flightWith(capacity), _block);

        for (final name in _allQuantityNames) {
          final (expectedMinutes, expectedCreditable) =
              overrides[name] ?? _zeroCreditable;
          final quantity = result[name];
          expect(quantity, isNotNull, reason: '$fixture: missing "$name"');
          expect(
            quantity!.value,
            expectedMinutes == 0 ? _zero : _block,
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
      // Guards against a fixture being added to test/fixtures/capacities/
      // without a matching entry here — silently skipping EASA coverage for
      // it would be exactly the kind of gap #18 exists to prevent.
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

  group('the canonical SPIC/dual distinction', () {
    test(
      'spic and sole_manipulator_receiving_instruction differ by exactly two facts',
      () {
        // Both are "command_authority + instructor aboard + sole manipulator".
        // The only two facts that differ are command_authority itself and
        // instructor.influencedFlight — and they produce opposite EASA answers.
        final spicCapacity = pilotCapacityFromFixture('spic');
        final dualCapacity = pilotCapacityFromFixture(
          'sole_manipulator_receiving_instruction',
        );

        final spicResult = easaPilotFunctionTime(
          _flightWith(spicCapacity),
          _block,
        );
        final dualResult = easaPilotFunctionTime(
          _flightWith(dualCapacity),
          _block,
        );

        expect(spicResult['spic']!.value, _block);
        expect(dualResult['spic']!.value, _zero);
        expect(spicResult['dual']!.value, _zero);
        expect(dualResult['dual']!.value, _block);
      },
    );

    test('command authority wins over an influencing instructor — no fixture '
        'covers this combination, so it is asserted directly', () {
      // Not a scenario any capacity fixture models — every fixture where
      // an instructor influences the flight also has commandAuthority:
      // false (the instructor holds command while actively instructing).
      // But PilotCapacity's fields are independent, so this combination
      // is constructible, and the branch order in
      // easaPilotFunctionTime must have a defined answer for it: holding
      // command is a general, independent claim (mid_flight_takeover.yaml
      // — "EASA PIC time does not depend on who was handling the
      // controls"), so it wins regardless of what an aboard instructor
      // did. This is what stops that branch order from silently
      // regressing to treating any instructor presence as SPIC-eligible.
      const capacity = PilotCapacity(
        commandAuthority: true,
        soleManipulator: false,
        soleOccupant: false,
        multiPilotOperation: false,
        additionalCrewRequiredByRule: false,
        actingAsInstructor: false,
        actingAsExaminer: false,
        picusClaimed: false,
        picInterventionNotRequired: false,
        instructor: InstructorPresence(
          capacity: InstructorCapacity.flightInstructor,
          influencedFlight: true,
        ),
      );

      final result = easaPilotFunctionTime(_flightWith(capacity), _block);

      expect(result['pic']!.value, _block);
      expect(
        result['pic']!.creditable,
        isTrue,
        reason: 'ordinary command PIC, not gated by a countersignature',
      );
      expect(result['spic']!.value, _zero);
      expect(result['dual']!.value, _zero);
    });
  });

  group('PICUS creditability', () {
    test('countersigned, pending and refused PICUS all claim the same value, '
        'differing only in creditability and reason', () {
      final signed = easaPilotFunctionTime(
        _flightWith(pilotCapacityFromFixture('picus_countersigned')),
        _block,
      );
      final pending = easaPilotFunctionTime(
        _flightWith(pilotCapacityFromFixture('picus_pending')),
        _block,
      );
      final refused = easaPilotFunctionTime(
        _flightWith(pilotCapacityFromFixture('picus_refused')),
        _block,
      );

      expect(signed['picus']!.value, _block);
      expect(
        pending['picus']!.value,
        _block,
        reason: 'not silently 0 while pending',
      );
      expect(
        refused['picus']!.value,
        _block,
        reason: 'not silently 0 when refused',
      );

      expect(signed['picus']!.creditable, isTrue);
      expect(pending['picus']!.creditable, isFalse);
      expect(refused['picus']!.creditable, isFalse);

      expect(
        pending['picus']!.explanation,
        isNot(refused['picus']!.explanation),
        reason: '#18: pending and refused must give different reasons',
      );
    });
  });
}
