import 'package:easa_digital_log/domain/currency/held_record.dart';
import 'package:easa_digital_log/domain/currency/rule_window.dart';
import 'package:easa_digital_log/domain/model/calendar_date.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('RuleWindow.rollingDays', () {
    test('start is exactly the boundary day, inclusive', () {
      // '3 in the preceding 90 days', evaluated on 2024-06-01: an event on
      // 2024-03-03 is exactly 90 days back and must still count -- #45's
      // acceptance criterion is a boundary test at exactly 90 days.
      final window = RuleWindow.rollingDays(90);
      final asOf = CalendarDate(2024, 6, 1);

      final range = window.rangeEndingAt(asOf, heldRecords: const []);

      expect(range.start, CalendarDate(2024, 3, 3));
      expect(range.end, asOf);
    });

    test('day 91 back falls outside the window', () {
      final window = RuleWindow.rollingDays(90);
      final asOf = CalendarDate(2024, 6, 1);
      final range = window.rangeEndingAt(asOf, heldRecords: const []);

      expect(CalendarDate(2024, 3, 2) < range.start, isTrue);
    });
  });

  group('RuleWindow.expiryFrom', () {
    test('rollingDays: the last day still within N days of the occurrence', () {
      final window = RuleWindow.rollingDays(90);

      final expiry = window.expiryFrom(CalendarDate(2024, 3, 3));

      expect(expiry, CalendarDate(2024, 6, 1));
    });

    test(
      'calendarMonths: valid through the end of the Nth month, not N*30 days',
      () {
        // A flight review on 2024-01-15 is valid for 24 calendar months --
        // #49: "valid through the end of the 24th month, not 730 days".
        final window = RuleWindow.calendarMonths(24);

        final expiry = window.expiryFrom(CalendarDate(2024, 1, 15));

        expect(expiry, CalendarDate(2026, 1, 31));
      },
    );

    test(
      'calendarMonths: from the 31st lands on the last real day of the target month',
      () {
        // #49: "Tests at the month boundary, including from the 31st of a
        // month" -- January 31 + 1 calendar month has no "31 February".
        final window = RuleWindow.calendarMonths(1);

        final expiry = window.expiryFrom(CalendarDate(2024, 1, 31));

        expect(expiry, CalendarDate(2024, 2, 29)); // 2024 is a leap year
      },
    );

    test(
      'anchored to a held record expiry uses that date, not evaluationDate',
      () {
        final window = RuleWindow.calendarMonths(
          12,
          anchor: WindowAnchor.heldRecordExpiry,
          anchorHeldRecordKind: 'eu.easa.sep_class_rating',
        );
        final heldRecords = [
          HeldRecord(
            kind: 'eu.easa.sep_class_rating',
            validFrom: CalendarDate(2023, 1, 1),
            validUntil: CalendarDate(2025, 1, 1),
          ),
        ];

        // Evaluated today, 2024-01-01, but the window is relative to the
        // rating's 2025-01-01 expiry, not to today -- #47.
        final range = window.rangeEndingAt(
          CalendarDate(2024, 1, 1),
          heldRecords: heldRecords,
        );

        expect(range.end, CalendarDate(2025, 1, 1));
        expect(range.start, CalendarDate(2024, 1, 1));
      },
    );

    test('anchored to a missing held record throws', () {
      final window = RuleWindow.calendarMonths(
        12,
        anchor: WindowAnchor.heldRecordExpiry,
        anchorHeldRecordKind: 'eu.easa.sep_class_rating',
      );

      expect(
        () => window.rangeEndingAt(
          CalendarDate(2024, 1, 1),
          heldRecords: const [],
        ),
        throwsStateError,
      );
    });
  });
}
