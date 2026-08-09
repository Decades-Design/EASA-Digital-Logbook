import '../model/aircraft.dart';
import '../model/flight.dart';
import '../model/flight_duration.dart';
import '../projection/derived_quantity.dart';

/// A named, jurisdiction-specific rule computing single-pilot/multi-pilot
/// time for one flight, from its already-computed [blockTime].
///
/// Takes [aircraft] as well as [flight]: `AMC1 FCL.050` column 5 splits
/// single-pilot time by engine count (SE/ME), a fact that lives on
/// [Aircraft], not on [Flight] or [PilotCapacity] — see [easaMultiPilotTime].
/// No FAA primitive exists under this rule kind: `docs/amc1-fcl050-layout.md`
/// column 5 is an EASA/UK column with no FAA logbook analogue, and a profile
/// that never sets `multi_pilot_rule` simply yields no quantities under this
/// name, the same "not every rule kind applies to every jurisdiction"
/// pattern [JurisdictionProjection] already uses for the others.
typedef MultiPilotTimeRule =
    Map<String, DerivedQuantity> Function(
      Flight flight,
      Aircraft aircraft,
      FlightDuration blockTime,
    );
