import 'easa_pilot_function_time.dart';
import 'faa_pilot_function_time.dart';
import 'pilot_function_time.dart';

/// The [PrimitiveRegistry] the app actually ships — every primitive id an
/// `assets/jurisdictions/*.yaml` profile can reference, wired to its real
/// implementation.
///
/// Grows by one line per primitive as later issues (#21-26:
/// night/cross-country/instrument) land — never by a change to
/// [JurisdictionProjection], which only ever sees this through the
/// [PrimitiveRegistry] interface.
final PrimitiveRegistry defaultPrimitives = PrimitiveRegistry({
  'easa.pilot_function_time': easaPilotFunctionTime,
  'faa.pilot_function_time': faaPilotFunctionTime,
});
