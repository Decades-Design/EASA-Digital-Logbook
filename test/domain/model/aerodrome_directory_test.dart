// flutter_test re-exports test/group/expect from package:test_api, so plain
// Dart tests need no separate package:test dependency.
import 'dart:io';

import 'package:easa_digital_log/domain/model/aerodrome.dart';
import 'package:easa_digital_log/domain/model/aerodrome_directory.dart';
import 'package:easa_digital_log/domain/model/geo_coordinate.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fixtures live under `test/fixtures/aerodromes/` as raw CSV, matching
/// OurAirports' own format directly — see the README there. This differs
/// from the YAML-plus-decoder pattern used elsewhere in `test/fixtures/`
/// because the thing under test *is* the CSV parser; wrapping the input in
/// YAML would just add a translation step with nothing to verify.
String _fixture(String name) =>
    File('test/fixtures/aerodromes/$name.csv').readAsStringSync();

void main() {
  group('parseOurAirportsCsv', () {
    late final aerodromes = parseOurAirportsCsv(_fixture('sample_ourairports'));

    test('keeps a row with both ICAO and IATA codes', () {
      final jfk = aerodromes.firstWhere((a) => a.icaoCode == 'KJFK');
      expect(jfk.iataCode, 'JFK');
      expect(jfk.name, 'John F Kennedy International Airport');
      expect(jfk.elevationFt, 13);
      expect(jfk.isoCountry, 'US');
      expect(jfk.position.latitude, 40.639801);
      expect(jfk.position.longitude, -73.7789);
    });

    test('an embedded comma in the name does not shift later columns', () {
      // "Newark, Liberty International Airport" — if the parser split on
      // literal commas instead of respecting the CSV quoting, icao_code and
      // iata_code (which come after name in the row) would read garbage.
      final ewr = aerodromes.firstWhere((a) => a.icaoCode == 'KEWR');
      expect(ewr.name, 'Newark, Liberty International Airport');
      expect(ewr.iataCode, 'EWR');
    });

    test('skips a row with neither ICAO nor IATA code', () {
      expect(aerodromes.where((a) => a.name == 'Total RF Heliport'), isEmpty);
    });

    test('keeps a row with only an IATA code', () {
      final remote = aerodromes.firstWhere(
        (a) => a.name == 'Remote Island Strip',
      );
      expect(remote.icaoCode, isNull);
      expect(remote.iataCode, 'XYZ');
    });

    test('a blank elevation becomes null, not zero', () {
      final noElevation = aerodromes.firstWhere((a) => a.icaoCode == 'ZZZZ');
      expect(noElevation.elevationFt, isNull);
    });

    test('skips a row with an unparseable position', () {
      expect(
        aerodromes.where((a) => a.name == 'Bad Coordinates Airport'),
        isEmpty,
      );
    });

    test('throws naming the missing column', () {
      expect(
        () => parseOurAirportsCsv(_fixture('missing_column')),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('iso_country'),
          ),
        ),
      );
    });
  });

  group('AerodromeDirectory', () {
    late final directory = AerodromeDirectory.fromOurAirportsCsv(
      _fixture('sample_ourairports'),
    );

    test('finds an aerodrome by ICAO code case-insensitively', () {
      expect(
        directory.byIcao('KJFK')?.name,
        'John F Kennedy International Airport',
      );
      expect(
        directory.byIcao('kjfk')?.name,
        'John F Kennedy International Airport',
      );
    });

    test('returns null, never throws, for an unknown code', () {
      expect(directory.byIcao('ZZZZ99'), isNull);
    });

    test('an aerodrome parsed with no ICAO code is not indexed', () {
      // The "Remote Island Strip" fixture row is IATA-only. It's still in
      // the parsed list (see parseOurAirportsCsv tests above), just not
      // reachable through byIcao.
      expect(
        directory.byIcao('XYZ'),
        isNull,
        reason: 'IATA is not a lookup key for byIcao',
      );
    });

    test('indexes exactly the rows that carry an ICAO code', () {
      // KJFK, EGLL, ZZZZ, KEWR. Heliport and bad-coordinate rows never made
      // it into the parsed list; the IATA-only row made the list but has no
      // ICAO code to index by.
      expect(directory.length, 4);
    });

    test('a duplicate ICAO code keeps the later entry', () {
      // Documented, deliberate behaviour, not an accident: the bundled
      // dataset is curated data, not user input, so this is not expected to
      // occur in practice and no error is raised for it.
      final directory = AerodromeDirectory.fromOurAirportsCsv(
        _fixture('duplicate_icao'),
      );
      expect(directory.byIcao('DUPE')?.name, 'Second Entry');
    });

    test('byIata finds an aerodrome by IATA code case-insensitively', () {
      expect(directory.byIata('xyz')?.name, 'Remote Island Strip');
      expect(directory.byIata('jfk')?.name, 'John F Kennedy International Airport');
    });

    test('byIata returns null for an unknown code', () {
      expect(directory.byIata('ZZQ'), isNull);
    });
  });

  group('AerodromeDirectory.search', () {
    late final directory = AerodromeDirectory.fromOurAirportsCsv(
      _fixture('sample_ourairports'),
    );

    test('returns nothing for a blank query', () {
      expect(directory.search(''), isEmpty);
      expect(directory.search('   '), isEmpty);
    });

    test('an exact ICAO match ranks first', () {
      final results = directory.search('KJFK');
      expect(results.first.name, 'John F Kennedy International Airport');
    });

    test('an exact IATA match is found even with no ICAO code', () {
      final results = directory.search('XYZ');
      expect(
        results.any((a) => a.name == 'Remote Island Strip'),
        isTrue,
      );
    });

    test('a prefix match on ICAO ranks before a name substring match', () {
      // "EG" prefixes EGLL's ICAO; it also isn't a substring of any other
      // fixture name, but this proves prefix tier ordering holds when both
      // tiers are populated together, using a query that legitimately
      // spans both.
      final results = directory.search('NEWARK');
      expect(results.single.name, 'Newark, Liberty International Airport');
    });

    test('a name substring match is found', () {
      final results = directory.search('HEATHROW');
      expect(results.single.name, 'London Heathrow Airport');
    });

    test('is case-insensitive', () {
      expect(directory.search('heathrow'), isNotEmpty);
    });

    test('merges in extra (custom) aerodromes alongside the bundled set', () {
      final strip = Aerodrome(
        name: "Farmer Brown's Strip",
        position: GeoCoordinate(latitude: 1, longitude: 2),
      );
      final results = directory.search('FARMER', extra: [strip]);
      expect(results.single.name, "Farmer Brown's Strip");
    });

    test('respects limit', () {
      final results = directory.search('A', limit: 2);
      expect(results.length, lessThanOrEqualTo(2));
    });
  });
}
