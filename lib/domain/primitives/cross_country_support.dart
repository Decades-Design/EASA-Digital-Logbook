import '../model/aerodrome_directory.dart';
import '../model/flight.dart';
import '../model/geo_coordinate.dart';

/// Shared by the EASA (#23) and FAA (#24) cross-country primitives.
///
/// [Flight.route] is "departure, any intermediate stops, and destination, in
/// order" (`flight.dart`) — every entry after the first is treated as a
/// place the aircraft landed, since that is the only reading consistent
/// with `Flight` recording no per-waypoint landing type and
/// `CircuitCounts` recording only flight-level touch-and-go/full-stop
/// totals, not which waypoint each landing was at. A route entry that was
/// only overflown, never landed at, should not appear in [Flight.route] at
/// all — see `docs/entry-form.md`.

/// Whether [flight] included a landing at any point other than its
/// departure aerodrome — the fact both `FCL.010` and `§61.1(b)(3)(i)`
/// require for a flight to be cross-country at all, independent of
/// distance. Pure string comparison (case-insensitive) against
/// [Flight.route]; needs no [AerodromeDirectory] and cannot be defeated by
/// an unresolvable waypoint.
bool landedAwayFromDeparture(Flight flight) {
  if (flight.route.length < 2) {
    return false;
  }
  final departure = flight.route.first.toUpperCase();
  return flight.route.skip(1).any((leg) => leg.toUpperCase() != departure);
}

/// The distinct waypoint identifiers in [flight]'s route other than the
/// departure, case-insensitively de-duplicated. Used for EASA's qualifying
/// cross-country flight, which counts *aerodromes visited*, not landings —
/// a there-and-back-and-back-again route only counts each other aerodrome
/// once.
Set<String> aerodromesVisitedOtherThanDeparture(Flight flight) {
  if (flight.route.isEmpty) {
    return const {};
  }
  final departure = flight.route.first.toUpperCase();
  return flight.route
      .skip(1)
      .map((leg) => leg.toUpperCase())
      .where((leg) => leg != departure)
      .toSet();
}

/// Total distance flown along [flight]'s route, in nautical miles — the sum
/// of each consecutive leg, not a single point-to-point figure. This is
/// what EASA's qualifying cross-country flight (FCL.210.A) measures: "at
/// least 270 km (150 NM)" is the length of the route flown, not how far the
/// furthest point was from departure.
///
/// `null` if fewer than two consecutive waypoints resolve to a position —
/// there is then no leg to measure at all, not merely an imprecise one.
double? totalRouteDistanceNm(Flight flight, AerodromeDirectory aerodromes) {
  final positions = _resolvedPositionsInOrder(flight, aerodromes);
  if (positions.length < 2) {
    return null;
  }

  var total = 0.0;
  for (var i = 1; i < positions.length; i++) {
    total += greatCircleDistanceNm(positions[i - 1], positions[i]);
  }
  return total;
}

/// The greatest straight-line distance, in nautical miles, from [flight]'s
/// departure to any other resolvable waypoint it landed at — the metric
/// every FAA `§61.1(b)(3)(ii)`-`(vii)` credit test uses ("more than *N*
/// nautical miles from the point of departure"). Deliberately not the
/// destination's distance and not a sum of legs: a flight that ranges 60 nm
/// out and returns to land back at departure went further than 50 nm from
/// departure even though the final leg's distance is zero, and a multi-leg
/// flight where every individual leg stays under a threshold can still put
/// a landing point beyond it overall.
///
/// `null` if the departure does not resolve, or no other waypoint does —
/// there is then nothing to measure a distance to.
double? furthestLandingDistanceFromDepartureNm(
  Flight flight,
  AerodromeDirectory aerodromes,
) {
  final departureIdentifier = flight.route.isEmpty ? null : flight.route.first;
  final departure = departureIdentifier == null
      ? null
      : aerodromes.byIcao(departureIdentifier)?.position;
  if (departure == null) {
    return null;
  }

  double? furthest;
  for (final identifier in flight.route.skip(1)) {
    final position = aerodromes.byIcao(identifier)?.position;
    if (position == null) {
      continue;
    }
    final distance = greatCircleDistanceNm(departure, position);
    if (furthest == null || distance > furthest) {
      furthest = distance;
    }
  }
  return furthest;
}

/// [flight]'s route, resolved to positions in order, skipping any waypoint
/// that doesn't resolve — used by [totalRouteDistanceNm], where a leg can
/// only be measured between two resolved points.
List<GeoCoordinate> _resolvedPositionsInOrder(
  Flight flight,
  AerodromeDirectory aerodromes,
) {
  final positions = <GeoCoordinate>[];
  for (final identifier in flight.route) {
    final position = aerodromes.byIcao(identifier)?.position;
    if (position != null) {
      positions.add(position);
    }
  }
  return positions;
}
