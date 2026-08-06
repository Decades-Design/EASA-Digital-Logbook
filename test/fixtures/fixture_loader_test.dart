import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import 'fixture_loader.dart';

void main() {
  group('loadFixture', () {
    test('loads the FAA/EASA divergence flight', () {
      final fixture = loadFixture('flights', 'faa_easa_divergence');

      expect(fixture, isA<YamlMap>());
      expect(fixture['sole_manipulator'], isTrue);
      expect(fixture['command_authority'], isFalse);
      expect(fixture['instructor_aboard'], isTrue);
    });

    test('stores no derived quantities', () {
      final fixture = loadFixture('flights', 'faa_easa_divergence');

      // CLAUDE.md rule 1: raw facts only. These are projection outputs.
      const forbidden = <String>[
        'pic_time',
        'dual_time',
        'night_time',
        'cross_country_time',
        'total_time',
      ];
      for (final key in forbidden) {
        expect(fixture.containsKey(key), isFalse, reason: '$key is derived');
      }
    });

    test('throws a clear error for a missing fixture', () {
      expect(
        () => loadFixture('flights', 'does_not_exist'),
        throwsA(
          isA<FixtureNotFoundException>().having(
            (e) => e.toString(),
            'message',
            allOf(contains('flights'), contains('does_not_exist')),
          ),
        ),
      );
    });
  });
}
