import '../model/aerodrome_directory.dart';
import '../model/flight.dart';
import '../model/flight_duration.dart';
import '../projection/derived_quantity.dart';
import 'night_time_support.dart';

/// EASA `night_rule` primitive: `FCL.010` defines night as the period
/// between the end of evening civil twilight and the beginning of morning
/// civil twilight — one quantity, `night`, unlike the FAA rule (#22), which
/// keeps a second, separate window for takeoff/landing currency.
///
/// The position/time computation is [civilTwilightNightPortion], shared
/// with the FAA primitive since both jurisdictions define night *logging*
/// identically — see that function's dartdoc for the interpolation
/// approximation this rests on.
Map<String, DerivedQuantity> easaNightTime(
  Flight flight,
  AerodromeDirectory aerodromes,
) {
  final night = civilTwilightNightPortion(flight, aerodromes);

  if (night == null) {
    return {
      'night': DerivedQuantity.notCreditable(
        FlightDuration.zero,
        "FCL.010 'night': neither the departure nor the destination in "
        "this flight's route could be resolved to a position, so night "
        'time cannot be computed',
      ),
    };
  }

  return {
    'night': DerivedQuantity.creditable(
      night,
      "FCL.010 'night': end of evening civil twilight to beginning of "
      "morning civil twilight, along the flight's route",
    ),
  };
}
