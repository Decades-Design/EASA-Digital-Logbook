import 'dart:io';

import 'package:easa_digital_log/domain/currency/currency_rule.dart';
import 'package:easa_digital_log/domain/currency/currency_rule_evaluator.dart';
import 'package:easa_digital_log/domain/currency/currency_rule_yaml.dart';
import 'package:easa_digital_log/domain/currency/evaluation_subject.dart';
import 'package:easa_digital_log/domain/currency/held_record.dart';
import 'package:easa_digital_log/domain/model/calendar_date.dart';
import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/instructor_presence.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:flutter_test/flutter_test.dart';

import '../currency/currency_test_helpers.dart';

CurrencyRule _loadRule(String path) =>
    parseCurrencyRuleYaml(File(path).readAsStringSync());

const _picCapacity = PilotCapacity(
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

const _dualWithInstructorCapacity = PilotCapacity(
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
    capacity: InstructorCapacity.flightInstructor,
    influencedFlight: false,
    name: 'A. Instructor',
  ),
);

void main() {
  const evaluator = CurrencyRuleEvaluator();

  group('eu.easa.fcl740a.sep_land_revalidation (#47)', () {
    final rule = _loadRule(
      'assets/rules/easa/fcl740a_sep_land_revalidation.yaml',
    );
    final sepRating = HeldRecord(
      kind: 'rating.eu.easa.part-fcl.classRating.SEP(land)',
      validFrom: CalendarDate(2023, 1, 1),
      validUntil: CalendarDate(2025, 1, 1),
    );

    test('metadata matches the regulation', () {
      expect(rule.citation, 'FCL.740.A(b)(1)');
    });

    test(
      '12 hours (6 as PIC), 12 takeoffs and landings, and a training flight: satisfied',
      () {
        final flights = [
          for (var i = 0; i < 6; i++)
            currencyTestRecord(
              'pic-$i',
              currencyTestFlight(
                date: CalendarDate(2024, 2, i + 1),
                landings: const CircuitCounts(dayFullStop: 1),
                takeoffs: const CircuitCounts(dayFullStop: 1),
                capacity: _picCapacity,
              ),
            ),
          for (var i = 0; i < 6; i++)
            currencyTestRecord(
              'dual-$i',
              currencyTestFlight(
                date: CalendarDate(2024, 3, i + 1),
                landings: const CircuitCounts(dayFullStop: 1),
                takeoffs: const CircuitCounts(dayFullStop: 1),
                capacity: _dualWithInstructorCapacity,
              ),
            ),
        ];
        final subject = EvaluationSubject(
          referenceAircraft: testAircraft,
          flights: flights,
          heldRecords: [sepRating],
        );

        final result = evaluator.evaluateRequirement(
          rule.requirement,
          subject,
          CalendarDate(2024, 8, 1),
        );

        expect(result.satisfied, isTrue);
      },
    );

    test('12 hours and 12 landings but only 3 as PIC: unsatisfied', () {
      final flights = [
        for (var i = 0; i < 3; i++)
          currencyTestRecord(
            'pic-$i',
            currencyTestFlight(
              date: CalendarDate(2024, 2, i + 1),
              landings: const CircuitCounts(dayFullStop: 1),
              takeoffs: const CircuitCounts(dayFullStop: 1),
              capacity: _picCapacity,
            ),
          ),
        for (var i = 0; i < 9; i++)
          currencyTestRecord(
            'dual-$i',
            currencyTestFlight(
              date: CalendarDate(2024, 3, i + 1),
              landings: const CircuitCounts(dayFullStop: 1),
              takeoffs: const CircuitCounts(dayFullStop: 1),
              capacity: _dualWithInstructorCapacity,
            ),
          ),
      ];
      final subject = EvaluationSubject(
        referenceAircraft: testAircraft,
        flights: flights,
        heldRecords: [sepRating],
      );

      final result = evaluator.evaluateRequirement(
        rule.requirement,
        subject,
        CalendarDate(2024, 8, 1),
      );

      expect(result.satisfied, isFalse);
    });

    test('a class-rating proficiency check alone satisfies it', () {
      final subject = EvaluationSubject(
        referenceAircraft: testAircraft,
        flights: [
          currencyTestRecord(
            '1',
            currencyTestFlight(
              date: CalendarDate(2024, 6, 1),
              alternativeComplianceEvents: const {
                AlternativeComplianceEvent.easaClassRatingProficiencyCheck,
              },
            ),
          ),
        ],
        heldRecords: [sepRating],
      );

      final result = evaluator.evaluateRequirement(
        rule.requirement,
        subject,
        CalendarDate(2024, 8, 1),
      );

      expect(result.satisfied, isTrue);
    });

    test(
      'the requirement is met, but entirely outside the 12-month pre-expiry window: unsatisfied',
      () {
        // Same activity as the fully-satisfied case above, but flown in 2022 --
        // right after a previous revalidation, well before the window
        // [2024-01-01, 2025-01-01] this rating's 2025-01-01 expiry implies.
        final flights = [
          for (var i = 0; i < 6; i++)
            currencyTestRecord(
              'pic-$i',
              currencyTestFlight(
                date: CalendarDate(2022, 2, i + 1),
                landings: const CircuitCounts(dayFullStop: 1),
                takeoffs: const CircuitCounts(dayFullStop: 1),
                capacity: _picCapacity,
              ),
            ),
          for (var i = 0; i < 6; i++)
            currencyTestRecord(
              'dual-$i',
              currencyTestFlight(
                date: CalendarDate(2022, 3, i + 1),
                landings: const CircuitCounts(dayFullStop: 1),
                takeoffs: const CircuitCounts(dayFullStop: 1),
                capacity: _dualWithInstructorCapacity,
              ),
            ),
        ];
        final subject = EvaluationSubject(
          referenceAircraft: testAircraft,
          flights: flights,
          heldRecords: [sepRating],
        );

        final result = evaluator.evaluateRequirement(
          rule.requirement,
          subject,
          CalendarDate(2024, 8, 1),
        );

        expect(result.satisfied, isFalse);
      },
    );

    test('no activity and no proficiency check: unsatisfied', () {
      final subject = EvaluationSubject(
        referenceAircraft: testAircraft,
        flights: const [],
        heldRecords: [sepRating],
      );

      final result = evaluator.evaluateRequirement(
        rule.requirement,
        subject,
        CalendarDate(2024, 8, 1),
      );

      expect(result.satisfied, isFalse);
    });
  });
}
