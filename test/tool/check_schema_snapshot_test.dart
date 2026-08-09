import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_schema_snapshot.dart';

void main() {
  group('schemasMatch', () {
    test('true for identical JSON', () {
      const json = '{"a": 1, "b": [1, 2, 3]}';
      expect(schemasMatch(json, json), isTrue);
    });

    test('true when formatting differs but content is the same', () {
      const a = '{"a": 1, "b": 2}';
      const b = '{\n  "b": 2,\n  "a": 1\n}';
      expect(schemasMatch(a, b), isTrue);
    });

    test('false when a value differs', () {
      const a = '{"a": 1}';
      const b = '{"a": 2}';
      expect(schemasMatch(a, b), isFalse);
    });

    test('false when a key is added or removed', () {
      const a = '{"a": 1}';
      const b = '{"a": 1, "b": 2}';
      expect(schemasMatch(a, b), isFalse);
    });

    test('false when a list differs', () {
      const a = '{"a": [1, 2]}';
      const b = '{"a": [1, 3]}';
      expect(schemasMatch(a, b), isFalse);
    });
  });
}
