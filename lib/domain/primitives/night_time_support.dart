import '../model/aerodrome_directory.dart';
import '../model/flight.dart';
import '../model/flight_duration.dart';
import '../model/geo_coordinate.dart';
import '../model/solar_position.dart';
import '../model/utc_instant.dart';

/// Shared by the EASA (#21) and FAA (#22) night-time primitives: both
/// define night, for *logging* purposes, identically — the period the sun
/// is more than 6 degrees below the horizon (civil twilight) —
/// `docs/jurisdiction-matrix.md` line 87. Only the [DerivedQuantity] name
/// and the cited rule differ per jurisdiction; the position/time
/// computation itself does not, so it lives in exactly one place.
///
/// Position during the flight is approximated per
/// `docs/adr/0008-night-time-position-interpolation.md` — a straight
/// great-circle line between the first and last resolvable route waypoints,
/// walked in step with elapsed time between [Flight.takeoff]/
/// [Flight.landing] (or [Flight.offBlocks]/[Flight.onBlocks] where airborne
/// times aren't recorded).
///
/// Returns `null` if neither the departure nor the destination in
/// [flight]'s route resolved to a position — the caller decides how to
/// report that in its own jurisdiction's vocabulary, rather than this
/// shared helper guessing at a shape that fits both.
FlightDuration? civilTwilightNightPortion(
  Flight flight,
  AerodromeDirectory aerodromes,
) {
  final start = flight.takeoff ?? flight.offBlocks;
  final end = flight.landing ?? flight.onBlocks;

  final departure = _resolvePosition(_firstOrNull(flight.route), aerodromes);
  final destination = _resolvePosition(_lastOrNull(flight.route), aerodromes);

  if (departure == null && destination == null) {
    return null;
  }

  final from = departure ?? destination!;
  final to = destination ?? departure!;

  return _nightPortion(
    start: start,
    end: end,
    positionAtFraction: (fraction) =>
        interpolateGreatCircle(from, to, fraction),
  );
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
