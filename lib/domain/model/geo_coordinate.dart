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

/// Great-circle distance between [a] and [b] along Earth's surface, in
/// nautical miles — the unit `docs/jurisdiction-matrix.md` cites for the
/// FAA's 50 nm cross-country threshold, so callers never need to convert.
///
/// Haversine, not Vincenty: FAA and EASA cross-country thresholds don't need
/// ellipsoid precision, and Vincenty can fail to converge for near-antipodal
/// points — a worse failure mode for a logbook than a fraction of a percent
/// of spherical-Earth error.
double greatCircleDistanceNm(GeoCoordinate a, GeoCoordinate b) {
  final lat1 = a.latitude * _degreesToRadians;
  final lat2 = b.latitude * _degreesToRadians;
  final dLat = (b.latitude - a.latitude) * _degreesToRadians;
  final dLon = (b.longitude - a.longitude) * _degreesToRadians;

  final sinHalfDLat = sin(dLat / 2);
  final sinHalfDLon = sin(dLon / 2);
  final h =
      sinHalfDLat * sinHalfDLat +
      cos(lat1) * cos(lat2) * sinHalfDLon * sinHalfDLon;
  final c = 2 * atan2(sqrt(h), sqrt(1 - h));
  return _earthRadiusNm * c;
}
