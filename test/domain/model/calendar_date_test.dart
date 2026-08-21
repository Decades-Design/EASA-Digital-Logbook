// flutter_test re-exports test/group/expect from package:test_api, so plain
// Dart tests need no separate package:test dependency.
import 'package:easa_digital_log/domain/model/calendar_date.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('CalendarDate.fromUtcInstant', () {
    test('takes the UTC calendar date, ignoring time of day', () {
      final date = CalendarDate.fromUtcInstant(
        UtcInstant.utc(2026, 6, 15, 23, 40),
      );

      expect(date, const CalendarDate(2026, 6, 15));
    });
  });

  group('CalendarDate.addDays', () {
    test('crosses a month boundary', () {
      expect(
        const CalendarDate(2024, 1, 28).addDays(5),
        const CalendarDate(2024, 2, 2),
      );
    });

    test('crosses a leap-year February 29', () {
      expect(
        const CalendarDate(2024, 2, 28).addDays(1),
        const CalendarDate(2024, 2, 29),
      );
    });

    test('negative days moves backward across a year boundary', () {
      expect(
        const CalendarDate(2024, 1, 3).addDays(-5),
        const CalendarDate(2023, 12, 29),
      );
    });
  });

  group('CalendarDate.differenceInDays', () {
    test('is the inverse of addDays', () {
      const start = CalendarDate(2024, 1, 28);
      const end = CalendarDate(2024, 3, 2);

      expect(end.differenceInDays(start), 34);
      expect(start.addDays(34), end);
    });

    test('is negative when this date is earlier than other', () {
      expect(
        const CalendarDate(
          2024,
          1,
          1,
        ).differenceInDays(const CalendarDate(2024, 1, 10)),
        -9,
      );
    });

    test('is zero for the same date', () {
      const date = CalendarDate(2024, 6, 15);
      expect(date.differenceInDays(date), 0);
    });
  });

  group('CalendarDate', () {
    test('orders, compares and de-duplicates by value', () {
      const a = CalendarDate(2026, 6, 15);
      const b = CalendarDate(2026, 6, 15);
      const c = CalendarDate(2026, 6, 16);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      // `a` and `b` are equal by value on purpose -- this is the
      // de-duplication behaviour under test, not an accidental duplicate.
      // ignore: equal_elements_in_set
      expect(<CalendarDate>{a, b, c}, hasLength(2));
      expect(a < c, isTrue);
      expect(c > a, isTrue);
      expect(a <= b, isTrue);
      expect(a >= b, isTrue);
      expect(<CalendarDate>[c, a].toList()..sort(), <CalendarDate>[a, c]);
    });

    test('compares across month and year boundaries, not just the day', () {
      const endOfYear = CalendarDate(2025, 12, 31);
      const startOfNextYear = CalendarDate(2026, 1, 1);
      const midMonth = CalendarDate(2026, 1, 15);

      expect(endOfYear < startOfNextYear, isTrue);
      expect(startOfNextYear < midMonth, isTrue);
    });

    test('month outranks day within the same year — a later month with an '
        'earlier day-of-month is still later', () {
      const earlyInApril = CalendarDate(2026, 4, 5);
      const lateInMarch = CalendarDate(2026, 3, 20);

      expect(
        lateInMarch < earlyInApril,
        isTrue,
        reason:
            'comparing day-of-month alone (20 vs 5) would wrongly say '
            'the March date is later',
      );
    });

    test('formats as zero-padded ISO-8601 date', () {
      expect(const CalendarDate(2026, 1, 5).toString(), '2026-01-05');
    });

    test('parses YYYY-MM-DD, round-tripping toString', () {
      expect(CalendarDate.parse('2026-01-05'), const CalendarDate(2026, 1, 5));
      expect(
        CalendarDate.parse(const CalendarDate(2027, 12, 31).toString()),
        const CalendarDate(2027, 12, 31),
      );
    });

    test('rejects malformed input', () {
      for (final bad in ['2026-1-5', '2026/01/05', '05-01-2026', '', 'abc']) {
        expect(
          () => CalendarDate.parse(bad),
          throwsFormatException,
          reason: bad,
        );
      }
    });
  });
}
