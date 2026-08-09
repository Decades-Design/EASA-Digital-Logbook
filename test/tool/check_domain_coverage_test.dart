// flutter_test re-exports test/group/expect from package:test_api, so plain
// Dart tests need no separate package:test dependency.
import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_domain_coverage.dart';

void main() {
  group('parseLcov', () {
    test('parses one record', () {
      const lcov = '''
SF:lib/domain/model/flight.dart
DA:1,3
DA:2,0
DA:3,1
LF:3
LH:2
end_of_record
''';
      final records = parseLcov(lcov);

      expect(records, hasLength(1));
      expect(records.single.path, 'lib/domain/model/flight.dart');
      expect(records.single.linesFound, 3);
      expect(records.single.linesHit, 2);
    });

    test('parses several records', () {
      const lcov = '''
SF:lib/domain/model/flight.dart
DA:1,1
LF:1
LH:1
end_of_record
SF:lib/domain/model/aircraft.dart
DA:1,0
LF:1
LH:0
end_of_record
''';
      final records = parseLcov(lcov);

      expect(records, hasLength(2));
      expect(records[0].path, 'lib/domain/model/flight.dart');
      expect(records[1].path, 'lib/domain/model/aircraft.dart');
    });

    // #98/#7: flutter test --coverage writes backslash-separated SF: paths
    // on Windows — the same footgun check_layering.dart has for its own
    // reported paths, and the reason recordsUnder's prefix match would
    // silently match nothing on a Windows-generated trace file without this.
    test('normalises backslash-separated paths', () {
      const lcov = '''
SF:lib\\domain\\model\\flight.dart
DA:1,1
LF:1
LH:1
end_of_record
''';
      final records = parseLcov(lcov);

      expect(records.single.path, 'lib/domain/model/flight.dart');
    });

    test(
      'prefers LF:/LH: over the derived DA: count when both are present',
      () {
        // LF:/LH: are lcov's own authoritative summary; deliberately mismatched
        // from what counting DA: lines would give (2 found, 1 hit), so a
        // parser that ignores LF:/LH: in favour of always deriving from DA:
        // is caught here rather than only in the "absent" case.
        const lcov = '''
SF:lib/domain/model/flight.dart
DA:1,1
DA:2,0
LF:9
LH:9
end_of_record
''';
        final records = parseLcov(lcov);

        expect(records.single.linesFound, 9);
        expect(records.single.linesHit, 9);
      },
    );

    test('falls back to counting DA: lines when LF:/LH: are absent', () {
      const lcov = '''
SF:lib/domain/model/flight.dart
DA:1,1
DA:2,0
DA:3,4
end_of_record
''';
      final records = parseLcov(lcov);

      expect(records.single.linesFound, 3);
      expect(records.single.linesHit, 2);
    });

    test('tolerates a trace file missing its final end_of_record', () {
      const lcov = '''
SF:lib/domain/model/flight.dart
DA:1,1
LF:1
LH:1''';
      final records = parseLcov(lcov);

      expect(records, hasLength(1));
    });
  });

  group('recordsUnder', () {
    final all = [
      const FileCoverage(
        path: 'lib/domain/model/flight.dart',
        linesFound: 10,
        linesHit: 10,
      ),
      const FileCoverage(
        path: 'lib/domain/model/flight.freezed.dart',
        linesFound: 100,
        linesHit: 0,
      ),
      const FileCoverage(
        path: 'lib/ui/screens/entry_form.dart',
        linesFound: 50,
        linesHit: 5,
      ),
    ];

    test('excludes a record outside the target directory', () {
      final domain = recordsUnder(all, 'lib/domain/');

      expect(domain.any((r) => r.path.startsWith('lib/ui/')), isFalse);
    });

    test('excludes generated files even under the target directory', () {
      // The fixture's flight.freezed.dart has 100 uncovered lines. If it
      // were not excluded, its 0% would drag the aggregate figure down —
      // it is not reachable code anyone wrote or is expected to test
      // directly (ADR-0006).
      final domain = recordsUnder(all, 'lib/domain/');

      expect(domain.any((r) => r.path.endsWith('.freezed.dart')), isFalse);
      expect(domain.map((r) => r.path), ['lib/domain/model/flight.dart']);
    });
  });

  group('aggregatePercent', () {
    test('weights by summed lines, not by averaging per-file percentages', () {
      // A naive average of (100%, 0%) is 50%. Weighted by lines, this is
      // 1000/1010 ≈ 99% — a large well-tested file cannot be dragged down
      // to look like a coin flip by one tiny untested one.
      final records = [
        const FileCoverage(
          path: 'lib/domain/a.dart',
          linesFound: 1000,
          linesHit: 1000,
        ),
        const FileCoverage(
          path: 'lib/domain/b.dart',
          linesFound: 10,
          linesHit: 0,
        ),
      ];

      final percent = aggregatePercent(records);

      expect(percent, closeTo(99.0, 0.1));
      expect(percent, isNot(closeTo(50.0, 1)));
    });

    test('an empty record set is 100%, not a division by zero', () {
      expect(aggregatePercent(const []), 100);
    });
  });
}
