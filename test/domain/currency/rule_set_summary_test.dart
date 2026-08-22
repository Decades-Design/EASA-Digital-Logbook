import 'package:easa_digital_log/domain/currency/currency_rule.dart';
import 'package:easa_digital_log/domain/currency/rule_set_summary.dart';
import 'package:easa_digital_log/domain/currency/rule_window.dart';
import 'package:easa_digital_log/domain/model/calendar_date.dart';
import 'package:flutter_test/flutter_test.dart';

CurrencyRule _rule({
  required String id,
  required String jurisdictionId,
  required Requirement requirement,
}) => CurrencyRule(
  id: id,
  jurisdictionId: jurisdictionId,
  citation: 'test citation',
  title: 'Test rule',
  effectiveFrom: const CalendarDate(2020, 1, 1),
  requirement: requirement,
);

void main() {
  group('summarizeRuleSet', () {
    test('groups rules by jurisdiction and counts the total', () {
      final rules = [
        _rule(
          id: 'a',
          jurisdictionId: 'eu.easa.part-fcl',
          requirement: Requirement.flightEventCount(
            event: CountableFlightEvent.landings,
            count: 3,
            window: RuleWindow.rollingDays(90),
          ),
        ),
        _rule(
          id: 'b',
          jurisdictionId: 'eu.easa.part-fcl',
          requirement: Requirement.flightEventCount(
            event: CountableFlightEvent.landings,
            count: 3,
            window: RuleWindow.rollingDays(90),
          ),
        ),
        _rule(
          id: 'c',
          jurisdictionId: 'us.faa.part61',
          requirement: Requirement.flightEventCount(
            event: CountableFlightEvent.landings,
            count: 3,
            window: RuleWindow.rollingDays(90),
          ),
        ),
      ];

      final summary = summarizeRuleSet(rules);

      expect(summary.total, 3);
      expect(summary.byJurisdiction, {
        'eu.easa.part-fcl': 2,
        'us.faa.part61': 1,
      });
    });

    test('counts a top-level held_record_currently_valid medical rule', () {
      final rules = [
        _rule(
          id: 'med',
          jurisdictionId: 'eu.easa.part-fcl',
          requirement: Requirement.heldRecordCurrentlyValid(
            'medical_certificate.easaClass1',
          ),
        ),
      ];

      expect(summarizeRuleSet(rules).medicalCount, 1);
    });

    test('counts a medical rule nested inside an allOf/anyOf composite', () {
      final rules = [
        _rule(
          id: 'composite',
          jurisdictionId: 'us.faa.part61',
          requirement: Requirement.allOf([
            Requirement.flightEventCount(
              event: CountableFlightEvent.landings,
              count: 3,
              window: RuleWindow.rollingDays(90),
            ),
            Requirement.anyOf([
              Requirement.heldRecordCurrentlyValid(
                'medical_certificate.faaThirdClass',
              ),
            ]),
          ]),
        ),
      ];

      expect(summarizeRuleSet(rules).medicalCount, 1);
    });

    test('does not count a non-medical held-record requirement', () {
      final rules = [
        _rule(
          id: 'rating',
          jurisdictionId: 'eu.easa.part-fcl',
          requirement: Requirement.heldRecordCurrentlyValid(
            'held_rating.instrumentRating',
          ),
        ),
      ];

      expect(summarizeRuleSet(rules).medicalCount, 0);
    });

    test('an empty rule list summarizes to all zeros', () {
      final summary = summarizeRuleSet(const []);
      expect(summary.total, 0);
      expect(summary.byJurisdiction, isEmpty);
      expect(summary.medicalCount, 0);
    });
  });
}
