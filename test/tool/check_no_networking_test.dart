import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_no_networking.dart';

void main() {
  group('resolvedPackageNames', () {
    test('reads every top-level package name from a lockfile', () {
      const lockfile = '''
packages:
  csv:
    dependency: "direct main"
    source: hosted
    version: "8.0.0"
  meta:
    dependency: transitive
    source: hosted
    version: "1.16.0"
''';
      expect(resolvedPackageNames(lockfile), containsAll(['csv', 'meta']));
      expect(resolvedPackageNames(lockfile), hasLength(2));
    });

    test('returns nothing for a lockfile with no packages section', () {
      expect(resolvedPackageNames('# empty\n'), isEmpty);
    });
  });

  test("the real project's pubspec.lock resolves to nothing outside the "
      'allowlist', () {
    // Guards against the allowlist and the actual dependency tree
    // silently drifting apart — same "compare committed state against
    // what the tool would generate right now" shape as
    // check_schema_snapshot_test.dart's own real-file comparison.
    final lockfile = File('pubspec.lock').readAsStringSync();
    final resolved = resolvedPackageNames(lockfile);

    expect(
      resolved,
      isNotEmpty,
      reason: 'pubspec.lock should list this project\'s own dependencies',
    );
    final unexpected = resolved.where((p) => !allowedPackages.contains(p));
    expect(
      unexpected,
      isEmpty,
      reason:
          'a new dependency (direct or transitive) appeared that '
          "isn't on check_no_networking.dart's allowlist yet — see "
          "that file's own dartdoc for what to do",
    );
  });

  group('findSourceViolations', () {
    test('flags a package:http import', () {
      const source = "import 'package:http/http.dart' as http;\n";
      final violations = findSourceViolations('lib/thing.dart', source);

      expect(violations, hasLength(1));
      expect(violations.single.detail, contains('package:http/'));
      expect(violations.single.line, 1);
    });

    test('flags a direct dart:io HttpClient call', () {
      const source = '''
import 'dart:io';

void fetch() {
  final client = HttpClient();
}
''';
      final violations = findSourceViolations('lib/thing.dart', source);

      expect(violations, hasLength(1));
      expect(violations.single.detail, contains('HttpClient'));
    });

    test('flags WebSocket.connect', () {
      const source = '''
import 'dart:io';

void connect() {
  WebSocket.connect('ws://example.com');
}
''';
      final violations = findSourceViolations('lib/thing.dart', source);

      expect(violations, hasLength(1));
    });

    test('ignores a commented-out banned import', () {
      const source = "// import 'package:http/http.dart';\n";
      expect(findSourceViolations('lib/thing.dart', source), isEmpty);
    });

    test(
      "dart:io's own non-networking uses (File, Directory) are not flagged",
      () {
        const source = '''
import 'dart:io';

String readBackup(String path) => File(path).readAsStringSync();

void makeDir(String path) => Directory(path).createSync();
''';
        expect(findSourceViolations('lib/thing.dart', source), isEmpty);
      },
    );

    test('every real lib/ file is clean', () {
      // The same scan check_no_networking's own main() runs, over the
      // real source tree rather than an inline fixture — pins today's
      // clean state so a future accidental import fails this test
      // immediately, not just the next CI run.
      final violations = <SourceViolation>[];
      for (final entity in Directory('lib').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        if (entity.path.endsWith('.freezed.dart') ||
            entity.path.endsWith('.g.dart')) {
          continue;
        }
        violations.addAll(
          findSourceViolations(entity.path, entity.readAsStringSync()),
        );
      }
      expect(violations, isEmpty);
    });
  });
}
