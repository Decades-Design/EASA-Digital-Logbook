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
  });
}
