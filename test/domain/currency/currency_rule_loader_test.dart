import 'package:easa_digital_log/domain/currency/currency_rule_loader.dart';
import 'package:easa_digital_log/domain/model/calendar_date.dart';
import 'package:flutter_test/flutter_test.dart';

const _v1 = '''
id: faa.61_56.flight_review
jurisdiction: us.faa.part61
citation: "§61.56 (pre-2020 wording)"
effective_from: 2010-01-01
expires_on: 2020-06-01
requirement:
  kind: held_record_currently_valid
  held_record_kind: flight_review
''';

const _v2 = '''
id: faa.61_56.flight_review
jurisdiction: us.faa.part61
citation: "§61.56"
effective_from: 2020-06-01
requirement:
  kind: held_record_currently_valid
  held_record_kind: flight_review
''';

const _otherRule = '''
id: easa.fcl060.passenger_recency
jurisdiction: eu.easa.part-fcl
citation: "FCL.060(b)(1)"
effective_from: 2011-11-08
requirement:
  kind: held_record_currently_valid
  held_record_kind: x
''';

void main() {
  group('CurrencyRuleLoader.fromYaml', () {
    test(
      'loads every file and resolves the version in force on a given date',
      () {
        final loader = CurrencyRuleLoader.fromYaml([_v1, _v2, _otherRule]);

        final beforeTransition = loader.resolve(
          'faa.61_56.flight_review',
          CalendarDate(2020, 5, 31),
        );
        final onTransition = loader.resolve(
          'faa.61_56.flight_review',
          CalendarDate(2020, 6, 1),
        );

        expect(beforeTransition.citation, '§61.56 (pre-2020 wording)');
        expect(onTransition.citation, '§61.56');
      },
    );

    test(
      'a historical flight is evaluated against the rule in force on its own date',
      () {
        // #41's own framing: "a flight in 2019 must be evaluated against the
        // rule in force in 2019", regardless of which version is current now.
        final loader = CurrencyRuleLoader.fromYaml([_v1, _v2]);

        final rule2019 = loader.resolve(
          'faa.61_56.flight_review',
          CalendarDate(2019, 1, 1),
        );

        expect(rule2019.citation, '§61.56 (pre-2020 wording)');
      },
    );

    test('superseded versions are retained, not deleted', () {
      final loader = CurrencyRuleLoader.fromYaml([_v1, _v2]);

      expect(
        loader.versionsOf('faa.61_56.flight_review').map((r) => r.citation),
        containsAll(['§61.56 (pre-2020 wording)', '§61.56']),
      );
    });

    test('throws ArgumentError naming the id when it is unknown', () {
      final loader = CurrencyRuleLoader.fromYaml([_otherRule]);

      expect(
        () => loader.resolve('no.such.rule', CalendarDate(2024, 1, 1)),
        throwsA(
          isA<ArgumentError>().having(
            (e) => e.message,
            'message',
            contains('no.such.rule'),
          ),
        ),
      );
    });

    test('throws StateError when evaluated before any version existed', () {
      final loader = CurrencyRuleLoader.fromYaml([_v1, _v2]);

      expect(
        () =>
            loader.resolve('faa.61_56.flight_review', CalendarDate(2005, 1, 1)),
        throwsStateError,
      );
    });

    test(
      'fails loudly at load time when one file is malformed, not deferred to evaluation',
      () {
        expect(
          () => CurrencyRuleLoader.fromYaml([_otherRule, 'not: [valid, rule']),
          throwsFormatException,
        );
      },
    );

    test('rejects two versions of the same rule sharing an effective_from', () {
      const duplicate = '''
id: faa.61_56.flight_review
jurisdiction: us.faa.part61
citation: "a different citation, same effective date"
effective_from: 2010-01-01
requirement:
  kind: held_record_currently_valid
  held_record_kind: flight_review
''';

      expect(
        () => CurrencyRuleLoader.fromYaml([_v1, duplicate]),
        throwsStateError,
      );
    });
  });
}
