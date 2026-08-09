import '../model/flight.dart';
import '../model/flight_duration.dart';
import '../projection/derived_quantity.dart';

/// A named, jurisdiction-specific rule computing the instrument-time
/// quantities for one flight, from its already-computed [blockTime].
///
/// One function per jurisdiction, not one per quantity, matching
/// [PilotFunctionTimeRule]'s reasoning — EASA's single IFR figure and the
/// FAA's actual/simulated split read different raw facts on [Flight] and
/// have nothing to reconcile against each other, but keeping the same
/// shape as the other rule kinds means [PrimitiveRegistry] and
/// [JurisdictionProjection] need no special case for this one.
typedef InstrumentTimeRule =
    Map<String, DerivedQuantity> Function(
      Flight flight,
      FlightDuration blockTime,
    );
