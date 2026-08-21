import 'package:freezed_annotation/freezed_annotation.dart';

import '../model/calendar_date.dart';
import '../model/flight_duration.dart';

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

    /// The structured numbers behind [explanation] — a progress bar or
    /// "4 / 6" readout needs the actual current/required values, not a
    /// regex against prose. Null for a composite (`allOf`/`anyOf`) result,
    /// where no single number represents the requirement.
    RuleProgress? progress,
  }) = _RuleResult;
}

/// The count/hours/validity numbers a leaf [RuleResult] was decided from —
/// what a progress bar and a "current / required" readout render from,
/// instead of parsing [RuleResult.explanation]'s prose back into numbers.
///
/// A flat class with a [kind] discriminator, not a sealed union — the same
/// shape [FlightCondition] and [Requirement] already use in this codebase
/// (see `currency_rule.dart`'s dartdoc for why).
enum RuleProgressKind { count, hours, validity }

@freezed
abstract class RuleProgress with _$RuleProgress {
  const factory RuleProgress({
    required RuleProgressKind kind,

    // ---- count.
    int? currentCount,
    int? requiredCount,

    // ---- hours.
    FlightDuration? currentHours,
    FlightDuration? requiredHours,

    // ---- validity. No "current/required" here — a held document either
    // covers the evaluation date or it doesn't; the progress bar instead
    // fills by how much of [validFrom]..[validUntil] has elapsed.
    CalendarDate? validFrom,
    CalendarDate? validUntil,
  }) = _RuleProgress;

  factory RuleProgress.count({required int current, required int required}) =>
      RuleProgress(
        kind: RuleProgressKind.count,
        currentCount: current,
        requiredCount: required,
      );

  factory RuleProgress.hours({
    required FlightDuration current,
    required FlightDuration required,
  }) => RuleProgress(
    kind: RuleProgressKind.hours,
    currentHours: current,
    requiredHours: required,
  );

  factory RuleProgress.validity({
    required CalendarDate validFrom,
    CalendarDate? validUntil,
  }) => RuleProgress(
    kind: RuleProgressKind.validity,
    validFrom: validFrom,
    validUntil: validUntil,
  );
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
