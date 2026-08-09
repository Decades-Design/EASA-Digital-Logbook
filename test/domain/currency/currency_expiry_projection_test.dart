import 'package:easa_digital_log/domain/currency/currency_expiry_projection.dart';
import 'package:easa_digital_log/domain/currency/currency_rule.dart';
import 'package:easa_digital_log/domain/currency/currency_rule_evaluator.dart';
import 'package:easa_digital_log/domain/currency/evaluation_subject.dart';
import 'package:easa_digital_log/domain/currency/rule_result.dart';
import 'package:easa_digital_log/domain/currency/rule_window.dart';
import 'package:easa_digital_log/domain/model/calendar_date.dart';
import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:flutter_test/flutter_test.dart';

import 'currency_test_helpers.dart';

CurrencyRuleEvaluation _evaluation({
  required String ruleId,
  required bool satisfied,
  CalendarDate? expiresOn,
}) => CurrencyRuleEvaluation(
  ruleId: ruleId,
  citation: 'citation for $ruleId',
  result: RuleResult(
    satisfied: satisfied,
    explanation: 'irrelevant to this test',
    expiresOn: expiresOn,
  ),
);

void main() {
  group('nextToExpire', () {
    test('picks the earliest expiry among several satisfied rules', () {
      final evaluations = [
        _evaluation(
          ruleId: 'a',
          satisfied: true,
          expiresOn: CalendarDate(2024, 9, 1),
        ),
        _evaluation(
          ruleId: 'b',
          satisfied: true,
          expiresOn: CalendarDate(2024, 7, 1),
        ),
        _evaluation(
          ruleId: 'c',
          satisfied: true,
          expiresOn: CalendarDate(2024, 12, 1),
        ),
      ];

      final next = nextToExpire(evaluations);

      expect(next?.ruleId, 'b');
      expect(next?.expiresOn, CalendarDate(2024, 7, 1));
    });

    test('a satisfied rule that never lapses is not "next to expire"', () {
      final evaluations = [
        _evaluation(ruleId: 'never-lapses', satisfied: true, expiresOn: null),
        _evaluation(
          ruleId: 'does-lapse',
          satisfied: true,
          expiresOn: CalendarDate(2024, 7, 1),
        ),
      ];

      final next = nextToExpire(evaluations);

      expect(next?.ruleId, 'does-lapse');
    });

    test('an unsatisfied rule is excluded, not treated as already expired', () {
      final evaluations = [
        _evaluation(ruleId: 'not-current', satisfied: false, expiresOn: null),
      ];

      expect(nextToExpire(evaluations), isNull);
    });

    test('null when nothing is both satisfied and lapsing', () {
      expect(nextToExpire(const []), isNull);
      expect(
        nextToExpire([
          _evaluation(ruleId: 'a', satisfied: true, expiresOn: null),
        ]),
        isNull,
      );
    });
  });

  group('isNearingExpiry', () {
    test('true once within the lead time', () {
      expect(
        isNearingExpiry(
          CalendarDate(2024, 9, 10),
          CalendarDate(2024, 9, 1),
          leadDays: 30,
        ),
        isTrue,
      );
    });

    test('false while still outside the lead time', () {
      expect(
        isNearingExpiry(
          CalendarDate(2024, 12, 1),
          CalendarDate(2024, 9, 1),
          leadDays: 30,
        ),
        isFalse,
      );
    });

    test('true exactly at the lead-time boundary', () {
      expect(
        isNearingExpiry(
          CalendarDate(2024, 10, 1), // exactly 30 days after asOf
          CalendarDate(2024, 9, 1),
          leadDays: 30,
        ),
        isTrue,
      );
    });

    test(
      'false once already lapsed -- that is "not current", not "nearing"',
      () {
        expect(
          isNearingExpiry(
            CalendarDate(2024, 8, 1),
            CalendarDate(2024, 9, 1),
            leadDays: 30,
          ),
          isFalse,
        );
      },
    );

    test(
      'the lead time is a caller-supplied parameter, not a fixed default',
      () {
        final expiresOn = CalendarDate(2024, 9, 15);
        final asOf = CalendarDate(2024, 9, 1);

        expect(isNearingExpiry(expiresOn, asOf, leadDays: 7), isFalse);
        expect(isNearingExpiry(expiresOn, asOf, leadDays: 14), isTrue);
      },
    );
  });

  group('nextToExpire against the real evaluator', () {
    const evaluator = CurrencyRuleEvaluator();
    final rule = CurrencyRule(
      id: 'test.recency',
      jurisdictionId: 'eu.easa.part-fcl',
      citation: 'test citation',
      effectiveFrom: CalendarDate(2020, 1, 1),
      requirement: Requirement.flightEventCount(
        event: CountableFlightEvent.landings,
        count: 3,
        window: RuleWindow.rollingDays(90),
      ),
    );

    test('flying one more qualifying flight extends currency', () {
      final asOf = CalendarDate(2024, 6, 1);
      final threeLandings = EvaluationSubject(
        flights: [
          for (var i = 0; i < 3; i++)
            currencyTestRecord(
              '$i',
              currencyTestFlight(
                date: CalendarDate(2024, 3, 3 + i), // oldest is the anchor
                landings: const CircuitCounts(dayFullStop: 1),
              ),
            ),
        ],
      );
      final before = evaluator.evaluateRule(rule, threeLandings, asOf);

      final withOneMoreRecentLanding = EvaluationSubject(
        flights: [
          ...threeLandings.flights,
          currencyTestRecord(
            'newest',
            currencyTestFlight(
              date: CalendarDate(2024, 5, 30),
              landings: const CircuitCounts(dayFullStop: 1),
            ),
          ),
        ],
      );
      final after = evaluator.evaluateRule(
        rule,
        withOneMoreRecentLanding,
        asOf,
      );

      final beforeNext = nextToExpire([before]);
      final afterNext = nextToExpire([after]);

      expect(beforeNext, isNotNull);
      expect(afterNext, isNotNull);
      expect(afterNext!.expiresOn > beforeNext!.expiresOn, isTrue);
    });

    test(
      'flying one more flight that does not qualify does not change the expiry',
      () {
        final asOf = CalendarDate(2024, 6, 1);
        final threeLandings = EvaluationSubject(
          flights: [
            for (var i = 0; i < 3; i++)
              currencyTestRecord(
                '$i',
                currencyTestFlight(
                  date: CalendarDate(2024, 3, 3 + i),
                  landings: const CircuitCounts(dayFullStop: 1),
                ),
              ),
          ],
        );
        final before = evaluator.evaluateRule(rule, threeLandings, asOf);

        // Adds a flight with zero landings -- a flight happened, but it
        // contributes nothing to this requirement.
        final withAnIrrelevantFlight = EvaluationSubject(
          flights: [
            ...threeLandings.flights,
            currencyTestRecord(
              'irrelevant',
              currencyTestFlight(date: CalendarDate(2024, 5, 30)),
            ),
          ],
        );
        final after = evaluator.evaluateRule(
          rule,
          withAnIrrelevantFlight,
          asOf,
        );

        expect(
          nextToExpire([after])?.expiresOn,
          nextToExpire([before])?.expiresOn,
        );
      },
    );
  });
}
