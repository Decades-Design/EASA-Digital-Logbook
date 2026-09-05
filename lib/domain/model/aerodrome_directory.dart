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
    : _all = List.unmodifiable(aerodromes),
      _byIcao = {
        for (final aerodrome in aerodromes)
          if (aerodrome.icaoCode != null)
            aerodrome.icaoCode!.toUpperCase(): aerodrome,
      },
      _byIata = {
        for (final aerodrome in aerodromes)
          if (aerodrome.iataCode != null)
            aerodrome.iataCode!.toUpperCase(): aerodrome,
      };

  factory AerodromeDirectory.fromOurAirportsCsv(String csvContent) =>
      AerodromeDirectory(parseOurAirportsCsv(csvContent));

  final List<Aerodrome> _all;
  final Map<String, Aerodrome> _byIcao;
  final Map<String, Aerodrome> _byIata;

  /// Looks up an aerodrome by ICAO code, case-insensitively. `null` if
  /// [code] isn't in this directory — never throws.
  Aerodrome? byIcao(String code) => _byIcao[code.toUpperCase()];

  /// Looks up an aerodrome by IATA code, case-insensitively. `null` if
  /// [code] isn't in this directory — never throws. #63: IATA is a
  /// secondary identifier (see the class dartdoc), but a pilot searching a
  /// picker by IATA still expects it to resolve, unlike [byIcao]'s
  /// exact-match contract which this mirrors rather than the fuzzier
  /// [search].
  Aerodrome? byIata(String code) => _byIata[code.toUpperCase()];

  /// Number of aerodromes indexed by ICAO code (i.e. with a non-null ICAO
  /// code). Unchanged by #63's [search] addition — this remains the
  /// pre-existing "how many are `byIcao`-reachable" count.
  int get length => _byIcao.length;

  /// #63: ranks every bundled aerodrome plus [extra] (typically the
  /// pilot's own user-defined strips, which live outside this
  /// dataset-only, immutably-loaded directory) against [query] — an exact
  /// ICAO or IATA match first, then an ICAO/IATA/name prefix match, then a
  /// name substring match, each tier alphabetical by name for a stable
  /// order. Scans linearly rather than maintaining a separate search
  /// index: ~85,000 cheap string comparisons is well under a frame budget,
  /// and a second index would have to be kept in sync with [extra] anyway
  /// since that list changes at runtime (a bundled index would not).
  ///
  /// Returns nothing for a blank [query] — this method is for narrowing a
  /// query the pilot has actually typed, not for browsing the whole
  /// dataset; the picker screen shows recent/frequent aerodromes instead
  /// when there is nothing to search on yet.
  List<Aerodrome> search(
    String query, {
    int limit = 20,
    Iterable<Aerodrome> extra = const [],
  }) {
    final q = query.trim().toUpperCase();
    if (q.isEmpty) {
      return const [];
    }

    final exact = <Aerodrome>[];
    final prefix = <Aerodrome>[];
    final substring = <Aerodrome>[];

    for (final aerodrome in _all.followedBy(extra)) {
      final icao = aerodrome.icaoCode?.toUpperCase();
      final iata = aerodrome.iataCode?.toUpperCase();
      final name = aerodrome.name.toUpperCase();

      if (icao == q || iata == q) {
        exact.add(aerodrome);
      } else if ((icao?.startsWith(q) ?? false) ||
          (iata?.startsWith(q) ?? false) ||
          name.startsWith(q)) {
        prefix.add(aerodrome);
      } else if (name.contains(q)) {
        substring.add(aerodrome);
      }
    }

    int byName(Aerodrome a, Aerodrome b) => a.name.compareTo(b.name);
    exact.sort(byName);
    prefix.sort(byName);
    substring.sort(byName);

    return exact.followedBy(prefix).followedBy(substring).take(limit).toList();
  }
}
