import 'dart:io';

import 'package:easa_digital_log/domain/currency/currency_rule.dart';
import 'package:easa_digital_log/domain/currency/currency_rule_evaluator.dart';
import 'package:easa_digital_log/domain/currency/currency_rule_yaml.dart';
import 'package:easa_digital_log/domain/currency/evaluation_subject.dart';
import 'package:easa_digital_log/domain/currency/held_record.dart';
import 'package:easa_digital_log/domain/model/calendar_date.dart';
import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:flutter_test/flutter_test.dart';

import '../currency/currency_test_helpers.dart';

CurrencyRule _loadRule(String path) =>
    parseCurrencyRuleYaml(File(path).readAsStringSync());

void main() {
  const evaluator = CurrencyRuleEvaluator();

  group('eu.easa.fcl060.b3_night_passenger_recency (#46)', () {
    final rule = _loadRule(
      'assets/rules/easa/fcl060_b3_night_passenger_recency.yaml',
    );

    test('metadata matches the regulation', () {
      expect(rule.citation, 'FCL.060(b)(3)');
    });

    test('3 landings with 1 at night, no IR held: satisfied', () {
      final asOf = CalendarDate(2024, 6, 1);
      final subject = EvaluationSubject(
        referenceAircraft: testAircraft,
        flights: [
          currencyTestRecord(
            '1',
            currencyTestFlight(
              date: CalendarDate(2024, 5, 1),
              landings: const CircuitCounts(nightFullStop: 1),
            ),
          ),
          currencyTestRecord(
            '2',
            currencyTestFlight(
              date: CalendarDate(2024, 5, 2),
              landings: const CircuitCounts(dayFullStop: 1),
            ),
          ),
          currencyTestRecord(
            '3',
            currencyTestFlight(
              date: CalendarDate(2024, 5, 3),
              landings: const CircuitCounts(dayFullStop: 1),
            ),
          ),
        ],
      );

      final result = evaluator.evaluateRequirement(
        rule.requirement,
        subject,
        asOf,
      );

      expect(result.satisfied, isTrue);
    });

    test('3 landings, none at night, but a valid IR is held: satisfied', () {
      final asOf = CalendarDate(2024, 6, 1);
      final subject = EvaluationSubject(
        referenceAircraft: testAircraft,
        flights: [
          for (var i = 0; i < 3; i++)
            currencyTestRecord(
              '$i',
              currencyTestFlight(
                date: CalendarDate(2024, 5, i + 1),
                landings: const CircuitCounts(dayFullStop: 1),
              ),
            ),
        ],
        heldRecords: [
          HeldRecord(
            kind: 'rating.eu.easa.part-fcl.instrumentRating.IR',
            validFrom: CalendarDate(2023, 1, 1),
            validUntil: CalendarDate(2025, 1, 1),
          ),
        ],
      );

      final result = evaluator.evaluateRequirement(
        rule.requirement,
        subject,
        asOf,
      );

      expect(result.satisfied, isTrue);
    });

    test('3 landings, none at night, no IR held: unsatisfied', () {
      final asOf = CalendarDate(2024, 6, 1);
      final subject = EvaluationSubject(
        referenceAircraft: testAircraft,
        flights: [
          for (var i = 0; i < 3; i++)
            currencyTestRecord(
              '$i',
              currencyTestFlight(
                date: CalendarDate(2024, 5, i + 1),
                landings: const CircuitCounts(dayFullStop: 1),
              ),
            ),
        ],
      );

      final result = evaluator.evaluateRequirement(
        rule.requirement,
        subject,
        asOf,
      );

      expect(result.satisfied, isFalse);
    });

    test(
      'only 2 landings total, one at night, no IR: unsatisfied -- the b1 base is not met',
      () {
        final asOf = CalendarDate(2024, 6, 1);
        final subject = EvaluationSubject(
          referenceAircraft: testAircraft,
          flights: [
            currencyTestRecord(
              '1',
              currencyTestFlight(
                date: CalendarDate(2024, 5, 1),
                landings: const CircuitCounts(nightFullStop: 1),
              ),
            ),
            currencyTestRecord(
              '2',
              currencyTestFlight(
                date: CalendarDate(2024, 5, 2),
                landings: const CircuitCounts(dayFullStop: 1),
              ),
            ),
          ],
        );

        final result = evaluator.evaluateRequirement(
          rule.requirement,
          subject,
          asOf,
        );

        expect(result.satisfied, isFalse);
      },
    );

    test('an expired IR does not substitute for the night landing', () {
      final asOf = CalendarDate(2024, 6, 1);
      final subject = EvaluationSubject(
        referenceAircraft: testAircraft,
        flights: [
          for (var i = 0; i < 3; i++)
            currencyTestRecord(
              '$i',
              currencyTestFlight(
                date: CalendarDate(2024, 5, i + 1),
                landings: const CircuitCounts(dayFullStop: 1),
              ),
            ),
        ],
        heldRecords: [
          HeldRecord(
            kind: 'rating.eu.easa.part-fcl.instrumentRating.IR',
            validFrom: CalendarDate(2018, 1, 1),
            validUntil: CalendarDate(2019, 1, 1), // lapsed
          ),
        ],
      );

      final result = evaluator.evaluateRequirement(
        rule.requirement,
        subject,
        asOf,
      );

      expect(result.satisfied, isFalse);
    });
  });

  group('us.faa.61_56.flight_review (#49)', () {
    final rule = _loadRule('assets/rules/faa/61_56_flight_review.yaml');

    test('metadata matches the regulation', () {
      expect(rule.citation, '§61.56');
    });

    test('valid through the end of the 24th calendar month, not 730 days', () {
      final subject = EvaluationSubject(
        flights: [
          currencyTestRecord(
            '1',
            currencyTestFlight(
              date: CalendarDate(2022, 1, 31),
              alternativeComplianceEvents: const {
                AlternativeComplianceEvent.faaFlightReview,
              },
            ),
          ),
        ],
      );

      final lastValidDay = evaluator.evaluateRequirement(
        rule.requirement,
        subject,
        CalendarDate(2024, 1, 31),
      );
      final firstLapsedDay = evaluator.evaluateRequirement(
        rule.requirement,
        subject,
        CalendarDate(2024, 2, 1),
      );

      expect(lastValidDay.satisfied, isTrue);
      expect(firstLapsedDay.satisfied, isFalse);
    });

    test(
      'an instrument proficiency check satisfies it in place of a flight review',
      () {
        final subject = EvaluationSubject(
          flights: [
            currencyTestRecord(
              '1',
              currencyTestFlight(
                date: CalendarDate(2023, 6, 1),
                alternativeComplianceEvents: const {
                  AlternativeComplianceEvent.faaInstrumentProficiencyCheck,
                },
              ),
            ),
          ],
        );

        final result = evaluator.evaluateRequirement(
          rule.requirement,
          subject,
          CalendarDate(2024, 1, 1),
        );

        expect(result.satisfied, isTrue);
      },
    );

    test('no flight review and no IPC: unsatisfied', () {
      final result = evaluator.evaluateRequirement(
        rule.requirement,
        const EvaluationSubject(flights: []),
        CalendarDate(2024, 1, 1),
      );

      expect(result.satisfied, isFalse);
    });
  });

  group('us.faa.61_57_c instrument currency + grace period (#50)', () {
    final currentRule = _loadRule(
      'assets/rules/faa/61_57_c_instrument_currency.yaml',
    );
    final graceRule = _loadRule(
      'assets/rules/faa/61_57_c_instrument_currency_grace_period.yaml',
    );

    Flight instrumentFlight(CalendarDate date) => currencyTestFlight(
      date: date,
      approaches: const [
        Approach(
          type: ApproachType.ils,
          aerodromeIcao: 'EGXX',
          runway: '27',
          count: 6,
        ),
      ],
      holdingProceduresCount: 1,
      trackingPerformed: true,
    );

    test(
      'six approaches, holding and tracking within 6 months: fully current',
      () {
        final subject = EvaluationSubject(
          flights: [
            currencyTestRecord('1', instrumentFlight(CalendarDate(2024, 1, 1))),
          ],
        );
        final asOf = CalendarDate(2024, 6, 1);

        expect(
          evaluator
              .evaluateRequirement(currentRule.requirement, subject, asOf)
              .satisfied,
          isTrue,
        );
      },
    );

    test(
      'lapsed but in grace: fails the 6-month rule, passes the 12-month one',
      () {
        // 8 months old: outside the 6-month window, inside the 12-month one.
        final subject = EvaluationSubject(
          flights: [
            currencyTestRecord('1', instrumentFlight(CalendarDate(2024, 1, 1))),
          ],
        );
        final asOf = CalendarDate(2024, 9, 1);

        final current = evaluator.evaluateRequirement(
          currentRule.requirement,
          subject,
          asOf,
        );
        final inGrace = evaluator.evaluateRequirement(
          graceRule.requirement,
          subject,
          asOf,
        );

        expect(current.satisfied, isFalse);
        expect(inGrace.satisfied, isTrue);
      },
    );

    test('lapsed past grace: fails both, an IPC is required', () {
      // 13 months old: outside even the 12-month grace window.
      final subject = EvaluationSubject(
        flights: [
          currencyTestRecord('1', instrumentFlight(CalendarDate(2023, 1, 1))),
        ],
      );
      final asOf = CalendarDate(2024, 2, 1);

      final current = evaluator.evaluateRequirement(
        currentRule.requirement,
        subject,
        asOf,
      );
      final inGrace = evaluator.evaluateRequirement(
        graceRule.requirement,
        subject,
        asOf,
      );

      expect(current.satisfied, isFalse);
      expect(inGrace.satisfied, isFalse);
    });

    test('an IPC alone satisfies currency without any approaches at all', () {
      final subject = EvaluationSubject(
        flights: [
          currencyTestRecord(
            '1',
            currencyTestFlight(
              date: CalendarDate(2024, 3, 1),
              alternativeComplianceEvents: const {
                AlternativeComplianceEvent.faaInstrumentProficiencyCheck,
              },
            ),
          ),
        ],
      );

      final result = evaluator.evaluateRequirement(
        currentRule.requirement,
        subject,
        CalendarDate(2024, 6, 1),
      );

      expect(result.satisfied, isTrue);
    });

    test(
      'five approaches is not enough -- the count is exactly six, not "several"',
      () {
        final subject = EvaluationSubject(
          flights: [
            currencyTestRecord(
              '1',
              currencyTestFlight(
                date: CalendarDate(2024, 1, 1),
                approaches: const [
                  Approach(
                    type: ApproachType.ils,
                    aerodromeIcao: 'EGXX',
                    runway: '27',
                    count: 5,
                  ),
                ],
                holdingProceduresCount: 1,
                trackingPerformed: true,
              ),
            ),
          ],
        );

        final result = evaluator.evaluateRequirement(
          currentRule.requirement,
          subject,
          CalendarDate(2024, 6, 1),
        );

        expect(result.satisfied, isFalse);
      },
    );
  });
}
