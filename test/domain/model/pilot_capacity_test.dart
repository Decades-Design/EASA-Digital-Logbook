// flutter_test re-exports test/group/expect from package:test_api, so plain
// Dart tests need no separate package:test dependency.
import 'package:easa_digital_log/domain/model/countersignature.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/instructor_presence.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/decoders/pilot_capacity_fixture.dart';

/// Every capacity scenario, by fixture name.
///
/// Issues #18 (EASA projection) and #19 (FAA projection) assert real PIC and
/// dual values against these. Until they exist, the expectations live as
/// comments in each YAML file. Add a fixture here when you add the file.
const List<String> capacityScenarios = <String>[
  'pic_sole_occupant',
  'pic_with_passengers',
  'sole_manipulator_receiving_instruction',
  'dual_received_not_manipulating',
  'spic',
  'picus_countersigned',
  'picus_pending',
  'picus_refused',
  'co_pilot_sic',
  'flight_instructor',
  'examiner',
  'skill_test_with_examiner',
  'safety_pilot',
  'second_pilot_single_pilot_aircraft',
  'mid_flight_takeover',
];

void main() {
  group('capacity fixtures', () {
    test('every scenario decodes', () {
      for (final name in capacityScenarios) {
        expect(
          pilotCapacityFromFixture(name),
          isA<PilotCapacity>(),
          reason: name,
        );
      }
    });

    test('no two scenarios are indistinguishable', () {
      // The load-bearing test. Drop any discriminator from PilotCapacity and
      // two scenarios collapse onto each other, turning this red. It proves
      // the model actually captures every case issue #13 requires it to tell
      // apart, without needing the projections that will interpret them.
      final decoded = <PilotCapacity, String>{};

      for (final name in capacityScenarios) {
        final capacity = pilotCapacityFromFixture(name);
        final clash = decoded[capacity];
        expect(
          clash,
          isNull,
          reason: '$name and $clash decode to the same PilotCapacity',
        );
        decoded[capacity] = name;
      }

      expect(decoded, hasLength(capacityScenarios.length));
    });

    test('every enum value is exercised by at least one scenario', () {
      // An enum value no fixture uses is model surface nothing tests. Both
      // projections branch on these, so an unexercised value is a branch that
      // has never been read from real data.
      final capacities = capacityScenarios.map(pilotCapacityFromFixture);

      final roles = capacities
          .map((c) => c.otherPilotRole)
          .whereType<OtherPilotRole>()
          .toSet();
      expect(roles, OtherPilotRole.values.toSet());

      final instructors = capacities
          .map((c) => c.instructor?.capacity)
          .whereType<InstructorCapacity>()
          .toSet();
      expect(instructors, InstructorCapacity.values.toSet());

      final statuses = capacities
          .map((c) => c.countersignature?.status)
          .whereType<CountersignatureStatus>()
          .toSet();
      expect(statuses, CountersignatureStatus.values.toSet());
    });
  });

  group('the EASA/FAA divergence', () {
    test('the canonical case separates command from manipulation', () {
      // Rated PPL flying, instructor aboard instructing and holding command.
      // FAA §61.51(e)(1)(i): PIC. EASA FCL.010: 0. The two facts that produce
      // opposite answers must both be present and must disagree.
      final capacity = pilotCapacityFromFixture(
        'sole_manipulator_receiving_instruction',
      );

      expect(capacity.commandAuthority, isFalse);
      expect(capacity.soleManipulator, isTrue);
      expect(capacity.instructor, isNotNull);
      expect(capacity.instructor!.influencedFlight, isTrue);
    });

    test('SPIC differs from dual on exactly one fact', () {
      // FCL.010: SPIC requires the instructor to only observe. If they
      // influenced the flight it is dual, and the two cannot be recorded
      // concurrently. That single boolean is the whole distinction.
      final spic = pilotCapacityFromFixture('spic');
      final dual = pilotCapacityFromFixture(
        'sole_manipulator_receiving_instruction',
      );

      expect(spic.instructor!.influencedFlight, isFalse);
      expect(dual.instructor!.influencedFlight, isTrue);

      // And SPIC holds command, which dual does not — the other half of why
      // EASA reaches opposite answers on two otherwise similar flights.
      expect(spic.commandAuthority, isTrue);
      expect(dual.commandAuthority, isFalse);
    });

    test('PICUS creditability turns only on the countersignature', () {
      // AMC1 FCL.050 requires the PIC's countersignature on a PICUS entry, and
      // at least one competent authority treats unsigned PICUS as unusable.
      // The two fixtures must therefore be identical in every capacity fact,
      // so #18 cannot accidentally attribute the difference to anything else.
      final signed = pilotCapacityFromFixture('picus_countersigned');
      final pending = pilotCapacityFromFixture('picus_pending');

      expect(signed.countersignature!.status, CountersignatureStatus.signed);
      expect(pending.countersignature!.status, CountersignatureStatus.pending);
      expect(signed.countersignature!.signedAt, isNotNull);
      expect(pending.countersignature!.signedAt, isNull);

      expect(
        signed.copyWith(countersignature: pending.countersignature),
        pending,
        reason: 'the two PICUS fixtures must differ only in the signature',
      );
    });

    test('a mid-flight takeover keeps the partial manipulation time', () {
      // §61.51(e)(1)(i) covers exactly the time manipulated. A bare boolean
      // would force overclaiming the whole flight or discarding 45 real
      // minutes, and neither is recoverable afterwards.
      final capacity = pilotCapacityFromFixture('mid_flight_takeover');

      expect(capacity.commandAuthority, isTrue);
      expect(capacity.soleManipulator, isFalse);
      expect(capacity.manipulationTime, const FlightDuration(45));
    });
  });

  group('the fixture decoder', () {
    test('names the fixture and key when a required field is missing', () {
      // A silently defaulted discriminator is indistinguishable from a
      // deliberate false, which is the failure rule 2 exists to prevent.
      expect(
        () => pilotCapacityFromFixture('malformed/missing_required_field'),
        throwsA(
          isA<FixtureFieldException>()
              .having((e) => e.key, 'key', 'sole_manipulator')
              .having(
                (e) => e.fixture,
                'fixture',
                'malformed/missing_required_field',
              ),
        ),
      );
    });

    test('rejects an unknown enum spelling rather than defaulting', () {
      expect(
        () => pilotCapacityFromFixture('malformed/bad_enum_value'),
        throwsA(
          isA<FixtureFieldException>().having(
            (e) => e.key,
            'key',
            'other_pilot_role',
          ),
        ),
      );
    });

    test('rejects an instant with no zone designator', () {
      // UtcInstant.parse resolves a naive string to LOCAL time silently if
      // asked, so the fixture path has to reject it too (rule 3, ADR-0002).
      expect(
        () => pilotCapacityFromFixture('malformed/naive_timestamp'),
        throwsA(
          isA<FixtureFieldException>().having((e) => e.key, 'key', 'signed_at'),
        ),
      );
    });
  });
}
