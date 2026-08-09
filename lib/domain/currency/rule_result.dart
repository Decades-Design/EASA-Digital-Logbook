import 'package:freezed_annotation/freezed_annotation.dart';

import '../model/calendar_date.dart';

part 'rule_result.freezed.dart';

/// The outcome of evaluating one [CurrencyRule] (or, recursively, one
/// [Requirement] inside it) against an [EvaluationSubject] — #43: "not
/// current, with no explanation, is a bug."
///
/// [components] carries the sub-results of an `allOf`/`anyOf` requirement,
/// so a composite rule's explanation can point at exactly which branch
/// succeeded or which one is missing something, rather than collapsing to a
/// single opaque boolean. Empty for a leaf requirement.
@freezed
abstract class RuleResult with _$RuleResult {
  const factory RuleResult({
    required bool satisfied,

    /// Human-readable, naming what is missing or confirming what was found
    /// — e.g. "2 of 3 night landings; needs 1 more full-stop night landing
    /// by 14 Sep" or "3 of 3 landings within 90 days, in G-ABCD (C152)".
    /// Never empty.
    required String explanation,

    /// Set when [satisfied] and the requirement can lapse — the date this
    /// result stops holding if nothing else qualifying happens. Null when
    /// [satisfied] is false, or when the requirement can never lapse.
    CalendarDate? expiresOn,

    /// Ids of the flights that contributed to this result, satisfied or
    /// not — a partial count still names which flights it has.
    @Default(<String>[]) List<String> contributingFlightIds,

    /// Sub-results of an `allOf`/`anyOf` requirement, in the order they were
    /// declared. Empty for a leaf requirement (flight-event or held-record
    /// check).
    @Default(<RuleResult>[]) List<RuleResult> components,
  }) = _RuleResult;
}

/// A [RuleResult] labelled with the rule it came from — what
/// [CurrencyRuleEvaluator.evaluate] actually returns. Kept separate from
/// [RuleResult] itself because [RuleResult.components] nests un-labelled
/// sub-results: only the outermost result belongs to a citable rule.
@freezed
abstract class CurrencyRuleEvaluation with _$CurrencyRuleEvaluation {
  const factory CurrencyRuleEvaluation({
    required String ruleId,
    required String citation,
    required RuleResult result,
  }) = _CurrencyRuleEvaluation;
}
