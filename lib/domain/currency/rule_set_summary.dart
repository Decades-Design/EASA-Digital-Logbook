import 'currency_rule.dart';

/// Which rules are actually loaded, grouped for the Settings "About" section
/// — pure aggregation over already-loaded [CurrencyRule]s, no evaluation.
class RuleSetSummary {
  const RuleSetSummary({
    required this.total,
    required this.byJurisdiction,
    required this.medicalCount,
  });

  final int total;

  /// Rule count keyed by [CurrencyRule.jurisdictionId].
  final Map<String, int> byJurisdiction;

  /// How many rules are medical-certificate-validity rules — a rule counts
  /// if any [Requirement] in its tree names a `medical_certificate.*` held
  /// record kind. Cuts across jurisdiction rather than being a third
  /// category alongside it: a medical rule is still counted in its own
  /// jurisdiction's total too.
  final int medicalCount;
}

/// Groups [rules] by jurisdiction and counts how many are medical-validity
/// rules. Every rule known to the engine has a [CurrencyRule.jurisdictionId]
/// — medicals are evaluated by the same generic rule engine as any other
/// currency rule, not a separate mechanism (see
/// `assets/rules/easa/med_a045_class1_validity.yaml`).
RuleSetSummary summarizeRuleSet(List<CurrencyRule> rules) {
  final byJurisdiction = <String, int>{};
  var medicalCount = 0;
  for (final rule in rules) {
    byJurisdiction[rule.jurisdictionId] =
        (byJurisdiction[rule.jurisdictionId] ?? 0) + 1;
    if (_isMedical(rule.requirement)) {
      medicalCount++;
    }
  }
  return RuleSetSummary(
    total: rules.length,
    byJurisdiction: byJurisdiction,
    medicalCount: medicalCount,
  );
}

/// Walks a [Requirement] tree (through `allOf`/`anyOf`'s [Requirement.of])
/// looking for a `held_record_currently_valid` leaf naming a
/// `medical_certificate.*` kind.
bool _isMedical(Requirement requirement) {
  if (requirement.heldRecordKind?.startsWith('medical_certificate.') ?? false) {
    return true;
  }
  return requirement.of.any(_isMedical);
}
