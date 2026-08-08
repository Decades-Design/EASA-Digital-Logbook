import 'dart:math';

/// A point on Earth's surface, WGS84 latitude/longitude in degrees.
///
/// Validated at construction so a transposed lat/lon or a stray sign typo
/// fails where it was entered instead of silently corrupting every distance
/// calculation that later reads it.
class GeoCoordinate {
  const GeoCoordinate._(this.latitude, this.longitude);

  /// Throws [ArgumentError] if [latitude] is outside -90..90 or [longitude]
  /// is outside -180..180.
  factory GeoCoordinate({required double latitude, required double longitude}) {
    if (latitude < -90 || latitude > 90) {
      throw ArgumentError.value(
        latitude,
        'latitude',
        'must be between -90 and 90 degrees',
      );
    }
    if (longitude < -180 || longitude > 180) {
      throw ArgumentError.value(
        longitude,
        'longitude',
        'must be between -180 and 180 degrees',
      );
    }
    return GeoCoordinate._(latitude, longitude);
  }

  final double latitude;
  final double longitude;

  @override
  bool operator ==(Object other) =>
      other is GeoCoordinate &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(latitude, longitude);

  @override
  String toString() => 'GeoCoordinate($latitude, $longitude)';
}

/// Mean Earth radius in nautical miles: 6371.0088 km (IUGG mean radius) /
/// 1.852 km per nm.
const double _earthRadiusNm = 3440.065;

const double _degreesToRadians = pi / 180;

/// The angular distance between [a] and [b] along Earth's surface, in
/// radians. Haversine, not Vincenty — see [greatCircleDistanceNm] — shared
/// by that function and by [interpolateGreatCircle], so the two never derive
/// slightly different notions of "the great-circle path between two points".
double _centralAngleRadians(GeoCoordinate a, GeoCoordinate b) {
  final lat1 = a.latitude * _degreesToRadians;
  final lat2 = b.latitude * _degreesToRadians;
  final dLat = (b.latitude - a.latitude) * _degreesToRadians;
  final dLon = (b.longitude - a.longitude) * _degreesToRadians;

  final sinHalfDLat = sin(dLat / 2);
  final sinHalfDLon = sin(dLon / 2);
  final h =
      sinHalfDLat * sinHalfDLat +
      cos(lat1) * cos(lat2) * sinHalfDLon * sinHalfDLon;
  return 2 * atan2(sqrt(h), sqrt(1 - h));
}

/// Great-circle distance between [a] and [b] along Earth's surface, in
/// nautical miles — the unit `docs/jurisdiction-matrix.md` cites for the
/// FAA's 50 nm cross-country threshold, so callers never need to convert.
///
/// Haversine, not Vincenty: FAA and EASA cross-country thresholds don't need
/// ellipsoid precision, and Vincenty can fail to converge for near-antipodal
/// points — a worse failure mode for a logbook than a fraction of a percent
/// of spherical-Earth error.
double greatCircleDistanceNm(GeoCoordinate a, GeoCoordinate b) =>
    _earthRadiusNm * _centralAngleRadians(a, b);

/// The point [fraction] of the way from [a] to [b] along the great circle
/// connecting them. `fraction: 0` is [a], `fraction: 1` is [b].
///
/// Used by the EASA and FAA night-time primitives (#21, #22) to approximate
/// an aircraft's position during a flight as a straight line — in the
/// great-circle sense — between its first and last resolvable route
/// waypoints, walked in step with elapsed time. See
/// `docs/adr/0008-night-time-position-interpolation.md` for why endpoints
/// only, not every intermediate stop.
///
/// Standard spherical interpolation (Ed Williams, *Aviation Formulary*,
/// "Intermediate points"). If [a] and [b] are (near-)coincident, the
/// central angle is ~0 and the interpolation formula divides by ~0, so that
/// case returns [a] directly rather than propagating a `NaN` — correct
/// either way, since every point on a zero-length path is the same point.
GeoCoordinate interpolateGreatCircle(
  GeoCoordinate a,
  GeoCoordinate b,
  double fraction,
) {
  final angle = _centralAngleRadians(a, b);
  if (angle < 1e-12) {
    return a;
  }

  final lat1 = a.latitude * _degreesToRadians;
  final lon1 = a.longitude * _degreesToRadians;
  final lat2 = b.latitude * _degreesToRadians;
  final lon2 = b.longitude * _degreesToRadians;

  final scaleA = sin((1 - fraction) * angle) / sin(angle);
  final scaleB = sin(fraction * angle) / sin(angle);

  final x = scaleA * cos(lat1) * cos(lon1) + scaleB * cos(lat2) * cos(lon2);
  final y = scaleA * cos(lat1) * sin(lon1) + scaleB * cos(lat2) * sin(lon2);
  final z = scaleA * sin(lat1) + scaleB * sin(lat2);

  final resultLatRad = atan2(z, sqrt(x * x + y * y));
  final resultLonRad = atan2(y, x);

  return GeoCoordinate(
    latitude: resultLatRad / _degreesToRadians,
    longitude: resultLonRad / _degreesToRadians,
  );
}
