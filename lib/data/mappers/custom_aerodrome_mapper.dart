import '../../domain/model/aerodrome.dart' as domain;
import '../../domain/model/geo_coordinate.dart';
import '../database.dart';

CustomAerodromeRow customAerodromeToRow(
  domain.Aerodrome aerodrome, {
  required String id,
}) {
  return CustomAerodromeRow(
    id: id,
    icaoCode: aerodrome.icaoCode,
    iataCode: aerodrome.iataCode,
    name: aerodrome.name,
    latitude: aerodrome.position.latitude,
    longitude: aerodrome.position.longitude,
    elevationFt: aerodrome.elevationFt,
    isoCountry: aerodrome.isoCountry,
  );
}

domain.Aerodrome customAerodromeFromRow(CustomAerodromeRow row) {
  return domain.Aerodrome(
    icaoCode: row.icaoCode,
    iataCode: row.iataCode,
    name: row.name,
    position: GeoCoordinate(latitude: row.latitude, longitude: row.longitude),
    elevationFt: row.elevationFt,
    isoCountry: row.isoCountry,
  );
}
