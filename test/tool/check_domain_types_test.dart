import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_domain_types.dart';

void main() {
  group('findBannedTypes', () {
    const path = 'lib/domain/model/thing.dart';

    test('flags a DateTime field', () {
      const source = 'class Thing {\n  final DateTime when;\n}\n';
      final violations = findBannedTypes(path, source);

      expect(violations, hasLength(1));
      expect(violations.single.identifier, 'DateTime');
      expect(violations.single.line, 2);
    });

    test('flags a DateTime parameter', () {
      const source = 'void log(DateTime when) {}\n';
      expect(findBannedTypes(path, source), hasLength(1));
    });

    test('flags a DateTime return type', () {
      const source = 'DateTime now() => throw UnimplementedError();\n';
      expect(findBannedTypes(path, source), hasLength(1));
    });

    test('flags DateTime inside a generic', () {
      const source = 'final List<DateTime> stamps = <DateTime>[];\n';
      expect(findBannedTypes(path, source), hasLength(2));
    });

    test('flags DateTime as a map value type', () {
      const source = 'Map<String, DateTime> byName = {};\n';
      expect(findBannedTypes(path, source), hasLength(1));
    });

    test(
      'flags DateTime.now(), which is nondeterminism as well as a raw type',
      () {
        const source = 'final stamp = DateTime.now();\n';
        expect(findBannedTypes(path, source), hasLength(1));
      },
    );

    test('ignores DateTime in a line comment', () {
      const source = '// Never store a raw DateTime here.\nclass Thing {}\n';
      expect(findBannedTypes(path, source), isEmpty);
    });

    test('ignores DateTime in a block comment', () {
      const source = '/*\n * DateTime is banned.\n */\nclass Thing {}\n';
      expect(findBannedTypes(path, source), isEmpty);
    });

    test('ignores an identifier that merely contains DateTime', () {
      const source = 'class UtcDateTimeHolder {}\nfinal x = myDateTime;\n';
      expect(findBannedTypes(path, source), isEmpty);
    });

    test('allows the two files that must wrap DateTime', () {
      const source = 'final DateTime value = DateTime.utc(2026);\n';

      expect(
        findBannedTypes('lib/domain/model/utc_instant.dart', source),
        isEmpty,
      );
      expect(
        findBannedTypes('lib/domain/model/wall_clock.dart', source),
        isEmpty,
      );
      // Windows-style separators must resolve to the same allowlist entry.
      expect(
        findBannedTypes(r'lib\domain\model\utc_instant.dart', source),
        isEmpty,
      );
      // But a lookalike path is not allowlisted.
      expect(
        findBannedTypes('lib/domain/model/utc_instant_helper.dart', source),
        hasLength(2),
      );
    });

    test('reports every occurrence with its own line number', () {
      const source =
          'final DateTime a = DateTime.utc(2026);\nfinal DateTime b = a;\n';
      final violations = findBannedTypes(path, source);

      expect(violations, hasLength(3));
      expect(violations.map((v) => v.line), <int>[1, 1, 2]);
    });
  });
}
