import '../model/calendar_date.dart';
import 'rule_result.dart';

/// One [CurrencyRuleEvaluation]'s worth of "when does this next lapse",
/// pulled out of its full result — what [nextToExpire] returns.
class NextExpiry {
  const NextExpiry({
    required this.ruleId,
    required this.citation,
    required this.expiresOn,
  });

  final String ruleId;
  final String citation;
  final CalendarDate expiresOn;
}

/// Whether [expiresOn] falls within [leadDays] of [asOf] — #51's
/// "warnings surfaced ahead of expiry, with a configurable lead time".
/// [leadDays] is always caller-supplied, never a fixed default baked in
/// here: how much warning is useful differs by what's expiring (a medical
/// certificate deserves more notice than a 90-day landing count) and is a
/// UI/settings concern, not this function's to decide.
///
/// `false` once [expiresOn] is already in the past relative to [asOf] —
/// that is [RuleResult.satisfied] turning `false`, a different state from
/// "still current but about to lapse". Meaningful only when called for a
/// requirement that is currently satisfied; an unsatisfied requirement's
/// [RuleResult.expiresOn] is already null.
bool isNearingExpiry(
  CalendarDate expiresOn,
  CalendarDate asOf, {
  required int leadDays,
}) {
  if (expiresOn < asOf) {
    return false;
  }
  final warningStart = expiresOn.addDays(-leadDays);
  return asOf >= warningStart;
}

/// Across every rule evaluation in [evaluations], the one that lapses
/// soonest — #44's "combined next thing to expire view across all
/// applicable requirements".
///
/// "You are current" is less useful than "you stop being current on 14
/// September unless you fly" (#44's own framing) — this is the single
/// figure a dashboard needs to show that.
///
/// An evaluation only competes for "next to expire" if it is currently
/// [RuleResult.satisfied] *and* carries a real [RuleResult.expiresOn]:
///
/// - Unsatisfied requirements (no qualifying events at all, or not enough
///   of them) are excluded, not treated as "already expired" — they are a
///   "not current" state, a different concern from "about to lapse".
/// - Requirements that can never lapse (satisfied with a null
///   [RuleResult.expiresOn] — an FAA endorsement, for instance) are
///   likewise excluded: something that never lapses can never be the next
///   thing *to* lapse.
///
/// Returns `null` if nothing in [evaluations] qualifies — an empty list, or
/// a list where every entry is unsatisfied, never-lapsing, or both.
NextExpiry? nextToExpire(List<CurrencyRuleEvaluation> evaluations) {
  CurrencyRuleEvaluation? earliest;
  for (final evaluation in evaluations) {
    final expiresOn = evaluation.result.expiresOn;
    if (!evaluation.result.satisfied || expiresOn == null) {
      continue;
    }
    final earliestExpiresOn = earliest?.result.expiresOn;
    if (earliestExpiresOn == null || expiresOn < earliestExpiresOn) {
      earliest = evaluation;
    }
  }
  if (earliest == null) {
    return null;
  }
  return NextExpiry(
    ruleId: earliest.ruleId,
    citation: earliest.citation,
    expiresOn: earliest.result.expiresOn!,
  );
}
