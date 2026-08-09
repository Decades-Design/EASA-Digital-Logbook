import '../model/aerodrome_directory.dart';
import '../model/aircraft.dart';
import '../model/flight.dart';
import '../projection/derived_quantity.dart';

/// A named, jurisdiction-specific rule computing the cross-country
/// quantities for one flight.
///
/// Takes [Aircraft], unlike [PilotFunctionTimeRule] and [NightTimeRule],
/// because the FAA's credit tests gate on aircraft category — rotorcraft
/// and powered-parachute each get their own distance threshold
/// (`§61.1(b)(3)(iv)`-`(v)`) instead of the general one. EASA's rule
/// ignores the parameter; the shared shape lets both register under the
/// same [PrimitiveRegistry] map rather than needing two typedefs for what
/// is, from the engine's point of view, one rule kind.
typedef CrossCountryRule =
    Map<String, DerivedQuantity> Function(
      Flight flight,
      Aircraft aircraft,
      AerodromeDirectory aerodromes,
    );
