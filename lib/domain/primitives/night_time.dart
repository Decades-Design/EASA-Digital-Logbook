import '../model/aerodrome_directory.dart';
import '../model/flight.dart';
import '../projection/derived_quantity.dart';

/// A named, jurisdiction-specific rule computing the night-time quantities
/// for one flight.
///
/// Takes the whole [Flight], not a precomputed block time, because night
/// determination needs the route (to resolve position — #21's ADR-0008
/// covers how) and needs [Flight.takeoff]/[Flight.landing] in preference to
/// [Flight.offBlocks]/[Flight.onBlocks] where they're recorded, since night
/// is a property of when the aircraft was airborne, not when it was
/// taxiing. [aerodromes] resolves route identifiers to positions; a route
/// entry with no matching entry (a private strip, `docs/entry-form.md`) is
/// not an error — see the individual primitives for how they degrade.
typedef NightTimeRule =
    Map<String, DerivedQuantity> Function(
      Flight flight,
      AerodromeDirectory aerodromes,
    );
