import 'package:csv/csv.dart';

import 'aerodrome.dart';
import 'geo_coordinate.dart';

/// Column names `parseOurAirportsCsv` reads. Looked up by name rather than
/// fixed position, so a harmless reorder or an added column in a future
/// OurAirports download doesn't break parsing — only a renamed or removed
/// column does, and that raises [FormatException] naming it.
const List<String> _requiredColumns = [
  'icao_code',
  'iata_code',
  'name',
  'latitude_deg',
  'longitude_deg',
  'elevation_ft',
  'iso_country',
];

/// Parses OurAirports' `airports.csv` format (see
/// `assets/aerodromes/README.md` for provenance and licence) into
/// [Aerodrome]s.
///
/// Skips a row if both [Aerodrome.icaoCode] and [Aerodrome.iataCode] would
/// be blank — those are the only public identifiers the app looks
/// aerodromes up by, and OurAirports carries thousands of closed strips and
/// heliports identified only by an internal `gps_code`/`local_code`. Also
/// skips a row with an unparseable latitude or longitude, which happens for
/// a handful of very old entries in the dataset; a bundled reference file is
/// not user input; the design that matters here is not asking one bad row
/// out of ~85,000 to fail the whole load.
List<Aerodrome> parseOurAirportsCsv(String csvContent) {
  final rows = Csv().decode(csvContent);
  if (rows.isEmpty) {
    return const <Aerodrome>[];
  }

  final header = rows.first.map((cell) => cell.toString()).toList();
  final columnIndex = <String, int>{};
  for (final name in _requiredColumns) {
    final index = header.indexOf(name);
    if (index == -1) {
      throw FormatException(
        'OurAirports CSV is missing expected column "$name". The upstream '
        'column layout may have changed.',
      );
    }
    columnIndex[name] = index;
  }

  final aerodromes = <Aerodrome>[];
  for (final row in rows.skip(1)) {
    final icao = _cell(row, columnIndex['icao_code']!);
    final iata = _cell(row, columnIndex['iata_code']!);
    if (icao == null && iata == null) {
      continue;
    }

    final lat = double.tryParse(row[columnIndex['latitude_deg']!].toString());
    final lon = double.tryParse(row[columnIndex['longitude_deg']!].toString());
    if (lat == null || lon == null) {
      continue;
    }

    aerodromes.add(
      Aerodrome(
        icaoCode: icao,
        iataCode: iata,
        name: row[columnIndex['name']!].toString(),
        position: GeoCoordinate(latitude: lat, longitude: lon),
        elevationFt: int.tryParse(row[columnIndex['elevation_ft']!].toString()),
        isoCountry: _cell(row, columnIndex['iso_country']!),
      ),
    );
  }
  return aerodromes;
}

/// Reads `row[index]` as a trimmed string, or `null` if blank.
String? _cell(List<dynamic> row, int index) {
  final value = row[index].toString().trim();
  return value.isEmpty ? null : value;
}

/// O(1) lookup of a bundled or user-supplied [Aerodrome] set by ICAO code.
///
/// Keyed on [Aerodrome.icaoCode] only — #14 treats IATA as a secondary
/// identifier, not the primary lookup key, and most GA aerodromes have no
/// IATA code at all. An aerodrome with no ICAO code isn't indexed; [byIcao]
/// returning `null` for an unindexed or unknown code — never throwing — is
/// the "gracefully handle absence" behaviour #14 asks for.
class AerodromeDirectory {
  /// If [aerodromes] contains two entries with the same ICAO code
  /// (case-insensitively), the later one wins — the source dataset is
  /// curated data, not a place this is expected to happen, so no error is
  /// raised for it.
  AerodromeDirectory(Iterable<Aerodrome> aerodromes)
    : _byIcao = {
        for (final aerodrome in aerodromes)
          if (aerodrome.icaoCode != null)
            aerodrome.icaoCode!.toUpperCase(): aerodrome,
      };

  factory AerodromeDirectory.fromOurAirportsCsv(String csvContent) =>
      AerodromeDirectory(parseOurAirportsCsv(csvContent));

  final Map<String, Aerodrome> _byIcao;

  /// Looks up an aerodrome by ICAO code, case-insensitively. `null` if
  /// [code] isn't in this directory — never throws.
  Aerodrome? byIcao(String code) => _byIcao[code.toUpperCase()];

  /// Number of aerodromes indexed (i.e. with a non-null ICAO code).
  int get length => _byIcao.length;
}
