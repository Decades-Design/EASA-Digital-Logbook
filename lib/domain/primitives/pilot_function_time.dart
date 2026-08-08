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

/// Looks up a [PilotFunctionTimeRule] by the id a [JurisdictionProfile]
/// names in its `pic_rule` key, e.g. `easa.pilot_function_time`.
///
/// A registry, not a hardcoded `switch` on jurisdiction id, because the
/// engine that calls it ([JurisdictionProjection]) must never itself branch
/// on which jurisdiction it is running — CLAUDE.md's acceptance test for
/// this whole abstraction is that adding a new authority needs a YAML
/// profile and at most one new primitive, never a change here.
class PrimitiveRegistry {
  const PrimitiveRegistry(this._pilotFunctionTimeRules);

  final Map<String, PilotFunctionTimeRule> _pilotFunctionTimeRules;

  /// Throws [ArgumentError] naming [ruleId] if nothing is registered under
  /// it — a profile referencing a primitive that was never wired up is a
  /// configuration bug, not a state to silently paper over with a zeroed
  /// result.
  PilotFunctionTimeRule pilotFunctionTime(String ruleId) {
    final rule = _pilotFunctionTimeRules[ruleId];
    if (rule == null) {
      throw ArgumentError.value(
        ruleId,
        'ruleId',
        'no pilot-function-time primitive is registered under this id',
      );
    }
    return rule;
  }
}
