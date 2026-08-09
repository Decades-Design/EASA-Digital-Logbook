import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Mirrors the list `flight_test.dart` guards on `Flight` itself — a
/// derived quantity must never become a stored column either, per
/// ADR-0001. This is the schema-level half of #31's "the model exposes no
/// field whose name matches a derived-quantity pattern" acceptance
/// criterion.
const List<String> _derivedQuantityNames = <String>[
  'picTime',
  'dualTime',
  'nightTime',
  'crossCountryTime',
  'totalTime',
  'picusTime',
  'spicTime',
];

const List<String> _tableFiles = <String>[
  'lib/data/tables/aircraft_tables.dart',
  'lib/data/tables/custom_aerodrome_table.dart',
  'lib/data/tables/flight_tables.dart',
];

void main() {
  test('no Drift table column name matches a derived-quantity pattern', () {
    for (final path in _tableFiles) {
      final source = File(path).readAsStringSync();
      for (final name in _derivedQuantityNames) {
        expect(
          RegExp('\\b$name\\b', caseSensitive: false).hasMatch(source),
          isFalse,
          reason: '$path stores a column matching "$name" — see ADR-0001',
        );
      }
    }
  });
}
