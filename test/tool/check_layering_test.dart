// flutter_test re-exports test/group/expect from package:test_api, so plain
// Dart tests need no separate package:test dependency.
import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_layering.dart';

void main() {
  group('findViolations', () {
    test('flags a package:flutter import', () {
      const source = '''
import 'package:flutter/material.dart';

class Thing {}
''';
      final violations = findViolations('lib/domain/thing.dart', source);

      expect(violations, hasLength(1));
      expect(violations.single.uri, 'package:flutter/material.dart');
      expect(violations.single.line, 1);
    });

    test('flags an export as well as an import', () {
      const source = "export 'dart:io';\n";
      final violations = findViolations('lib/domain/thing.dart', source);

      expect(violations, hasLength(1));
      expect(violations.single.uri, 'dart:io');
    });

    test('allows a clean domain file', () {
      const source = '''
import 'dart:math';

import 'package:meta/meta.dart';

class Thing {}
''';
      expect(findViolations('lib/domain/thing.dart', source), isEmpty);
    });

    test('ignores a commented-out banned import', () {
      const source = '''
// import 'package:flutter/material.dart';
/* import 'dart:ui'; */

class Thing {}
''';
      expect(findViolations('lib/domain/thing.dart', source), isEmpty);
    });

    test('reports the correct line number for a later violation', () {
      const source = '''
import 'dart:math';

import 'dart:ui';
''';
      final violations = findViolations('lib/domain/thing.dart', source);

      expect(violations.single.line, 3);
    });

    // #98: Directory.listSync returns backslash-separated paths on Windows,
    // so a violation reported there must still read with forward slashes —
    // the same normalisation _escapesDomain already relies on internally.
    test('normalises Windows-style path separators in the reported path', () {
      const source = "import 'dart:io';\n";
      final violations = findViolations(
        r'lib\domain\primitives\thing.dart',
        source,
      );

      expect(violations.single.filePath, 'lib/domain/primitives/thing.dart');
      expect(violations.single.toString(), isNot(contains(r'\')));
    });

    test(
      'strips a banned import written inside a multi-line block comment',
      () {
        // Pins the newline-matching class in _comment's block-comment
        // alternative. With a plain `.` in place of `[\s\S]` the pattern can
        // only match an opener and closer sitting on the same physical line,
        // so a comment spanning several lines is never recognised as a single
        // unit and is not stripped at all — and the import written on its own
        // line *inside* it surfaces as a false-positive violation. Narrowing
        // that class turns this test red.
        const source = '''
/*
import 'package:flutter/material.dart';
*/
class Thing {}
''';
        expect(findViolations('lib/domain/thing.dart', source), isEmpty);
      },
    );

    test('known false positive: flags a banned import that only appears '
        'inside a multi-line string literal', () {
      // This is accepted, not desired, behaviour. Matching is
      // syntactic, not semantic (no package:analyzer), so a Dart
      // triple-quoted string whose own line reads like an import
      // directive is indistinguishable from a real one. The guard fails
      // closed: a
      // false positive breaks the build and a human looks, which is the
      // safe direction. See the limitations note on findViolations.
      const source = '''
const example = \'\'\'
import 'package:flutter/material.dart';
\'\'\';
''';
      final violations = findViolations('lib/domain/thing.dart', source);

      expect(violations, hasLength(1));
      expect(violations.single.uri, 'package:flutter/material.dart');
    });

    test('known gap: a banned import is not reported when a comment '
        'delimiter is opened inside a string literal above it', () {
      // This pins accepted, NOT desired, behaviour, in the opposite
      // direction from the false positive above: this one fails OPEN. A
      // library-level annotation is the one place a string literal can
      // legally sit above an import, since directives must precede other
      // declarations. `_stripComments` has no notion of string literals, so
      // the `/*` inside `@Deprecated('/*')` is read as a real block-comment
      // opener, and everything up to the next `*/` — including the
      // `dart:io` import below it — is stripped before the directive scan
      // ever runs. The import is real and reaches lib/domain/, but the
      // guard reports the file as clean. See the limitations note on
      // findViolations.
      //
      // If this test ever goes red because the hole was closed, that is
      // good news, but update this test deliberately rather than deleting
      // it — it exists to make a future fix visible, not to block one.
      const source = '''
@Deprecated('/*')
library;

import 'dart:io';

String readLogbook(String path) => File(path).readAsStringSync();

const closer = '*/';
''';
      final violations = findViolations('lib/domain/thing.dart', source);

      expect(violations, isEmpty);
    });
  });

  // Every test below reproduces a way the guard was verified to fail *open* —
  // i.e. a real `lib/domain/` dependency on Flutter or I/O that the CI
  // pipeline reported as clean. A guard that fails open is worse than no
  // guard, because the branch is green and nobody looks.
  group('findViolations — evasion classes', () {
    test('A1: flags the banned URI of a conditional import', () {
      // The idiomatic Dart way to reach dart:io behind a platform check, and
      // therefore the most likely way the dependency is reintroduced. The
      // banned URI is the *second* quoted string on the line.
      const source = '''
import 'a1_stub.dart' if (dart.library.io) 'dart:io';

class Thing {}
''';
      final violations = findViolations('lib/domain/thing.dart', source);

      expect(violations, hasLength(1));
      expect(violations.single.uri, 'dart:io');
      expect(violations.single.line, 1);
    });

    test('A2: flags a directive split across physical lines', () {
      // A directive is terminated by `;`, not by a newline. `dart format`
      // itself wraps a long directive like this.
      const source = '''
import
    'package:flutter/material.dart';

class Thing {}
''';
      final violations = findViolations('lib/domain/thing.dart', source);

      expect(violations, hasLength(1));
      expect(violations.single.uri, 'package:flutter/material.dart');
      expect(violations.single.line, 1);
    });

    test('A3: a `/*` inside a line comment does not swallow a real '
        'import', () {
      // If block comments are stripped before line comments, the `/*` below
      // opens a comment that runs to the `*/` on line 3, deleting the real
      // violation on line 2 along with it.
      const source = '''
// toggle: /*
import 'dart:io';
// end: */

class Thing {}
''';
      final violations = findViolations('lib/domain/thing.dart', source);

      expect(violations, hasLength(1));
      expect(violations.single.uri, 'dart:io');
      expect(violations.single.line, 2);
    });

    test('A4: flags cross-layer and remaining platform URIs', () {
      // domain/ is the innermost layer: it may not depend on data/, io/,
      // export/ or ui/ by package: URI or by a relative path that climbs out
      // of the domain tree. dart:isolate is not hypothetical — the
      // solar-position engine is exactly the kind of domain code that reaches
      // for one.
      const cases = <String>[
        'package:easa_digital_log/data/db.dart',
        'package:easa_digital_log/io/foreflight.dart',
        'package:easa_digital_log/export/pdf.dart',
        'package:easa_digital_log/ui/app.dart',
        '../../data/db.dart',
        'dart:ffi',
        'dart:isolate',
        'dart:developer',
        'dart:html',
      ];

      for (final uri in cases) {
        final violations = findViolations(
          'lib/domain/model/thing.dart',
          "import '$uri';\n",
        );

        expect(violations.map((v) => v.uri), <String>[
          uri,
        ], reason: '$uri must be reported');
      }
    });

    test('A5: flags exotic URI spellings', () {
      // A raw string is a legal directive URI, and adjacent string literals
      // concatenate — `'dart:' 'io'` *is* `dart:io` to the compiler.
      const cases = <String>[
        "import r'dart:io';\n",
        "import 'dart:' 'io';\n",
        'import r"package:flutter/material.dart";\n',
      ];
      const expected = <String>[
        'dart:io',
        'dart:io',
        'package:flutter/material.dart',
      ];

      for (var i = 0; i < cases.length; i++) {
        final violations = findViolations('lib/domain/thing.dart', cases[i]);

        expect(violations.map((v) => v.uri), <String>[
          expected[i],
        ], reason: 'case ${cases[i]} must be reported');
      }
    });

    test('allows a relative import that stays inside the domain tree', () {
      const source = '''
import '../model/flight.dart';
import 'aircraft.dart';

class Thing {}
''';
      expect(findViolations('lib/domain/model/thing.dart', source), isEmpty);
    });
  });
}
