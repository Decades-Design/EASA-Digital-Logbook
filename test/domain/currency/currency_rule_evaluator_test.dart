import 'package:easa_digital_log/domain/currency/currency_rule.dart';
import 'package:easa_digital_log/domain/currency/currency_rule_evaluator.dart';
import 'package:easa_digital_log/domain/currency/evaluation_subject.dart';
import 'package:easa_digital_log/domain/currency/flight_condition.dart';
import 'package:easa_digital_log/domain/currency/held_record.dart';
import 'package:easa_digital_log/domain/currency/rule_window.dart';
import 'package:easa_digital_log/domain/model/aircraft.dart';
import 'package:easa_digital_log/domain/model/calendar_date.dart';
import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/repository/flight_read_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import 'currency_test_helpers.dart';

Flight _flight({
  required CalendarDate date,
  CircuitCounts? landings,
  CircuitCounts? takeoffs,
  List<Approach> approaches = const [],
  int holdingProceduresCount = 0,
  bool trackingPerformed = false,
  Set<AlternativeComplianceEvent> alternativeComplianceEvents = const {},
  String aircraftRegistration = 'G-TEST',
}) => currencyTestFlight(
  date: date,
  landings: landings,
  takeoffs: takeoffs,
  approaches: approaches,
  holdingProceduresCount: holdingProceduresCount,
  trackingPerformed: trackingPerformed,
  alternativeComplianceEvents: alternativeComplianceEvents,
  aircraftRegistration: aircraftRegistration,
);

FlightRecord _record(String id, Flight flight, {Aircraft? aircraft}) =>
    currencyTestRecord(id, flight, aircraft: aircraft);

void main() {
  const evaluator = CurrencyRuleEvaluator();

  group('flightEventCount', () {
    final requirement = Requirement.flightEventCount(
      event: CountableFlightEvent.landings,
      count: 3,
      window: RuleWindow.rollingDays(90),
    );

    test('satisfied by exactly the boundary flights, and reports expiry', () {
      final asOf = CalendarDate(2024, 6, 1);
      final subject = EvaluationSubject(
        flights: [
          _record(
            '1',
            _flight(
              date: CalendarDate(2024, 3, 3), // exactly 90 days back
              landings: const CircuitCounts(dayFullStop: 1),
            ),
          ),
          _record(
            '2',
            _flight(
              date: CalendarDate(2024, 4, 1),
              landings: const CircuitCounts(dayFullStop: 1),
            ),
          ),
          _record(
            '3',
            _flight(
              date: CalendarDate(2024, 5, 1),
              landings: const CircuitCounts(dayFullStop: 1),
            ),
          ),
        ],
      );

      final result = evaluator.evaluateRequirement(requirement, subject, asOf);

      expect(result.satisfied, isTrue);
      expect(result.contributingFlightIds, unorderedEquals(['1', '2', '3']));
      // Oldest of the 3 relied-upon landings is 2024-03-03; recency lapses
      // the day after it falls outside the 90-day window.
      expect(result.expiresOn, CalendarDate(2024, 6, 1));
    });

    test(
      'one day later, the oldest landing has aged out and it is unsatisfied',
      () {
        final asOf = CalendarDate(2024, 6, 2);
        final subject = EvaluationSubject(
          flights: [
            _record(
              '1',
              _flight(
                date: CalendarDate(2024, 3, 3),
                landings: const CircuitCounts(dayFullStop: 1),
              ),
            ),
            _record(
              '2',
              _flight(
                date: CalendarDate(2024, 4, 1),
                landings: const CircuitCounts(dayFullStop: 1),
              ),
            ),
            _record(
              '3',
              _flight(
                date: CalendarDate(2024, 5, 1),
                landings: const CircuitCounts(dayFullStop: 1),
              ),
            ),
          ],
        );

        final result = evaluator.evaluateRequirement(
          requirement,
          subject,
          asOf,
        );

        expect(result.satisfied, isFalse);
        expect(result.expiresOn, isNull);
        expect(result.explanation, contains('2 of 3'));
      },
    );

    test('a flight contributing multiple landings counts each one', () {
      final asOf = CalendarDate(2024, 6, 1);
      final subject = EvaluationSubject(
        flights: [
          _record(
            '1',
            _flight(
              date: CalendarDate(2024, 5, 1),
              landings: const CircuitCounts(dayFullStop: 3),
            ),
          ),
        ],
      );

      final result = evaluator.evaluateRequirement(requirement, subject, asOf);

      expect(result.satisfied, isTrue);
      expect(result.contributingFlightIds, ['1']);
    });

    test('flights outside the window do not contribute', () {
      final asOf = CalendarDate(2024, 6, 1);
      final subject = EvaluationSubject(
        flights: [
          _record(
            '1',
            _flight(
              date: CalendarDate(2024, 3, 2), // 91 days back
              landings: const CircuitCounts(dayFullStop: 3),
            ),
          ),
        ],
      );

      final result = evaluator.evaluateRequirement(requirement, subject, asOf);

      expect(result.satisfied, isFalse);
      expect(result.contributingFlightIds, isEmpty);
    });
  });

  group('flightEventCount with day/night and full-stop conditions', () {
    test('night full-stop only counts the matching sub-count', () {
      final requirement = Requirement.flightEventCount(
        event: CountableFlightEvent.landings,
        count: 1,
        window: RuleWindow.rollingDays(90),
        conditions: [
          FlightCondition.dayNight(DayNight.night),
          FlightCondition.landingType(LandingType.fullStop),
        ],
      );
      final asOf = CalendarDate(2024, 6, 1);
      final subject = EvaluationSubject(
        flights: [
          _record(
            '1',
            _flight(
              date: CalendarDate(2024, 5, 1),
              landings: const CircuitCounts(dayFullStop: 5, nightTouchAndGo: 5),
            ),
          ),
        ],
      );

      final result = evaluator.evaluateRequirement(requirement, subject, asOf);

      expect(result.satisfied, isFalse);

      final withOneNightFullStop = EvaluationSubject(
        flights: [
          _record(
            '2',
            _flight(
              date: CalendarDate(2024, 5, 1),
              landings: const CircuitCounts(nightFullStop: 1),
            ),
          ),
        ],
      );
      expect(
        evaluator
            .evaluateRequirement(requirement, withOneNightFullStop, asOf)
            .satisfied,
        isTrue,
      );
    });
  });

  group('explanation wording', () {
    test(
      'names the day/night and landing-type qualifiers, not just the bare event',
      () {
        // #43's own example: "needs 1 more full-stop night landing", not
        // "needs 1 more landing".
        final requirement = Requirement.flightEventCount(
          event: CountableFlightEvent.landings,
          count: 3,
          window: RuleWindow.rollingDays(90),
          conditions: [
            FlightCondition.dayNight(DayNight.night),
            FlightCondition.landingType(LandingType.fullStop),
          ],
        );
        final subject = EvaluationSubject(
          flights: [
            _record(
              '1',
              _flight(
                date: CalendarDate(2024, 5, 1),
                landings: const CircuitCounts(nightFullStop: 2),
              ),
            ),
          ],
        );

        final result = evaluator.evaluateRequirement(
          requirement,
          subject,
          CalendarDate(2024, 6, 1),
        );

        expect(result.explanation, contains('night full-stop landings'));
        expect(result.explanation, contains('2 of 3'));
      },
    );
  });

  group('flightEventCount with aircraft match condition', () {
    final requirement = Requirement.flightEventCount(
      event: CountableFlightEvent.landings,
      count: 1,
      window: RuleWindow.rollingDays(90),
      conditions: [FlightCondition.aircraftMatch(AircraftMatch.sameType)],
    );

    test('only flights in the reference aircraft type count', () {
      final asOf = CalendarDate(2024, 6, 1);
      final subject = EvaluationSubject(
        referenceAircraft: const Aircraft(
          registration: 'G-REF',
          manufacturer: 'Piper',
          model: 'Arrow',
          icaoTypeDesignator: 'PA28',
          category: AircraftCategory.aeroplane,
          engineType: EngineType.piston,
          engineCount: 1,
          operatingSurface: OperatingSurface.land,
          requiresMultiCrew: false,
        ),
        flights: [
          _record(
            '1',
            _flight(
              date: CalendarDate(2024, 5, 1),
              landings: const CircuitCounts(dayFullStop: 1),
            ),
            aircraft: const Aircraft(
              registration: 'G-OTHER',
              manufacturer: 'Cessna',
              model: '152',
              icaoTypeDesignator: 'C152',
              category: AircraftCategory.aeroplane,
              engineType: EngineType.piston,
              engineCount: 1,
              operatingSurface: OperatingSurface.land,
              requiresMultiCrew: false,
            ),
          ),
          _record(
            '2',
            _flight(
              date: CalendarDate(2024, 5, 2),
              landings: const CircuitCounts(dayFullStop: 1),
            ),
            aircraft: const Aircraft(
              registration: 'G-SAME',
              manufacturer: 'Piper',
              model: 'Arrow',
              icaoTypeDesignator: 'PA28',
              category: AircraftCategory.aeroplane,
              engineType: EngineType.piston,
              engineCount: 1,
              operatingSurface: OperatingSurface.land,
              requiresMultiCrew: false,
            ),
          ),
        ],
      );

      final result = evaluator.evaluateRequirement(requirement, subject, asOf);

      expect(result.satisfied, isTrue);
      expect(result.contributingFlightIds, ['2']);
    });
  });

  group('flightEventCount with classOrTypeIfRequired aircraft match', () {
    final requirement = Requirement.flightEventCount(
      event: CountableFlightEvent.landings,
      count: 1,
      window: RuleWindow.rollingDays(90),
      conditions: [
        FlightCondition.aircraftMatch(AircraftMatch.classOrTypeIfRequired),
      ],
    );

    test(
      'requires the same type when the reference aircraft is type-rated',
      () {
        final subject = EvaluationSubject(
          referenceAircraft: const Aircraft(
            registration: 'G-REF',
            manufacturer: 'Airbus',
            model: 'A320',
            icaoTypeDesignator: 'A320',
            typeRatingDesignator: 'A320',
            category: AircraftCategory.aeroplane,
            engineType: EngineType.turbofan,
            engineCount: 2,
            operatingSurface: OperatingSurface.land,
            requiresMultiCrew: true,
          ),
          flights: [
            _record(
              'same-class-diff-type',
              _flight(
                date: CalendarDate(2024, 5, 1),
                landings: const CircuitCounts(dayFullStop: 1),
              ),
              aircraft: const Aircraft(
                registration: 'G-OTHER',
                manufacturer: 'Boeing',
                model: '737',
                icaoTypeDesignator: 'B737',
                typeRatingDesignator: 'B737',
                category: AircraftCategory.aeroplane,
                engineType: EngineType.turbofan,
                engineCount: 2,
                operatingSurface: OperatingSurface.land,
                requiresMultiCrew: true,
              ),
            ),
          ],
        );

        expect(
          evaluator
              .evaluateRequirement(
                requirement,
                subject,
                CalendarDate(2024, 6, 1),
              )
              .satisfied,
          isFalse,
        );
      },
    );

    test(
      'requires only the same class when the reference aircraft is class-rated',
      () {
        final subject = EvaluationSubject(
          referenceAircraft: const Aircraft(
            registration: 'G-REF',
            manufacturer: 'Cessna',
            model: '152',
            icaoTypeDesignator: 'C152',
            category: AircraftCategory.aeroplane,
            engineType: EngineType.piston,
            engineCount: 1,
            operatingSurface: OperatingSurface.land,
            requiresMultiCrew: false,
          ),
          flights: [
            _record(
              'same-class-diff-type-designator',
              _flight(
                date: CalendarDate(2024, 5, 1),
                landings: const CircuitCounts(dayFullStop: 1),
              ),
              aircraft: const Aircraft(
                registration: 'G-OTHER',
                manufacturer: 'Piper',
                model: 'Cherokee',
                icaoTypeDesignator: 'PA28',
                category: AircraftCategory.aeroplane,
                engineType: EngineType.piston,
                engineCount: 1,
                operatingSurface: OperatingSurface.land,
                requiresMultiCrew: false,
              ),
            ),
          ],
        );

        expect(
          evaluator
              .evaluateRequirement(
                requirement,
                subject,
                CalendarDate(2024, 6, 1),
              )
              .satisfied,
          isTrue,
        );
      },
    );
  });

  group(
    'flightEventCount over alt-compliance events and tracking (#121, #50)',
    () {
      test('a flight review event counts as a presence check', () {
        final requirement = Requirement.flightEventCount(
          event: CountableFlightEvent.faaFlightReview,
          count: 1,
          window: RuleWindow.calendarMonths(24),
        );
        final subject = EvaluationSubject(
          flights: [
            _record(
              '1',
              _flight(
                date: CalendarDate(2024, 1, 1),
                alternativeComplianceEvents: const {
                  AlternativeComplianceEvent.faaFlightReview,
                },
              ),
            ),
          ],
        );

        expect(
          evaluator
              .evaluateRequirement(
                requirement,
                subject,
                CalendarDate(2024, 6, 1),
              )
              .satisfied,
          isTrue,
        );
      });

      test(
        'an unrelated flight with no alt-compliance events does not count',
        () {
          final requirement = Requirement.flightEventCount(
            event: CountableFlightEvent.faaInstrumentProficiencyCheck,
            count: 1,
            window: RuleWindow.calendarMonths(6),
          );
          final subject = EvaluationSubject(
            flights: [_record('1', _flight(date: CalendarDate(2024, 1, 1)))],
          );

          expect(
            evaluator
                .evaluateRequirement(
                  requirement,
                  subject,
                  CalendarDate(2024, 6, 1),
                )
                .satisfied,
            isFalse,
          );
        },
      );

      test('trackingPerformed is read as a presence fact, not a count', () {
        final requirement = Requirement.flightEventCount(
          event: CountableFlightEvent.trackingPerformed,
          count: 1,
          window: RuleWindow.calendarMonths(6),
        );
        final subject = EvaluationSubject(
          flights: [
            _record(
              '1',
              _flight(date: CalendarDate(2024, 1, 1), trackingPerformed: true),
            ),
          ],
        );

        expect(
          evaluator
              .evaluateRequirement(
                requirement,
                subject,
                CalendarDate(2024, 6, 1),
              )
              .satisfied,
          isTrue,
        );
      });
    },
  );

  group('flightEventHours', () {
    test('sums flight duration, not count', () {
      final requirement = Requirement.flightEventHours(
        event: CountableFlightEvent.landings,
        hours: const FlightDuration(6 * 60),
        window: RuleWindow.rollingDays(365),
        conditions: const [],
      );
      final asOf = CalendarDate(2024, 6, 1);
      // Each flight is 1 hour (see _flight's fixed onBlocks - offBlocks).
      final subject = EvaluationSubject(
        flights: [
          for (var i = 0; i < 6; i++)
            _record(
              '$i',
              _flight(
                date: CalendarDate(2024, 5, i + 1),
                landings: const CircuitCounts(dayFullStop: 1),
              ),
            ),
        ],
      );

      final result = evaluator.evaluateRequirement(requirement, subject, asOf);

      expect(result.satisfied, isTrue);
    });
  });

  group('heldRecordCurrentlyValid', () {
    final requirement = Requirement.heldRecordCurrentlyValid(
      'us.faa.instrument_rating',
    );

    test('satisfied when a covering held record exists', () {
      final subject = EvaluationSubject(
        flights: const [],
        heldRecords: [
          HeldRecord(
            kind: 'us.faa.instrument_rating',
            validFrom: CalendarDate(2020, 1, 1),
          ),
        ],
      );

      final result = evaluator.evaluateRequirement(
        requirement,
        subject,
        CalendarDate(2024, 1, 1),
      );

      expect(result.satisfied, isTrue);
    });

    test('unsatisfied when no held record of that kind exists', () {
      final result = evaluator.evaluateRequirement(
        requirement,
        const EvaluationSubject(flights: []),
        CalendarDate(2024, 1, 1),
      );

      expect(result.satisfied, isFalse);
    });

    test('unsatisfied once the held record has expired', () {
      final subject = EvaluationSubject(
        flights: const [],
        heldRecords: [
          HeldRecord(
            kind: 'eu.easa.sep_class_rating',
            validFrom: CalendarDate(2022, 1, 1),
            validUntil: CalendarDate(2024, 1, 1),
          ),
        ],
      );
      final ratingRequirement = Requirement.heldRecordCurrentlyValid(
        'eu.easa.sep_class_rating',
      );

      final result = evaluator.evaluateRequirement(
        ratingRequirement,
        subject,
        CalendarDate(2024, 1, 2),
      );

      expect(result.satisfied, isFalse);
    });
  });

  group('anyOf', () {
    test('alternative means of compliance: satisfied if either branch is', () {
      final recency = Requirement.flightEventCount(
        event: CountableFlightEvent.landings,
        count: 3,
        window: RuleWindow.rollingDays(90),
      );
      final proficiencyCheckAlternative = Requirement.heldRecordCurrentlyValid(
        'proficiency_check',
      );
      final requirement = Requirement.anyOf([
        recency,
        proficiencyCheckAlternative,
      ]);

      final subject = EvaluationSubject(
        flights: const [],
        heldRecords: [
          HeldRecord(
            kind: 'proficiency_check',
            validFrom: CalendarDate(2024, 1, 1),
            validUntil: CalendarDate(2024, 12, 1),
          ),
        ],
      );

      final result = evaluator.evaluateRequirement(
        requirement,
        subject,
        CalendarDate(2024, 6, 1),
      );

      expect(result.satisfied, isTrue);
      expect(result.components, hasLength(2));
      expect(result.components[0].satisfied, isFalse);
      expect(result.components[1].satisfied, isTrue);
    });

    test('unsatisfied when every branch is', () {
      final requirement = Requirement.anyOf([
        Requirement.heldRecordCurrentlyValid('a'),
        Requirement.heldRecordCurrentlyValid('b'),
      ]);

      final result = evaluator.evaluateRequirement(
        requirement,
        const EvaluationSubject(flights: []),
        CalendarDate(2024, 6, 1),
      );

      expect(result.satisfied, isFalse);
    });
  });

  group('allOf', () {
    test('satisfied only when every branch is', () {
      final requirement = Requirement.allOf([
        Requirement.heldRecordCurrentlyValid('a'),
        Requirement.heldRecordCurrentlyValid('b'),
      ]);
      final subject = EvaluationSubject(
        flights: const [],
        heldRecords: [
          HeldRecord(kind: 'a', validFrom: CalendarDate(2020, 1, 1)),
        ],
      );

      final result = evaluator.evaluateRequirement(
        requirement,
        subject,
        CalendarDate(2024, 6, 1),
      );

      expect(result.satisfied, isFalse);
      expect(result.components[0].satisfied, isTrue);
      expect(result.components[1].satisfied, isFalse);
    });
  });

  group('CurrencyRuleEvaluator.evaluateRule', () {
    test('labels the result with the rule id and citation', () {
      final rule = CurrencyRule(
        id: 'test.rule',
        jurisdictionId: 'eu.easa.part-fcl',
        citation: 'FCL.060(b)(1)',
        effectiveFrom: CalendarDate(2020, 1, 1),
        requirement: Requirement.heldRecordCurrentlyValid('x'),
      );

      final evaluation = evaluator.evaluateRule(
        rule,
        const EvaluationSubject(flights: []),
        CalendarDate(2024, 1, 1),
      );

      expect(evaluation.ruleId, 'test.rule');
      expect(evaluation.citation, 'FCL.060(b)(1)');
      expect(evaluation.result.satisfied, isFalse);
    });
  });

  group('window anchored to a held record expiry', () {
    test(
      'sums hours in the fixed window preceding the rating expiry, not today',
      () {
        final requirement = Requirement.flightEventHours(
          event: CountableFlightEvent.landings,
          hours: const FlightDuration(2 * 60),
          window: RuleWindow.calendarMonths(
            12,
            anchor: WindowAnchor.heldRecordExpiry,
            anchorHeldRecordKind: 'eu.easa.sep_class_rating',
          ),
          conditions: const [],
        );
        final heldRecords = [
          HeldRecord(
            kind: 'eu.easa.sep_class_rating',
            validFrom: CalendarDate(2023, 1, 1),
            validUntil: CalendarDate(2025, 1, 1),
          ),
        ];
        // Two 1-hour flights inside [2024-01-01, 2025-01-01]; evaluated
        // "today" in 2024, long before the rating's own expiry.
        final subject = EvaluationSubject(
          flights: [
            _record(
              '1',
              _flight(
                date: CalendarDate(2024, 3, 1),
                landings: const CircuitCounts(dayFullStop: 1),
              ),
            ),
            _record(
              '2',
              _flight(
                date: CalendarDate(2024, 4, 1),
                landings: const CircuitCounts(dayFullStop: 1),
              ),
            ),
          ],
          heldRecords: heldRecords,
        );

        final result = evaluator.evaluateRequirement(
          requirement,
          subject,
          CalendarDate(2024, 6, 1),
        );

        expect(result.satisfied, isTrue);
      },
    );
  });
}
