import 'easa_cross_country_time.dart';
import 'easa_night_time.dart';
import 'easa_pilot_function_time.dart';
import 'faa_cross_country_time.dart';
import 'faa_night_time.dart';
import 'faa_pilot_function_time.dart';
import 'primitive_registry.dart';

/// The [PrimitiveRegistry] the app actually ships — every primitive id an
/// `assets/jurisdictions/*.yaml` profile can reference, wired to its real
/// implementation.
///
/// Grows by one line per primitive as later issues (#25-26:
/// instrument/multi-pilot time) land — never by a change to
/// [JurisdictionProjection], which only ever sees this through the
/// [PrimitiveRegistry] interface.
final PrimitiveRegistry defaultPrimitives = PrimitiveRegistry(
  pilotFunctionTimeRules: {
    'easa.pilot_function_time': easaPilotFunctionTime,
    'faa.pilot_function_time': faaPilotFunctionTime,
  },
  nightTimeRules: {
    'easa.night_time': easaNightTime,
    'faa.night_time': faaNightTime,
  },
  crossCountryRules: {
    'easa.cross_country_time': easaCrossCountryTime,
    'faa.cross_country_time': faaCrossCountryTime,
  },
);
