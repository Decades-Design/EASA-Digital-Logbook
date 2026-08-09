import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import 'fixture_loader.dart';

/// Key names that name a *derived* quantity rather than a raw fact.
///
/// Matched by shape, not by literal name, so the guard covers keys nobody has
/// thought of yet. `pic_time`, `easa_pic_hours` and `picus_time` all fall out
/// of the two duration suffixes; `is_cross_country` is named explicitly
/// because CLAUDE.md rule 2 calls out the precomputed boolean by name — a
/// cross-country determination depends on a threshold that differs per
/// authority, so storing the answer destroys the question.
final List<RegExp> _derivedKeyPatterns = <RegExp>[
  RegExp(r'_time$'),
  RegExp(r'_hours$'),
  RegExp(r'^is_cross_country$'),
];

/// Every key in [node], including keys of nested maps, so a derived quantity
/// cannot hide one level down under a `derived:` heading.
List<String> _allKeys(Object? node) {
  final keys = <String>[];
  if (node is YamlMap) {
    for (final Object? key in node.keys) {
      keys.add('$key');
      keys.addAll(_allKeys(node[key]));
    }
  } else if (node is YamlList) {
    for (final Object? item in node) {
      keys.addAll(_allKeys(item));
    }
  }
  return keys;
}

/// Every flight fixture on disk, so a fixture added tomorrow is guarded too.
List<File> _flightFixtures() =>
    Directory('test/fixtures/flights')
        .listSync()
        .whereType<File>()
        .where((file) => file.path.endsWith('.yaml'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path));

void main() {
  group('loadFixture', () {
    test('loads the FAA/EASA divergence flight', () {
      final fixture = loadFixture('flights', 'faa_easa_divergence');

      expect(fixture, isA<YamlMap>());
      final capacity = fixture['capacity'] as YamlMap;
      expect(capacity['sole_manipulator'], isTrue);
      expect(capacity['command_authority'], isFalse);
      expect(capacity['instructor'], isNotNull);
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

    // #101: package:yaml's own parse failure carries a line/column but never
    // a file path, since loadYaml only ever sees a raw string — the fixture
    // path must be attached by this loader, not left for the caller to
    // rediscover by trial and error.
    test('throws a clear, actionable error naming the file for malformed '
        'YAML syntax', () {
      expect(
        () => loadFixture('malformed', 'invalid_syntax'),
        throwsA(
          isA<FixtureParseException>().having(
            (e) => e.toString(),
            'message',
            contains('test/fixtures/malformed/invalid_syntax.yaml'),
          ),
        ),
      );
    });

    test('rejects a fixture that parses to something other than a map', () {
      expect(
        () => loadFixture('malformed', 'not_a_map'),
        throwsA(
          isA<FixtureParseException>().having(
            (e) => e.toString(),
            'message',
            allOf(
              contains('test/fixtures/malformed/not_a_map.yaml'),
              contains('YamlList'),
            ),
          ),
        ),
      );
    });
  });

  // CLAUDE.md rule 1 and ADR-0001: a fixture stores raw facts only. A stored
  // derived quantity is unrepairable — a projection cannot be re-derived from
  // a number that overwrote the facts it came from — so this sweeps every
  // flight fixture, not just the one that happens to exist today.
  group('rule 1: fixtures store no derived quantities', () {
    final fixtures = _flightFixtures();

    test('there is at least one flight fixture to check', () {
      // Without this, an empty or renamed directory would make the sweep below
      // vacuously green.
      expect(fixtures, isNotEmpty);
    });

    test('the patterns catch the derived names we already know of', () {
      const knownDerived = <String>[
        'pic_time',
        'dual_time',
        'night_time',
        'cross_country_time',
        'total_time',
        'picus_time',
        'spic_time',
        'easa_pic_hours',
        'is_cross_country',
      ];

      for (final key in knownDerived) {
        expect(
          _derivedKeyPatterns.any((pattern) => pattern.hasMatch(key)),
          isTrue,
          reason: '$key is a projection output and must be rejected',
        );
      }
    });

    test('the patterns do not catch raw facts', () {
      // Raw facts that are themselves durations or counts are fine — see
      // test/fixtures/README.md. The guard must not push a fixture author into
      // dropping a fact to satisfy it.
      const rawFacts = <String>[
        'actual_instrument_minutes',
        'simulated_instrument_minutes',
        'off_blocks',
        'route',
        'takeoffs',
        'landings',
        'command_authority',
      ];

      for (final key in rawFacts) {
        expect(
          _derivedKeyPatterns.any((pattern) => pattern.hasMatch(key)),
          isFalse,
          reason: '$key is a raw fact and must be allowed',
        );
      }
    });

    for (final file in fixtures) {
      final name = file.uri.pathSegments.last;

      test('$name stores no derived quantity', () {
        final Object? parsed = loadYaml(file.readAsStringSync());
        expect(parsed, isA<YamlMap>(), reason: '$name must parse as a map');

        for (final keyName in _allKeys(parsed)) {
          for (final pattern in _derivedKeyPatterns) {
            expect(
              pattern.hasMatch(keyName),
              isFalse,
              reason:
                  '$name stores "$keyName", which matches the derived-quantity '
                  'pattern ${pattern.pattern}. Raw facts only — see CLAUDE.md '
                  'rule 1 and ADR-0001.',
            );
          }
        }
      });
    }
  });
}
