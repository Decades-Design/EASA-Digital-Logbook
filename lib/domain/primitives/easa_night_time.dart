import '../model/aerodrome_directory.dart';
import '../model/flight.dart';
import '../model/flight_duration.dart';
import '../model/geo_coordinate.dart';
import '../model/solar_position.dart';
import '../model/utc_instant.dart';
import '../projection/derived_quantity.dart';

/// EASA `night_rule` primitive: `FCL.010` defines night as the period
/// between the end of evening civil twilight and the beginning of morning
/// civil twilight — one quantity, `night`, unlike the FAA rule (#22), which
/// keeps a second, separate window for takeoff/landing currency.
///
/// Position during the flight is approximated as a straight line — in the
/// great-circle sense — between the first and last resolvable route
/// waypoints, walked in step with elapsed time. See
/// `docs/adr/0008-night-time-position-interpolation.md` for why, and for
/// what a route with no resolvable waypoint at all does here.
Map<String, DerivedQuantity> easaNightTime(
  Flight flight,
  AerodromeDirectory aerodromes,
) {
  final start = flight.takeoff ?? flight.offBlocks;
  final end = flight.landing ?? flight.onBlocks;

  final departure = _resolvePosition(_firstOrNull(flight.route), aerodromes);
  final destination = _resolvePosition(_lastOrNull(flight.route), aerodromes);

  if (departure == null && destination == null) {
    return {
      'night': DerivedQuantity.notCreditable(
        FlightDuration.zero,
        "FCL.010 'night': neither the departure nor the destination in "
        "this flight's route could be resolved to a position, so night "
        'time cannot be computed',
      ),
    };
  }

  final from = departure ?? destination!;
  final to = destination ?? departure!;

  final nightDuration = _nightPortion(
    start: start,
    end: end,
    positionAtFraction: (fraction) =>
        interpolateGreatCircle(from, to, fraction),
  );

  return {
    'night': DerivedQuantity.creditable(
      nightDuration,
      "FCL.010 'night': end of evening civil twilight to beginning of "
      "morning civil twilight, along the flight's route",
    ),
  };
}

String? _firstOrNull(List<String> route) => route.isEmpty ? null : route.first;

String? _lastOrNull(List<String> route) => route.isEmpty ? null : route.last;

GeoCoordinate? _resolvePosition(
  String? identifier,
  AerodromeDirectory aerodromes,
) => identifier == null ? null : aerodromes.byIcao(identifier)?.position;

/// The portion of [start] to [end] during which the sun is more than 6
/// degrees below the horizon at the aircraft's position, sampled once per
/// whole minute — [FlightDuration]'s own granularity, so this never needs
/// sub-minute precision.
///
/// Each minute is classified atomically, day or night, from the sun's
/// elevation at that minute's midpoint — accurate enough given the position
/// approximation ([positionAtFraction]) is itself only a straight line
/// between two waypoints, and simpler than bisecting a twilight-crossing
/// instant to sub-minute precision only to immediately truncate it back to
/// whole minutes.
FlightDuration _nightPortion({
  required UtcInstant start,
  required UtcInstant end,
  required GeoCoordinate Function(double fraction) positionAtFraction,
}) {
  final totalMinutes = end.difference(start).inMinutes;
  if (totalMinutes <= 0) {
    return FlightDuration.zero;
  }

  var nightMinutes = 0;
  for (var minute = 0; minute < totalMinutes; minute++) {
    final midpoint = start.add(Duration(minutes: minute, seconds: 30));
    final fraction = (minute + 0.5) / totalMinutes;
    if (isNight(midpoint, positionAtFraction(fraction))) {
      nightMinutes++;
    }
  }
  return FlightDuration(nightMinutes);
}
