import '../model/aerodrome_directory.dart';
import '../model/aircraft.dart';
import '../model/flight.dart';
import '../model/flight_duration.dart';
import '../projection/derived_quantity.dart';
import 'cross_country_support.dart';

/// EASA `cross_country_rule` primitive.
///
/// `FCL.010` defines cross-country with no minimum distance: flight time
/// navigating to a destination away from the departure aerodrome, following
/// a pre-planned route, using standard navigation procedures. This gives
/// exactly one general quantity, `crossCountry`.
///
/// The definition does not require the destination to differ from the
/// departure — a solo navigation exercise that departs, flies a planned
/// route out to a distant point, and lands back where it started is still
/// cross-country. [Flight.route] alone can't express that (it records only
/// where the aircraft landed), so this reads [Flight.prePlannedNavigation]
/// as well as [landedAwayFromDeparture] — either one is sufficient.
///
/// [aircraft] is part of this primitive's signature ([CrossCountryRule])
/// but is not read — EASA's cross-country definition and its one qualifying
/// flight do not gate on aircraft category the way the FAA's do (#24).
///
/// A second, distinct quantity, `qualifyingCrossCountry`, answers the
/// licence-issue question `FCL.210.A`/`AMC1 FCL.210` asks: a route of at
/// least 270 km (150 NM), with full-stop landings at two aerodromes other
/// than the departure. This is a stricter, additional condition layered on
/// top of the general definition, not a replacement for it — a flight can
/// be `crossCountry` without being `qualifyingCrossCountry`, but not the
/// reverse.
Map<String, DerivedQuantity> easaCrossCountryTime(
  Flight flight,
  Aircraft aircraft,
  AerodromeDirectory aerodromes,
) {
  final blockTime = FlightDuration(
    flight.onBlocks.difference(flight.offBlocks).inMinutes,
  );

  return {
    'crossCountry': _generalCrossCountry(flight, blockTime),
    'qualifyingCrossCountry': _qualifyingCrossCountry(
      flight,
      aerodromes,
      blockTime,
    ),
  };
}

DerivedQuantity _generalCrossCountry(Flight flight, FlightDuration blockTime) {
  if (flight.prePlannedNavigation) {
    return DerivedQuantity.creditable(
      blockTime,
      "FCL.010 'cross-country': flown to a destination away from the "
      'departure aerodrome by a pre-planned route, using standard '
      'navigation procedures',
    );
  }
  if (landedAwayFromDeparture(flight)) {
    return DerivedQuantity.creditable(
      blockTime,
      "FCL.010 'cross-country': included a landing away from the "
      'departure aerodrome',
    );
  }
  return DerivedQuantity.zero(
    "FCL.010 'cross-country': no landing away from the departure "
    'aerodrome, and not recorded as a planned navigation exercise',
  );
}

DerivedQuantity _qualifyingCrossCountry(
  Flight flight,
  AerodromeDirectory aerodromes,
  FlightDuration blockTime,
) {
  final otherAerodromes = aerodromesVisitedOtherThanDeparture(flight);
  final totalDistanceNm = totalRouteDistanceNm(flight, aerodromes);

  if (totalDistanceNm == null) {
    return DerivedQuantity.notCreditable(
      FlightDuration.zero,
      "AMC1 FCL.210 qualifying cross-country flight: the route's distance "
      'could not be computed — fewer than two waypoints resolved to a '
      'position',
    );
  }

  final distanceQualifies = totalDistanceNm >= 150;
  final aerodromeCountQualifies = otherAerodromes.length >= 2;

  if (distanceQualifies && aerodromeCountQualifies) {
    return DerivedQuantity.creditable(
      blockTime,
      'AMC1 FCL.210 qualifying cross-country flight: '
      '${totalDistanceNm.toStringAsFixed(1)} NM total, full-stop landings '
      'at ${otherAerodromes.length} aerodromes other than departure — '
      'requires at least 150 NM (270 km) and two',
    );
  }

  return DerivedQuantity.zero(
    'AMC1 FCL.210 qualifying cross-country flight: '
    '${totalDistanceNm.toStringAsFixed(1)} NM total '
    '(needs at least 150 NM / 270 km), landings at '
    '${otherAerodromes.length} aerodrome(s) other than departure '
    '(needs at least 2) — does not qualify',
  );
}
