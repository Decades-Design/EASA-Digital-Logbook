import 'package:flutter_test/flutter_test.dart';

import 'pdf_bytes_normalization.dart';

void main() {
  test('two different /ID trailer values normalize to the same bytes', () {
    final a = '<</ID[<aaaa><aaaa>]/Root 2 0 R>>'.codeUnits;
    final b = '<</ID[<bbbb><bbbb>]/Root 2 0 R>>'.codeUnits;

    expect(
      normalizeNonDeterministicBytes(a),
      normalizeNonDeterministicBytes(b),
    );
  });

  test(
    'a real content difference elsewhere in the bytes still compares unequal',
    () {
      final a = '<</ID[<aaaa><aaaa>]/Root 2 0 R>>'.codeUnits;
      final b = '<</ID[<bbbb><bbbb>]/Root 3 0 R>>'.codeUnits;

      expect(
        normalizeNonDeterministicBytes(a),
        isNot(equals(normalizeNonDeterministicBytes(b))),
      );
    },
  );

  test('bytes with no /ID entry pass through unchanged', () {
    final bytes = 'no id here'.codeUnits;

    expect(normalizeNonDeterministicBytes(bytes), bytes);
  });
}
