// flutter_test re-exports test/group/expect from package:test_api, so plain
// Dart tests need no separate package:test dependency.
import 'package:flutter_test/flutter_test.dart';

import 'package:easa_digital_log/domain/model/flight_duration.dart';

void main() {
  group('FlightDuration', () {
    test('sums ten thousand flights with exact integer arithmetic', () {
      final flights = List<FlightDuration>.filled(
        10000,
        FlightDuration.parseHoursMinutes('1:23'),
      );

      final total = FlightDuration.sum(flights);

      // 10,000 x 83 minutes.
      expect(total, const FlightDuration(830000));
      expect(total.inMinutes, 830000);
      expect(total.toHoursMinutes(), '13833:20');
      expect(total.toDecimalHours(), '13833.3');
    });

    test(
      'rounding at the display boundary is not the same as rounding first',
      () {
        // This is the whole reason the type exists. Summing the DISPLAY values
        // instead of the stored minutes is wrong by 166.7 hours over 10,000
        // flights, and nothing about the printed total would look suspicious.
        final one = FlightDuration.parseHoursMinutes('1:23');

        var roundedFirst = 0.0;
        for (var i = 0; i < 10000; i++) {
          roundedFirst += double.parse(one.toDecimalHours());
        }

        // Exact equality to 14000.0 does not hold here even in a correct
        // implementation: double.parse('1.4') summed 10,000 times via plain
        // IEEE-754 addition lands on 13999.999999997615, not 14000.0 exactly.
        // That is a property of binary floating-point summation, not of
        // FlightDuration -- the same drift appears for any implementation
        // whose toDecimalHours() correctly renders 83 minutes as '1.4'.
        // closeTo preserves the point of the test (the ~166.7-hour drift
        // against the correct 13833.3 total) without asserting an exact
        // double bit-pattern that summation does not actually produce.
        expect(roundedFirst, closeTo(14000.0, 0.001));
        expect(
          FlightDuration.sum(List.filled(10000, one)).toDecimalHours(),
          '13833.3',
        );
      },
    );

    test('decimal hours round-trip from decimal to minutes and back', () {
      // Minutes CANNOT round-trip through decimal hours: at one decimal place
      // only multiples of 6 minutes survive. The guaranteed direction is
      // decimal -> minutes -> decimal, which is what import fidelity needs.
      const samples = <String>[
        '0.0',
        '0.1',
        '0.5',
        '1.0',
        '1.4',
        '2.5',
        '12.3',
        '999.9',
      ];

      for (final sample in samples) {
        expect(
          FlightDuration.parseDecimalHours(sample).toDecimalHours(),
          sample,
          reason: 'round-trip failed for $sample',
        );
      }
    });

    test('parses decimal hours with integer arithmetic, not doubles', () {
      // double.parse('1.4') * 60 == 84.00000000000001. If the implementation
      // routes through a double, one of these will be off by a minute.
      expect(FlightDuration.parseDecimalHours('1.4').inMinutes, 84);
      expect(FlightDuration.parseDecimalHours('1.45').inMinutes, 87);
      expect(FlightDuration.parseDecimalHours('0.05').inMinutes, 3);
      expect(FlightDuration.parseDecimalHours('0.1').inMinutes, 6);
      expect(FlightDuration.parseDecimalHours('2').inMinutes, 120);
      expect(FlightDuration.parseDecimalHours('100.0').inMinutes, 6000);
    });

    test('formats decimal hours to tenths, half away from zero', () {
      const cases = <int, String>{
        0: '0.0',
        2: '0.0', // 0.0333 h
        3: '0.1', // 0.05 h exactly -> half away from zero
        6: '0.1',
        83: '1.4', // 1.3833 h
        85: '1.4', // 1.4166 h
        87: '1.5', // 1.45 h exactly -> half away from zero
        90: '1.5',
      };

      cases.forEach((minutes, expected) {
        expect(
          FlightDuration(minutes).toDecimalHours(),
          expected,
          reason: '$minutes minutes',
        );
      });
    });

    test('formats and parses HH:MM', () {
      const cases = <int, String>{
        0: '00:00',
        59: '00:59',
        60: '01:00',
        83: '01:23',
        6000: '100:00',
        74096: '1234:56',
      };

      cases.forEach((minutes, expected) {
        expect(FlightDuration(minutes).toHoursMinutes(), expected);
        expect(FlightDuration.parseHoursMinutes(expected).inMinutes, minutes);
      });

      // Unpadded hours are accepted on input even though output pads to two.
      expect(FlightDuration.parseHoursMinutes('1:23').inMinutes, 83);
    });

    test('rejects malformed input', () {
      const bad = <String>[
        '',
        'abc',
        '1:60',
        '1:5',
        '1:',
        ':30',
        '-1:00',
        '1:23:45',
        '1.4.5',
        '1,4',
        '.5',
        '-1.4',
        '1.0000000000',
      ];

      for (final source in bad) {
        expect(
          () => source.contains(':')
              ? FlightDuration.parseHoursMinutes(source)
              : FlightDuration.parseDecimalHours(source),
          throwsFormatException,
          reason: 'should reject "$source"',
        );
      }
    });

    test('orders, compares and de-duplicates by value', () {
      const a = FlightDuration(83);
      const b = FlightDuration(83);
      const c = FlightDuration(90);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      // `a` and `b` are equal by value on purpose -- this is the
      // de-duplication behaviour under test, not an accidental duplicate.
      // ignore: equal_elements_in_set
      expect(<FlightDuration>{a, b, c}, hasLength(2));
      expect(a < c, isTrue);
      expect(c > a, isTrue);
      expect(a <= b, isTrue);
      expect(<FlightDuration>[c, a].toList()..sort(), <FlightDuration>[a, c]);
      expect(a + c, const FlightDuration(173));
      expect((a - c).isNegative, isTrue);
      expect(FlightDuration.sum(const <FlightDuration>[]), FlightDuration.zero);
    });
  });
}
