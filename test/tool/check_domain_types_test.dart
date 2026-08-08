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
      // A directory prefix that happens to end in the right characters is
      // not allowlisted either — a character-level suffix match would treat
      // this as the wrapper file since it ends with the same characters.
      expect(
        findBannedTypes('xlib/domain/model/utc_instant.dart', source),
        hasLength(2),
      );
      // Nor is a nested path that repeats the allowlisted path as a
      // trailing *segment* sequence — this rules out a path-boundary check
      // on trailing segments alone, since the trailing four segments here
      // are still exactly `lib/domain/model/utc_instant.dart`, immediately
      // preceded by a `/`.
      expect(
        findBannedTypes(
          'lib/domain/foo/lib/domain/model/utc_instant.dart',
          source,
        ),
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

    test('known gap: a real DateTime is not reported when a comment '
        'delimiter is opened inside a string literal above it', () {
      // This pins accepted, NOT desired, behaviour — the same fail-open gap
      // `check_layering_test.dart` pins for the sibling guard, inherited
      // here because both guards share `stripComments`. `stripComments` has
      // no notion of string literals, so the `/*` inside the string literal
      // `'/*'` is read as a real block-comment opener, and everything up to
      // the next `*/` — including the genuine, undeclared `DateTime` below
      // it — is stripped before the identifier scan ever runs. The
      // violation is real and reaches lib/domain/, but the guard reports the
      // file as clean.
      //
      // If this test ever goes red because the hole was closed, that is
      // good news, but update this test deliberately rather than deleting
      // it — it exists to make a future fix visible, not to block one. See
      // the fail-open discussion on findBannedTypes.
      const source = '''
const String trap = '/*';
final DateTime when = DateTime.now(); // never reported
/* a totally unrelated, later, legitimate block comment */
''';

      expect(findBannedTypes(path, source), isEmpty);
    });
  });
}
