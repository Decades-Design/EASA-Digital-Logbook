import 'cross_country_time.dart';
import 'instrument_time.dart';
import 'multi_pilot_time.dart';
import 'night_time.dart';
import 'pilot_function_time.dart';

/// Looks up a named primitive by the id a [JurisdictionProfile] names in a
/// rule key (`pic_rule`, `night_rule`, ...), e.g. `easa.pilot_function_time`.
///
/// A registry, not a hardcoded `switch` on jurisdiction id, because the
/// engine that calls it ([JurisdictionProjection]) must never itself branch
/// on which jurisdiction it is running — CLAUDE.md's acceptance test for
/// this whole abstraction is that adding a new authority needs a YAML
/// profile and at most one new primitive per rule kind, never a change here.
///
/// One map per rule *kind*, not one flat map keyed only by id: `pic_rule`,
/// `night_rule` and `cross_country_rule` are different function shapes
/// ([PilotFunctionTimeRule], [NightTimeRule], [CrossCountryRule]), and a
/// single `Map<String, Object>` would push the cast back onto every caller.
class PrimitiveRegistry {
  const PrimitiveRegistry({
    required this.pilotFunctionTimeRules,
    required this.nightTimeRules,
    required this.crossCountryRules,
    required this.instrumentTimeRules,
    required this.multiPilotTimeRules,
  });

  final Map<String, PilotFunctionTimeRule> pilotFunctionTimeRules;
  final Map<String, NightTimeRule> nightTimeRules;
  final Map<String, CrossCountryRule> crossCountryRules;
  final Map<String, InstrumentTimeRule> instrumentTimeRules;
  final Map<String, MultiPilotTimeRule> multiPilotTimeRules;

  /// Throws [ArgumentError] naming [ruleId] if nothing is registered under
  /// it — a profile referencing a primitive that was never wired up is a
  /// configuration bug, not a state to silently paper over with a zeroed
  /// result.
  PilotFunctionTimeRule pilotFunctionTime(String ruleId) {
    final rule = pilotFunctionTimeRules[ruleId];
    if (rule == null) {
      throw ArgumentError.value(
        ruleId,
        'ruleId',
        'no pilot-function-time primitive is registered under this id',
      );
    }
    return rule;
  }

  /// As [pilotFunctionTime], for a profile's `night_rule` key.
  NightTimeRule nightTime(String ruleId) {
    final rule = nightTimeRules[ruleId];
    if (rule == null) {
      throw ArgumentError.value(
        ruleId,
        'ruleId',
        'no night-time primitive is registered under this id',
      );
    }
    return rule;
  }

  /// As [pilotFunctionTime], for a profile's `cross_country_rule` key.
  CrossCountryRule crossCountry(String ruleId) {
    final rule = crossCountryRules[ruleId];
    if (rule == null) {
      throw ArgumentError.value(
        ruleId,
        'ruleId',
        'no cross-country primitive is registered under this id',
      );
    }
    return rule;
  }

  /// As [pilotFunctionTime], for a profile's `instrument_rule` key.
  InstrumentTimeRule instrumentTime(String ruleId) {
    final rule = instrumentTimeRules[ruleId];
    if (rule == null) {
      throw ArgumentError.value(
        ruleId,
        'ruleId',
        'no instrument-time primitive is registered under this id',
      );
    }
    return rule;
  }

  /// As [pilotFunctionTime], for a profile's `multi_pilot_rule` key.
  MultiPilotTimeRule multiPilotTime(String ruleId) {
    final rule = multiPilotTimeRules[ruleId];
    if (rule == null) {
      throw ArgumentError.value(
        ruleId,
        'ruleId',
        'no multi-pilot-time primitive is registered under this id',
      );
    }
    return rule;
  }
}
