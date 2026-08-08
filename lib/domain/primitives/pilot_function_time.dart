import '../model/flight.dart';
import '../model/flight_duration.dart';
import '../projection/derived_quantity.dart';

/// A named, jurisdiction-specific rule computing the pilot-function-time
/// quantities (PIC, dual, and whatever else that jurisdiction distinguishes)
/// for one flight, from its already-computed [blockTime].
///
/// One function per jurisdiction, not one per quantity: EASA's PIC, dual,
/// SPIC and PICUS are interdependent — knowing whether a flight is SPIC
/// changes what PIC is — so they are derived together from one reading of
/// [flight.capacity], not as four independent lookups that could disagree
/// with each other. CLAUDE.md's `pic_rule: faa.sole_manipulator` naming is
/// shorthand for exactly this: one profile key, one primitive, the whole
/// related bundle back at once.
typedef PilotFunctionTimeRule =
    Map<String, DerivedQuantity> Function(
      Flight flight,
      FlightDuration blockTime,
    );
