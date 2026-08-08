// flutter_test re-exports test/group/expect from package:test_api, so plain
// Dart tests need no separate package:test dependency.
import 'package:easa_digital_log/domain/model/geo_coordinate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GeoCoordinate validation', () {
    test('accepts the boundary values', () {
      expect(
        () => GeoCoordinate(latitude: 90, longitude: 180),
        returnsNormally,
      );
      expect(
        () => GeoCoordinate(latitude: -90, longitude: -180),
        returnsNormally,
      );
    });

    test('rejects latitude outside -90..90', () {
      expect(
        () => GeoCoordinate(latitude: 90.0001, longitude: 0),
        throwsArgumentError,
      );
      expect(
        () => GeoCoordinate(latitude: -90.0001, longitude: 0),
        throwsArgumentError,
      );
    });

    test('rejects longitude outside -180..180', () {
      expect(
        () => GeoCoordinate(latitude: 0, longitude: 180.0001),
        throwsArgumentError,
      );
      expect(
        () => GeoCoordinate(latitude: 0, longitude: -180.0001),
        throwsArgumentError,
      );
    });
  });

  group('GeoCoordinate equality', () {
    test('two coordinates with the same values are equal', () {
      final a = GeoCoordinate(latitude: 51.4706, longitude: -0.461941);
      final b = GeoCoordinate(latitude: 51.4706, longitude: -0.461941);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('a different latitude or longitude breaks equality', () {
      final base = GeoCoordinate(latitude: 51.4706, longitude: -0.461941);
      expect(base, isNot(GeoCoordinate(latitude: 51.47, longitude: -0.461941)));
      expect(base, isNot(GeoCoordinate(latitude: 51.4706, longitude: 0)));
    });
  });

  group('greatCircleDistanceNm', () {
    test('the same point is zero nm away from itself', () {
      final point = GeoCoordinate(latitude: 40.6413, longitude: -73.7781);
      expect(greatCircleDistanceNm(point, point), 0);
    });

    test('distance is symmetric', () {
      final jfk = GeoCoordinate(latitude: 40.639801, longitude: -73.7789);
      final lhr = GeoCoordinate(latitude: 51.4706, longitude: -0.461941);
      expect(
        greatCircleDistanceNm(jfk, lhr),
        closeTo(greatCircleDistanceNm(lhr, jfk), 1e-9),
      );
    });

    test('a quarter of the equator is R * pi/2 nm exactly', () {
      // Two equatorial points 90 degrees of longitude apart reduce the
      // haversine formula to R * dLon with no approximation involved, so
      // this is an exact check on the formula, not a real-world estimate.
      final a = GeoCoordinate(latitude: 0, longitude: 0);
      final b = GeoCoordinate(latitude: 0, longitude: 90);
      expect(greatCircleDistanceNm(a, b), closeTo(5403.64, 0.5));
    });

    test('antipodal points are half of Earth\'s circumference apart', () {
      final a = GeoCoordinate(latitude: 10, longitude: 20);
      final b = GeoCoordinate(latitude: -10, longitude: -160);
      expect(greatCircleDistanceNm(a, b), closeTo(10807.28, 1.0));
    });

    test('JFK to LHR matches the published great-circle distance', () {
      // Published distance is commonly cited as ~2991 nm (5541 km). A unit
      // or formula bug (degrees instead of radians, statute miles instead
      // of nm, swapped lat/lon) would miss by far more than this tolerance.
      final jfk = GeoCoordinate(latitude: 40.639801, longitude: -73.7789);
      final lhr = GeoCoordinate(latitude: 51.4706, longitude: -0.461941);
      expect(greatCircleDistanceNm(jfk, lhr), closeTo(2991, 20));
    });
  });
}
