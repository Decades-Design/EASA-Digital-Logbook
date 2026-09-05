import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_io_vendor_leak.dart';

void main() {
  group('findVendorLeaks', () {
    test('flags a vendor identifier in lib/data/', () {
      const source = 'class ForeFlightRow {}\n';
      final leaks = findVendorLeaks('lib/data/thing.dart', source);

      expect(leaks, hasLength(1));
      expect(leaks.single.vendorName, 'ForeFlight');
      expect(leaks.single.line, 1);
    });

    test('flags a vendor identifier in lib/ui/', () {
      const source = "const label = 'Imported from Garmin Pilot';\n";
      final leaks = findVendorLeaks('lib/ui/settings/thing.dart', source);

      expect(leaks, hasLength(1));
      expect(leaks.single.vendorName, 'Garmin');
    });

    test('allows the same name inside lib/io/', () {
      const source = 'class ForeFlightAdapter {}\n';
      expect(
        findVendorLeaks('lib/io/foreflight/adapter.dart', source),
        isEmpty,
      );
    });

    test('ignores a comment explaining a design decision by vendor name', () {
      const source = '''
// ForeFlight and Garmin both export a single "PIC" figure per flight.
class Aircraft {}
''';
      expect(
        findVendorLeaks('lib/domain/model/aircraft.dart', source),
        isEmpty,
      );
    });

    test('is case-sensitive to the vendor\'s own capitalisation', () {
      const source = "const x = 'foreflightless';\n";
      expect(findVendorLeaks('lib/ui/thing.dart', source), isEmpty);
    });

    test('flags a compound identifier a real adapter would plausibly use '
        '(regression: a `\\b`-bounded match let ForeFlightRow slip past, '
        'since Dart identifiers concatenate words with no separator)', () {
      const source = 'class ForeFlightRow {}\nclass GarminCsvRow {}\n';
      final leaks = findVendorLeaks('lib/data/thing.dart', source);

      expect(leaks, hasLength(2));
      expect(leaks.map((l) => l.vendorName), ['ForeFlight', 'Garmin']);
    });

    test('every real lib/ file is clean', () {
      // Pins today's clean state, the same shape as
      // check_no_networking_test.dart's own real-tree assertion — a future
      // accidental leak fails this test immediately, not just the next CI
      // run.
      final leaks = <VendorLeak>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.path.endsWith('.freezed.dart') ||
            entity.path.endsWith('.g.dart')) {
          continue;
        }
        leaks.addAll(findVendorLeaks(entity.path, entity.readAsStringSync()));
      }
      expect(leaks, isEmpty);
    });
  });
}
