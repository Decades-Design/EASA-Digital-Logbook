import 'dart:math';

import 'package:easa_digital_log/data/ulid.dart';
import 'package:flutter_test/flutter_test.dart';

final RegExp _ulidPattern = RegExp(r'^[0-9A-HJKMNP-TV-Z]{26}$');

void main() {
  group('generateUlid', () {
    test('produces a 26-character Crockford base32 string', () {
      final ulid = generateUlid();
      expect(ulid, matches(_ulidPattern));
    });

    test('is unique across a burst of same-millisecond generation', () {
      final fixedNow = DateTime.utc(2026, 8, 9, 12, 0, 0);
      final ulids = List.generate(
        1000,
        (_) => generateUlid(now: fixedNow, random: Random.secure()),
      );
      expect(ulids.toSet(), hasLength(1000));
    });

    test('the timestamp portion is chronologically sortable', () {
      final earlier = generateUlid(now: DateTime.utc(2026, 1, 1));
      final later = generateUlid(now: DateTime.utc(2026, 6, 1));
      expect(
        earlier.substring(0, 10).compareTo(later.substring(0, 10)) < 0,
        isTrue,
      );
    });
  });
}
