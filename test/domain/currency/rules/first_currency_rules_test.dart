import 'dart:io';

import 'package:easa_digital_log/domain/currency/currency_rule.dart';
import 'package:easa_digital_log/domain/currency/currency_rule_evaluator.dart';
import 'package:easa_digital_log/domain/currency/currency_rule_yaml.dart';
import 'package:easa_digital_log/domain/currency/evaluation_subject.dart';
import 'package:easa_digital_log/domain/currency/flight_condition.dart';
import 'package:easa_digital_log/domain/currency/rule_window.dart';
import 'package:easa_digital_log/domain/model/aircraft.dart';
import 'package:easa_digital_log/domain/model/calendar_date.dart';
import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:flutter_test/flutter_test.dart';

import '../currency_test_helpers.dart';

CurrencyRule _loadRule(String path) =>
    parseCurrencyRuleYaml(File(path).readAsStringSync());

const _typeRatedAircraft = Aircraft(
  registration: 'G-JET',
  manufacturer: 'Cessna',
  model: 'Citation Mustang',
  icaoTypeDesignator: 'C510',
  typeRatingDesignator: 'C510S',
  category: AircraftCategory.aeroplane,
  engineType: EngineType.turbofan,
  engineCount: 2,
  operatingSurface: OperatingSurface.land,
  requiresMultiCrew: false,
);

void main() {
  const evaluator = CurrencyRuleEvaluator();

  group('easa.fcl060.b1_passenger_recency (#45)', () {
    final rule = _loadRule(
      'assets/rules/easa/fcl060_b1_passenger_recency.yaml',
    );

    test('metadata matches the regulation', () {
      expect(rule.citation, 'FCL.060(b)(1)');
      expect(rule.jurisdictionId, 'eu.easa.part-fcl');
    });

    test('satisfied by 3 landings, the oldest exactly 90 days back', () {
      final asOf = CalendarDate(2024, 6, 1);
      final subject = EvaluationSubject(
        referenceAircraft: testAircraft,
        flights: [
          currencyTestRecord(
            '1',
            currencyTestFlight(
              date: CalendarDate(2024, 3, 3), // exactly 90 days before asOf
              landings: const CircuitCounts(dayFullStop: 1),
            ),
          ),
          currencyTestRecord(
            '2',
            currencyTestFlight(
              date: CalendarDate(2024, 4, 1),
              landings: const CircuitCounts(dayFullStop: 1),
            ),
          ),
          currencyTestRecord(
            '3',
            currencyTestFlight(
              date: CalendarDate(2024, 5, 1),
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

    test('91 days back is outside the window', () {
      final asOf = CalendarDate(2024, 6, 1);
      final subject = EvaluationSubject(
        referenceAircraft: testAircraft,
        flights: [
          currencyTestRecord(
            '1',
            currencyTestFlight(
              date: CalendarDate(2024, 3, 2), // 91 days before asOf
              landings: const CircuitCounts(dayFullStop: 3),
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

    test('a different type or class does not count', () {
      final asOf = CalendarDate(2024, 6, 1);
      final subject = EvaluationSubject(
        referenceAircraft: const Aircraft(
          registration: 'G-REF',
          manufacturer: 'Piper',
          model: 'Arrow',
          category: AircraftCategory.aeroplane,
          engineType: EngineType.piston,
          engineCount: 1,
          operatingSurface: OperatingSurface.land,
          requiresMultiCrew: false,
        ),
        flights: [
          currencyTestRecord(
            '1',
            currencyTestFlight(
              date: CalendarDate(2024, 5, 1),
              landings: const CircuitCounts(dayFullStop: 3),
            ),
            aircraft: const Aircraft(
              registration: 'G-JET',
              manufacturer: 'Cessna',
              model: 'Citation',
              category: AircraftCategory.aeroplane,
              engineType: EngineType.turbofan,
              engineCount: 2,
              operatingSurface: OperatingSurface.land,
              requiresMultiCrew: false,
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
  });

  group('us.faa.61_57_a.takeoff_landing_currency (#48)', () {
    final rule = _loadRule(
      'assets/rules/faa/61_57_a_takeoff_landing_currency.yaml',
    );

    test('metadata matches the regulation', () {
      expect(rule.citation, '§61.57(a)');
      expect(rule.jurisdictionId, 'us.faa.part61');
    });

    test('takeoffs and landings are counted independently', () {
      // docs/entry-form.md 5's own example: a pilot who took over mid-flight
      // has zero takeoffs and one landing. Three such flights give 3
      // landings but 0 takeoffs, so currency is not met.
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
                takeoffs: const CircuitCounts(), // none -- took over mid-flight
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
      expect(result.components, hasLength(2));
      expect(result.components[0].satisfied, isFalse); // takeoffs
      expect(result.components[1].satisfied, isTrue); // landings
    });

    test(
      'requires the same type when the aircraft is type-rated, not merely the same class',
      () {
        final asOf = CalendarDate(2024, 6, 1);
        final subject = EvaluationSubject(
          referenceAircraft: _typeRatedAircraft,
          flights: [
            for (var i = 0; i < 3; i++)
              currencyTestRecord(
                '$i',
                currencyTestFlight(
                  date: CalendarDate(2024, 5, i + 1),
                  landings: const CircuitCounts(dayFullStop: 1),
                  takeoffs: const CircuitCounts(dayFullStop: 1),
                ),
                // Same engine/class shape as the reference, but a different
                // type rating -- §61.57(a) still requires the specific type.
                aircraft: const Aircraft(
                  registration: 'G-OTHERJET',
                  manufacturer: 'Embraer',
                  model: 'Phenom 100',
                  icaoTypeDesignator: 'E50P',
                  typeRatingDesignator: 'E50P',
                  category: AircraftCategory.aeroplane,
                  engineType: EngineType.turbofan,
                  engineCount: 2,
                  operatingSurface: OperatingSurface.land,
                  requiresMultiCrew: false,
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
  });

  group('us.faa.61_57_a2.tailwheel_takeoff_landing_currency (#48)', () {
    final rule = _loadRule(
      'assets/rules/faa/61_57_a2_tailwheel_takeoff_landing_currency.yaml',
    );

    test(
      'a touch-and-go does not count toward the tailwheel-specific rule',
      () {
        final asOf = CalendarDate(2024, 6, 1);
        final subject = EvaluationSubject(
          referenceAircraft: testAircraft,
          flights: [
            for (var i = 0; i < 3; i++)
              currencyTestRecord(
                '$i',
                currencyTestFlight(
                  date: CalendarDate(2024, 5, i + 1),
                  landings: const CircuitCounts(dayTouchAndGo: 1),
                  takeoffs: const CircuitCounts(dayTouchAndGo: 1),
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

    test('full-stop takeoffs and landings satisfy it', () {
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
                takeoffs: const CircuitCounts(dayFullStop: 1),
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
  });

  group('us.faa.61_57_b.night_takeoff_landing_currency (#48)', () {
    final rule = _loadRule(
      'assets/rules/faa/61_57_b_night_takeoff_landing_currency.yaml',
    );

    test('metadata matches the regulation', () {
      expect(rule.citation, '§61.57(b)');
    });

    test('a night touch-and-go does not satisfy the FAA night rule', () {
      final asOf = CalendarDate(2024, 6, 1);
      final subject = EvaluationSubject(
        referenceAircraft: testAircraft,
        flights: [
          for (var i = 0; i < 3; i++)
            currencyTestRecord(
              '$i',
              currencyTestFlight(
                date: CalendarDate(2024, 5, i + 1),
                landings: const CircuitCounts(nightTouchAndGo: 1),
                takeoffs: const CircuitCounts(nightTouchAndGo: 1),
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

    test('the same night touch-and-gos would satisfy an EASA-shaped night '
        'requirement that has no full-stop condition -- the #48 divergence: '
        'EASA night passenger recency (#46) accepts any landing type, FAA '
        "doesn't", () {
      final easaShapedNightRequirement = Requirement.flightEventCount(
        event: CountableFlightEvent.landings,
        count: 1,
        window: RuleWindow.rollingDays(90),
        conditions: [FlightCondition.dayNight(DayNight.night)],
      );
      final asOf = CalendarDate(2024, 6, 1);
      final subject = EvaluationSubject(
        referenceAircraft: testAircraft,
        flights: [
          currencyTestRecord(
            '1',
            currencyTestFlight(
              date: CalendarDate(2024, 5, 1),
              landings: const CircuitCounts(nightTouchAndGo: 1),
            ),
          ),
        ],
      );

      final faaResult = evaluator.evaluateRequirement(
        rule.requirement,
        subject,
        asOf,
      );
      final easaShapedResult = evaluator.evaluateRequirement(
        easaShapedNightRequirement,
        subject,
        asOf,
      );

      expect(faaResult.satisfied, isFalse);
      expect(easaShapedResult.satisfied, isTrue);
    });

    test('full-stop night takeoffs and landings satisfy it', () {
      final asOf = CalendarDate(2024, 6, 1);
      final subject = EvaluationSubject(
        referenceAircraft: testAircraft,
        flights: [
          for (var i = 0; i < 3; i++)
            currencyTestRecord(
              '$i',
              currencyTestFlight(
                date: CalendarDate(2024, 5, i + 1),
                landings: const CircuitCounts(nightFullStop: 1),
                takeoffs: const CircuitCounts(nightFullStop: 1),
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
  });
}
