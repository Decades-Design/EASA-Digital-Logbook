import '../model/aerodrome_directory.dart';
import '../model/flight.dart';
import '../model/flight_duration.dart';
import '../projection/derived_quantity.dart';
import 'night_time_support.dart';

/// FAA `night_rule` primitive. `§1.1` defines night, for *logging* flight
/// time, identically to EASA's `FCL.010` — the period between the end of
/// evening civil twilight and the beginning of morning civil twilight — so
/// this reuses the same [civilTwilightNightPortion] the EASA primitive
/// (#21) does, under a different key and citation.
///
/// `§61.57(b)` night *takeoff and landing currency* uses a second, distinct
/// window: one hour after sunset to one hour before sunrise, always later-
/// starting and earlier-ending than the twilight window — a landing can be
/// night for logging but not yet night for currency, and vice versa,
/// `docs/jurisdiction-matrix.md` line 88. This primitive does not compute
/// that window: `Flight.landings` (`CircuitCounts.nightFullStop` /
/// `nightTouchAndGo`) already records the currency-relevant day/night split
/// as a raw, pilot-entered fact per CLAUDE.md rule 2 — not something this
/// projection may recompute or reconcile against its own `nightFlightTime`
/// figure. Rule 5 is why the two are kept under different names rather than
/// one "night" quantity meaning two different things depending on which
/// part of the app reads it.
///
/// `§1.1`'s position-lights window (sunset to sunrise, a third definition)
/// is deliberately not implemented — nothing in this app advises on
/// position lights.
Map<String, DerivedQuantity> faaNightTime(
  Flight flight,
  AerodromeDirectory aerodromes,
) {
  final night = civilTwilightNightPortion(flight, aerodromes);

  if (night == null) {
    return {
      'nightFlightTime': DerivedQuantity.notCreditable(
        FlightDuration.zero,
        "§1.1 'night': neither the departure nor the destination in this "
        "flight's route could be resolved to a position, so night flight "
        'time cannot be computed',
      ),
    };
  }

  return {
    'nightFlightTime': DerivedQuantity.creditable(
      night,
      "§1.1 'night': end of evening civil twilight to beginning of "
      "morning civil twilight, along the flight's route — logging only; "
      "§61.57(b) night takeoff/landing currency is a separate, later-"
      'starting window recorded on Flight.landings, not this quantity',
    ),
  };
}
