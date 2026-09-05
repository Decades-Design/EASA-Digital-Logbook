import '../model/flight_duration.dart';
import 'projection_result.dart';

/// Function-time quantities that represent credited command-authority time,
/// per jurisdiction — the same "which key means PIC-ish" knowledge
/// `totals_screen.dart`'s own function-tab row list carries for display,
/// scoped down to just the command-authority subset. EASA and FAA don't
/// share a vocabulary here, so a divergence check has to compare *minutes*,
/// not key names — see [commandTimeDiverges].
///
/// FAA's own `actingPic` is deliberately excluded: `faa_pilot_function_time
/// .dart`'s dartdoc notes it and `loggedPic` "can both be creditable" for
/// the same ordinary flight (a safety-pilot scenario) — they measure two
/// different things (who held legal responsibility vs who gets to log PIC
/// time), not two additive contributions, so summing both here would
/// double-count a single flight's time. `loggedPic` — §61.51(e)(1)(i)'s
/// sole-manipulator rule — is the FAA quantity that actually corresponds to
/// what goes in the PIC column, the same pairing
/// `easa_faa_divergence_test.dart` itself compares `easa['pic']` against.
const _commandAuthorityKeys = {
  'eu.easa.part-fcl': {'pic', 'picus', 'spic'},
  'us.faa.part61': {'loggedPic'},
};

/// Total creditable command-authority time [result] credits, summing
/// whichever of its own jurisdiction's command-authority quantities came
/// back creditable. A quantity that exists but isn't creditable yet (a
/// PICUS sector awaiting countersignature) doesn't count here — the same
/// "never silently valid" rule [DerivedQuantity.creditable] itself exists
/// for.
FlightDuration commandAuthorityTime(ProjectionResult result) {
  final keys = _commandAuthorityKeys[result.jurisdictionId] ?? const {};
  return FlightDuration.sum([
    for (final key in keys)
      if (result[key] case final quantity? when quantity.creditable)
        quantity.value,
  ]);
}

/// Whether the same flight's credited command-authority time would differ
/// depending which of [results]' jurisdictions it's totalled under —
/// CLAUDE.md's multi-jurisdiction UX rule: "a flight whose derived values
/// differ under a secondary licence gets a badge opening a side-by-side
/// comparison." Compares total minutes rather than a shared role label,
/// since EASA and FAA's own command-authority concepts don't share a
/// vocabulary to compare by name — see `easa_faa_divergence_test.dart`'s
/// "sole manipulator receiving instruction" case for the canonical example
/// this exists to catch (FAA logs PIC while receiving instruction; EASA
/// logs dual).
///
/// `false` for fewer than two results — there's nothing to diverge from.
bool commandTimeDiverges(Iterable<ProjectionResult> results) {
  FlightDuration? first;
  var sawAny = false;
  for (final result in results) {
    final time = commandAuthorityTime(result);
    if (!sawAny) {
      first = time;
      sawAny = true;
    } else if (time != first) {
      return true;
    }
  }
  return false;
}
