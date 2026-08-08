// flutter_test re-exports test/group/expect from package:test_api, so plain
// Dart tests need no separate package:test dependency.
import 'package:easa_digital_log/domain/model/aerodrome.dart';
import 'package:easa_digital_log/domain/model/geo_coordinate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Aerodrome', () {
    test('two aerodromes with the same fields are equal', () {
      final a = Aerodrome(
        icaoCode: 'EGLL',
        iataCode: 'LHR',
        name: 'London Heathrow Airport',
        position: GeoCoordinate(latitude: 51.4706, longitude: -0.461941),
        elevationFt: 83,
        isoCountry: 'GB',
      );
      final b = Aerodrome(
        icaoCode: 'EGLL',
        iataCode: 'LHR',
        name: 'London Heathrow Airport',
        position: GeoCoordinate(latitude: 51.4706, longitude: -0.461941),
        elevationFt: 83,
        isoCountry: 'GB',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('a different field breaks equality', () {
      final heathrow = Aerodrome(
        icaoCode: 'EGLL',
        iataCode: 'LHR',
        name: 'London Heathrow Airport',
        position: GeoCoordinate(latitude: 51.4706, longitude: -0.461941),
        elevationFt: 83,
        isoCountry: 'GB',
      );
      expect(heathrow, isNot(heathrow.copyWith(icaoCode: 'EGKK')));
    });

    test('a private strip can be recorded with no ICAO or IATA code', () {
      // #14 is explicit: this is not an edge case. Plenty of GA flying
      // happens from places no public dataset knows about.
      final strip = Aerodrome(
        name: "Someone's Farm Strip",
        position: GeoCoordinate(latitude: 52.1, longitude: -1.3),
      );
      expect(strip.icaoCode, isNull);
      expect(strip.iataCode, isNull);
      expect(strip.elevationFt, isNull);
      expect(strip.isoCountry, isNull);
    });
  });
}
