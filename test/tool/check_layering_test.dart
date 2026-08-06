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

    test(
      'strips a banned import written inside a multi-line block comment',
      () {
        // Pins `dotAll: true` on _blockComment. Without it, `.` does not
        // match newlines, so `/\*.*?\*/` can only match a comment opener and
        // closer that sit on the same line. A comment spanning several
        // physical lines is then never recognised as a single unit and is
        // not stripped at all — so an import written on its own line *inside*
        // the comment would surface as a false-positive violation. Removing
        // `dotAll: true` turns this test red.
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
      // line-syntactic (no package:analyzer), so a Dart triple-quoted
      // string whose own line reads like an import directive is
      // indistinguishable from a real one. The guard fails closed: a
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
  });
}
