import 'package:easa_digital_log/domain/currency/currency_rule.dart';
import 'package:easa_digital_log/domain/currency/currency_rule_yaml.dart';
import 'package:easa_digital_log/domain/currency/flight_condition.dart';
import 'package:easa_digital_log/domain/currency/rule_window.dart';
import 'package:easa_digital_log/domain/model/calendar_date.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('parseCurrencyRuleYaml', () {
    test('parses a minimal flight-event-count rule', () {
      const yaml = '''
id: easa.fcl060.passenger_recency
jurisdiction: eu.easa.part-fcl
citation: "FCL.060(b)(1)"
title: "Passenger recency"
effective_from: 2011-11-08
requirement:
  kind: flight_event_count
  event: landings
  count: 3
  window:
    kind: rolling_days
    days: 90
''';

      final rule = parseCurrencyRuleYaml(yaml);

      expect(rule.id, 'easa.fcl060.passenger_recency');
      expect(rule.jurisdictionId, 'eu.easa.part-fcl');
      expect(rule.citation, 'FCL.060(b)(1)');
      expect(rule.effectiveFrom, CalendarDate(2011, 11, 8));
      expect(rule.expiresOn, isNull);
      expect(
        rule.requirement,
        Requirement.flightEventCount(
          event: CountableFlightEvent.landings,
          count: 3,
          window: RuleWindow.rollingDays(90),
        ),
      );
    });

    test('parses expires_on when present', () {
      const yaml = '''
id: x
jurisdiction: eu.easa.part-fcl
citation: "x"
title: "x"
effective_from: 2011-11-08
expires_on: 2020-01-01
requirement:
  kind: held_record_currently_valid
  held_record_kind: x
''';

      final rule = parseCurrencyRuleYaml(yaml);

      expect(rule.expiresOn, CalendarDate(2020, 1, 1));
    });

    test('parses conditions: day/night, landing type, aircraft match', () {
      const yaml = '''
id: x
jurisdiction: eu.easa.part-fcl
citation: "x"
title: "x"
effective_from: 2011-11-08
requirement:
  kind: flight_event_count
  event: landings
  count: 1
  window:
    kind: rolling_days
    days: 90
  conditions:
    - kind: day_night
      value: night
    - kind: landing_type
      value: full_stop
    - kind: aircraft_match
      level: same_type_or_class
''';

      final rule = parseCurrencyRuleYaml(yaml);

      expect(rule.requirement.conditions, [
        FlightCondition.dayNight(DayNight.night),
        FlightCondition.landingType(LandingType.fullStop),
        FlightCondition.aircraftMatch(AircraftMatch.sameTypeOrClass),
      ]);
    });

    test('parses capacity and instructor_aboard conditions', () {
      const yaml = '''
id: x
jurisdiction: eu.easa.part-fcl
citation: "x"
title: "x"
effective_from: 2011-11-08
requirement:
  kind: flight_event_hours
  event: landings
  hours: 6
  window: { kind: rolling_days, days: 365 }
  conditions:
    - kind: capacity
      value: command_authority
    - kind: instructor_aboard
''';

      final rule = parseCurrencyRuleYaml(yaml);

      expect(rule.requirement.conditions, [
        FlightCondition.capacity(CapacityRequirement.commandAuthority),
        FlightCondition.instructorAboard(),
      ]);
    });

    test('parses the class_or_type_if_required aircraft match level', () {
      const yaml = '''
id: x
jurisdiction: us.faa.part61
citation: "x"
title: "x"
effective_from: 2011-11-08
requirement:
  kind: flight_event_count
  event: landings
  count: 3
  window: { kind: rolling_days, days: 90 }
  conditions:
    - kind: aircraft_match
      level: class_or_type_if_required
''';

      final rule = parseCurrencyRuleYaml(yaml);

      expect(rule.requirement.conditions, [
        FlightCondition.aircraftMatch(AircraftMatch.classOrTypeIfRequired),
      ]);
    });

    test(
      'parses a calendar-months window anchored to a held record expiry',
      () {
        const yaml = '''
id: x
jurisdiction: eu.easa.part-fcl
citation: "x"
title: "x"
effective_from: 2011-11-08
requirement:
  kind: flight_event_hours
  event: landings
  hours: 12
  window:
    kind: calendar_months
    months: 12
    anchor: held_record_expiry
    anchor_held_record_kind: eu.easa.sep_class_rating
''';

        final rule = parseCurrencyRuleYaml(yaml);

        expect(rule.requirement.hours, const FlightDuration(12 * 60));
        expect(
          rule.requirement.window,
          RuleWindow.calendarMonths(
            12,
            anchor: WindowAnchor.heldRecordExpiry,
            anchorHeldRecordKind: 'eu.easa.sep_class_rating',
          ),
        );
      },
    );

    test('parses fractional hours', () {
      const yaml = '''
id: x
jurisdiction: eu.easa.part-fcl
citation: "x"
title: "x"
effective_from: 2011-11-08
requirement:
  kind: flight_event_hours
  event: landings
  hours: 6.5
  window: { kind: rolling_days, days: 90 }
''';

      final rule = parseCurrencyRuleYaml(yaml);

      expect(rule.requirement.hours, const FlightDuration(6 * 60 + 30));
    });

    test(
      'parses a nested any_of composite (alternative means of compliance)',
      () {
        const yaml = '''
id: x
jurisdiction: eu.easa.part-fcl
citation: "x"
title: "x"
effective_from: 2011-11-08
requirement:
  kind: any_of
  of:
    - kind: flight_event_count
      event: landings
      count: 3
      window: { kind: rolling_days, days: 90 }
    - kind: held_record_currently_valid
      held_record_kind: proficiency_check
''';

        final rule = parseCurrencyRuleYaml(yaml);

        expect(rule.requirement.kind, RequirementKind.anyOf);
        expect(rule.requirement.of, hasLength(2));
        expect(rule.requirement.of[0].kind, RequirementKind.flightEventCount);
        expect(
          rule.requirement.of[1].kind,
          RequirementKind.heldRecordCurrentlyValid,
        );
      },
    );

    for (final missing in [
      'id',
      'jurisdiction',
      'citation',
      'title',
      'effective_from',
      'requirement',
    ]) {
      test(
        'throws FormatException naming the field when "$missing" is missing',
        () {
          final fields = {
            'id': 'x',
            'jurisdiction': 'eu.easa.part-fcl',
            'citation': 'x',
            'title': 'x',
            'effective_from': '2011-11-08',
          };
          fields.remove(missing);
          final buffer = StringBuffer();
          fields.forEach((key, value) => buffer.writeln('$key: $value'));
          if (missing != 'requirement') {
            buffer.writeln('requirement:');
            buffer.writeln('  kind: held_record_currently_valid');
            buffer.writeln('  held_record_kind: x');
          }

          expect(
            () => parseCurrencyRuleYaml(buffer.toString()),
            throwsA(
              isA<FormatException>().having(
                (e) => e.message,
                'message',
                contains(missing),
              ),
            ),
          );
        },
      );
    }

    test('rejects a malformed effective_from date', () {
      const yaml = '''
id: x
jurisdiction: eu.easa.part-fcl
citation: "x"
title: "x"
effective_from: "not-a-date"
requirement:
  kind: held_record_currently_valid
  held_record_kind: x
''';

      expect(() => parseCurrencyRuleYaml(yaml), throwsFormatException);
    });

    test('rejects an unknown requirement kind', () {
      const yaml = '''
id: x
jurisdiction: eu.easa.part-fcl
citation: "x"
title: "x"
effective_from: 2011-11-08
requirement:
  kind: not_a_real_kind
''';

      expect(() => parseCurrencyRuleYaml(yaml), throwsFormatException);
    });

    test('rejects a top-level document that is not a map', () {
      expect(
        () => parseCurrencyRuleYaml('- just\n- a list'),
        throwsFormatException,
      );
    });
  });
}
