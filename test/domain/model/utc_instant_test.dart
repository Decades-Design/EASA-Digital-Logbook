import 'package:flutter_test/flutter_test.dart';

import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:easa_digital_log/domain/model/wall_clock.dart';

void main() {
  group('UtcInstant construction', () {
    test('rejects a local DateTime', () {
      expect(
        () => UtcInstant.fromDateTime(DateTime(2026, 3, 14, 9, 5)),
        throwsArgumentError,
      );
    });

    test('accepts a UTC DateTime', () {
      final instant = UtcInstant.fromDateTime(DateTime.utc(2026, 3, 14, 9, 5));
      expect(instant.toIso8601String(), '2026-03-14T09:05:00.000Z');
    });

    test('rejects an ISO string with no zone designator', () {
      // DateTime.parse returns a LOCAL DateTime for this string, silently.
      // That silence is the entire reason this type exists.
      expect(
        () => UtcInstant.parse('2026-03-14T09:05:00'),
        throwsFormatException,
      );
      expect(UtcInstant.tryParse('2026-03-14T09:05:00'), isNull);
    });

    test('accepts Z and normalises an explicit offset', () {
      expect(
        UtcInstant.parse('2026-03-14T09:05:00Z').toIso8601String(),
        '2026-03-14T09:05:00.000Z',
      );
      expect(
        UtcInstant.parse('2026-03-14T10:05:00+01:00').toIso8601String(),
        '2026-03-14T09:05:00.000Z',
      );
      expect(
        UtcInstant.parse('2026-03-14T04:05:00-05:00').toIso8601String(),
        '2026-03-14T09:05:00.000Z',
      );
    });

    test('always serialises with an explicit Z', () {
      // ADR-0002: never a bare offset-less string that could be read as local.
      final instant = UtcInstant.utc(2026, 3, 14, 9, 5);
      expect(instant.toIso8601String(), endsWith('Z'));
      expect(instant.asUtcDateTime.isUtc, isTrue);
    });

    test('round-trips through parse and format', () {
      const source = '2026-10-25T01:30:00.000Z';
      expect(UtcInstant.parse(source).toIso8601String(), source);
    });
  });

  group('UtcInstant ordering', () {
    test('orders, compares and de-duplicates by instant', () {
      final a = UtcInstant.utc(2026, 3, 14, 9, 5);
      final b = UtcInstant.utc(2026, 3, 14, 9, 5);
      final c = UtcInstant.utc(2026, 3, 14, 10, 42);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(<UtcInstant>{a, b, c}, hasLength(2));
      expect(a < c, isTrue);
      expect(c > a, isTrue);
      expect(a <= b, isTrue);
      expect(<UtcInstant>[c, a].toList()..sort(), <UtcInstant>[a, c]);
      expect(c.difference(a), const Duration(hours: 1, minutes: 37));
      expect(a.add(const Duration(hours: 1, minutes: 37)), c);
      expect(c.subtract(const Duration(hours: 1, minutes: 37)), a);
    });
  });

  group('WallClock rendering across DST transitions', () {
    // Europe/London 2026: BST begins 2026-03-29T01:00Z, ends 2026-10-25T01:00Z.

    test('renders either side of the spring-forward gap', () {
      expect(
        UtcInstant.parse('2026-03-29T00:59:00Z').toWallClock(Duration.zero),
        const WallClock(
          year: 2026,
          month: 3,
          day: 29,
          hour: 0,
          minute: 59,
          second: 0,
          offset: Duration.zero,
        ),
      );

      // 01:00 GMT is 02:00 BST — the hour 01:00-02:00 local never happens.
      expect(
        UtcInstant.parse(
          '2026-03-29T01:00:00Z',
        ).toWallClock(const Duration(hours: 1)).hour,
        2,
      );
    });

    test('the autumn ambiguous hour is one wall clock over two instants', () {
      // THE test. 01:30 local happens twice on 2026-10-25: once as BST and
      // once, an hour later, as GMT. Two different instants, one wall clock.
      // Storing the wall clock would make these indistinguishable; storing
      // UTC keeps them apart. This is what fails if anyone "simplifies"
      // UtcInstant back to a bare DateTime.
      final bst = UtcInstant.parse(
        '2026-10-25T00:30:00Z',
      ).toWallClock(const Duration(hours: 1));
      final gmt = UtcInstant.parse(
        '2026-10-25T01:30:00Z',
      ).toWallClock(Duration.zero);

      expect(bst.hour, 1);
      expect(bst.minute, 30);
      expect(gmt.hour, 1);
      expect(gmt.minute, 30);

      expect(bst.offset, const Duration(hours: 1));
      expect(gmt.offset, Duration.zero);
      expect(bst, isNot(gmt));

      expect(
        UtcInstant.parse('2026-10-25T00:30:00Z'),
        isNot(UtcInstant.parse('2026-10-25T01:30:00Z')),
      );
    });

    test('renders a western offset', () {
      // America/New_York 2026: EDT begins 2026-03-08T07:00Z (-5 -> -4).
      final before = UtcInstant.parse(
        '2026-03-08T06:59:00Z',
      ).toWallClock(const Duration(hours: -5));
      final after = UtcInstant.parse(
        '2026-03-08T07:00:00Z',
      ).toWallClock(const Duration(hours: -4));

      expect(before.hour, 1);
      expect(before.minute, 59);
      expect(after.hour, 3);
      expect(after.minute, 0);
    });

    test('renders a half-hour offset', () {
      final india = UtcInstant.parse(
        '2026-03-14T09:05:00Z',
      ).toWallClock(const Duration(hours: 5, minutes: 30));

      expect(india.hour, 14);
      expect(india.minute, 35);
      expect(india.toString(), '2026-03-14 14:35 +05:30');
    });

    test('crosses the date boundary when the offset shifts the day', () {
      final auckland = UtcInstant.parse(
        '2026-03-14T23:30:00Z',
      ).toWallClock(const Duration(hours: 13));

      expect(auckland.year, 2026);
      expect(auckland.month, 3);
      expect(auckland.day, 15);
      expect(auckland.hour, 12);
      expect(auckland.toString(), '2026-03-15 12:30 +13:00');
    });

    test('formats negative offsets correctly', () {
      final honolulu = UtcInstant.parse(
        '2026-03-14T09:05:00Z',
      ).toWallClock(const Duration(hours: -10, minutes: -30));

      expect(honolulu.toString(), '2026-03-13 22:35 -10:30');
    });
  });
}
