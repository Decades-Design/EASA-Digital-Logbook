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

  group('interpolateGreatCircle', () {
    test('fraction 0 is the start point, fraction 1 is the end point', () {
      final a = GeoCoordinate(latitude: 40.639801, longitude: -73.7789);
      final b = GeoCoordinate(latitude: 51.4706, longitude: -0.461941);

      // closeTo, not exact equality: fraction 0/1 round-trips through
      // radians and back, which is not bit-exact even though the formula
      // is mathematically the identity at those endpoints.
      expect(
        interpolateGreatCircle(a, b, 0).latitude,
        closeTo(a.latitude, 1e-9),
      );
      expect(
        interpolateGreatCircle(a, b, 0).longitude,
        closeTo(a.longitude, 1e-9),
      );
      expect(
        interpolateGreatCircle(a, b, 1).latitude,
        closeTo(b.latitude, 1e-9),
      );
      expect(
        interpolateGreatCircle(a, b, 1).longitude,
        closeTo(b.longitude, 1e-9),
      );
    });

    test('the midpoint of a 90-degree equatorial arc is exactly halfway', () {
      // Same pair used for the exact quarter-of-the-equator distance
      // check above — the midpoint of an equatorial arc stays on the
      // equator at the mean longitude, with no spherical correction
      // needed, so this is an exact check rather than an estimate.
      final a = GeoCoordinate(latitude: 0, longitude: 0);
      final b = GeoCoordinate(latitude: 0, longitude: 90);
      final midpoint = interpolateGreatCircle(a, b, 0.5);

      expect(midpoint.latitude, closeTo(0, 1e-9));
      expect(midpoint.longitude, closeTo(45, 1e-9));
    });

    test('a coincident start and end point never divides by zero', () {
      final point = GeoCoordinate(latitude: 51.4706, longitude: -0.461941);
      expect(interpolateGreatCircle(point, point, 0.5), point);
    });

    test('walking the whole path splits the total distance proportionally', () {
      final jfk = GeoCoordinate(latitude: 40.639801, longitude: -73.7789);
      final lhr = GeoCoordinate(latitude: 51.4706, longitude: -0.461941);
      final total = greatCircleDistanceNm(jfk, lhr);
      final quarter = interpolateGreatCircle(jfk, lhr, 0.25);

      expect(greatCircleDistanceNm(jfk, quarter), closeTo(total * 0.25, 1));
      expect(greatCircleDistanceNm(quarter, lhr), closeTo(total * 0.75, 1));
    });
  });
}
