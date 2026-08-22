import '../model/aerodrome.dart';
import '../model/aerodrome_directory.dart';
import '../model/calendar_date.dart';
import '../model/geo_coordinate.dart';
import '../repository/flight_read_repository.dart';

/// Pure aggregation over a flight set for the Aerodromes screen — mirrors
/// `totals_summary.dart`'s shape (no Flutter import, unit-tested,
/// deterministic). The summary-card counts (aerodromes visited, countries)
/// reuse `totals_summary.aerodromesVisited` rather than duplicating that
/// logic here.
///
/// **Visits, not landings.** [Flight.landings] is a per-flight total, not
/// broken down by which leg of a multi-stop route it happened on, so there
/// is no raw fact saying how many landings occurred at any one aerodrome on
/// a route like `[home, A, B, home]`. [rankAerodromesByVisits] counts
/// flights that touched each aerodrome instead — always correct, and it's
/// what the screen's own "most visited" framing actually means.

/// One aerodrome's visit count, with its resolved [Aerodrome] where the
/// directory has one. [aerodrome] is null for a code the directory doesn't
/// know — a private strip or an unlicensed field (#14) — the screen falls
/// back to showing the bare code.
class AerodromeVisit {
  const AerodromeVisit({
    required this.icao,
    required this.aerodrome,
    required this.visitCount,
  });

  final String icao;
  final Aerodrome? aerodrome;
  final int visitCount;
}

/// Ranks every aerodrome appearing in [flights]' routes by how many flights
/// touched it, most-visited first, then by ICAO code for a stable tie order.
/// A flight visiting the same aerodrome twice in one route (e.g. `[A, A]`,
/// an out-and-back with no intermediate stop) counts once, not twice — this
/// counts flights per aerodrome, not route-leg occurrences.
List<AerodromeVisit> rankAerodromesByVisits(
  List<FlightRecord> flights,
  AerodromeDirectory directory,
) {
  final visitCounts = <String, int>{};
  for (final record in flights) {
    for (final icao in record.flight.route.toSet()) {
      visitCounts[icao] = (visitCounts[icao] ?? 0) + 1;
    }
  }

  final visits = [
    for (final entry in visitCounts.entries)
      AerodromeVisit(
        icao: entry.key,
        aerodrome: directory.byIcao(entry.key),
        visitCount: entry.value,
      ),
  ];
  visits.sort((a, b) {
    final byCount = b.visitCount.compareTo(a.visitCount);
    return byCount != 0 ? byCount : a.icao.compareTo(b.icao);
  });
  return visits;
}

/// The furthest aerodrome visited from [homeBaseIcao], with its great-circle
/// distance in nautical miles. Returns `null` if [homeBaseIcao] doesn't
/// resolve in [directory], or if no other aerodrome has been visited — never
/// a fabricated distance for a home base nobody has actually set.
({String icao, double nm})? furthestAerodrome(
  List<FlightRecord> flights,
  AerodromeDirectory directory,
  String homeBaseIcao,
) {
  final home = directory.byIcao(homeBaseIcao);
  if (home == null) {
    return null;
  }

  final icaoCodes = <String>{
    for (final record in flights) ...record.flight.route,
  }..remove(homeBaseIcao);

  String? furthestIcao;
  var furthestNm = 0.0;
  for (final icao in icaoCodes) {
    final aerodrome = directory.byIcao(icao);
    if (aerodrome == null) {
      continue;
    }
    final nm = greatCircleDistanceNm(home.position, aerodrome.position);
    if (furthestIcao == null || nm > furthestNm) {
      furthestIcao = icao;
      furthestNm = nm;
    }
  }

  return furthestIcao == null ? null : (icao: furthestIcao, nm: furthestNm);
}

/// Count of aerodromes whose earliest visiting flight falls in [asOf]'s
/// calendar year — an aerodrome flown to for the first time this year.
int newAerodromesThisYear(List<FlightRecord> flights, CalendarDate asOf) {
  final firstVisitYear = <String, int>{};
  for (final record in flights) {
    final year = CalendarDate.fromUtcInstant(record.flight.offBlocks).year;
    for (final icao in record.flight.route.toSet()) {
      final existing = firstVisitYear[icao];
      if (existing == null || year < existing) {
        firstVisitYear[icao] = year;
      }
    }
  }
  return firstVisitYear.values.where((year) => year == asOf.year).length;
}
