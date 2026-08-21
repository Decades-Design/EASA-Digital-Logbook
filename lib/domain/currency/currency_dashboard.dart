import '../model/calendar_date.dart';
import 'currency_expiry_projection.dart';
import 'currency_rule_evaluator.dart';
import 'currency_rule_loader.dart';
import 'evaluation_subject.dart';
import 'rule_result.dart';

/// One held licence's worth of currency rows to evaluate — the Currency
/// screen's per-licence grouping (CLAUDE.md: "show all held licences
/// grouped, always").
///
/// [privilegeSummary] and [ruleIds] are supplied by the caller rather than
/// derived from held ratings: rolling ratings/medicals up into "one row per
/// issuing authority with a privileges summary", and resolving which
/// currency rules actually apply to what a pilot holds, are both real
/// features with no domain representation yet (flagged for the Settings
/// phase of this redesign) — a real caller hand-picks both today the same
/// way `sample_currency_data.dart` does.
class CurrencyLicenceSpec {
  const CurrencyLicenceSpec({
    required this.jurisdictionId,
    required this.label,
    required this.isPrimary,
    required this.privilegeSummary,
    required this.ruleIds,
  });

  final String jurisdictionId;
  final String label;
  final bool isPrimary;
  final String privilegeSummary;

  /// Which loaded [CurrencyRule] ids apply under this licence, in display
  /// order.
  final List<String> ruleIds;
}

/// One evaluated currency rule, ready to render as a row.
class CurrencyDashboardRow {
  const CurrencyDashboardRow({
    required this.title,
    required this.evaluation,
    required this.isAtRisk,
  });

  final String title;
  final CurrencyRuleEvaluation evaluation;

  /// Unsatisfied, or satisfied with an [RuleResult.expiresOn] inside the
  /// hero window — [isNearingExpiry]'s own criteria. This is what decides
  /// hero-row membership; "not current, with no explanation" (CLAUDE.md)
  /// applies just as much to an unsatisfied rule with no expiry as to one
  /// about to lapse, so both count as at-risk here.
  final bool isAtRisk;
}

class CurrencyLicenceGroup {
  const CurrencyLicenceGroup({
    required this.jurisdictionId,
    required this.label,
    required this.isPrimary,
    required this.privilegeSummary,
    required this.rows,
  });

  final String jurisdictionId;
  final String label;
  final bool isPrimary;
  final String privilegeSummary;
  final List<CurrencyDashboardRow> rows;
}

/// Every held licence's currency rows, grouped for display — the Currency
/// screen's whole data model, built fresh from [buildCurrencyDashboard] on
/// each load rather than cached, since it is cheap and always as-of "now".
class CurrencyDashboard {
  const CurrencyDashboard({required this.groups});

  final List<CurrencyLicenceGroup> groups;

  /// Rows worth surfacing in the hero row — across every group, in group
  /// order. Empty when nothing is expired or due soon, which hides the
  /// whole hero row (the mockup's own rule: "nothing appears there unless
  /// it is expired or inside 30 days").
  List<CurrencyDashboardRow> get atRiskRows => [
    for (final group in groups)
      for (final row in group.rows)
        if (row.isAtRisk) row,
  ];
}

/// Resolves, evaluates and groups every rule named by [licences] — the
/// Currency screen's whole pipeline, kept as one pure function so it can be
/// unit-tested without a widget tree.
///
/// [heroLeadDays] is [isNearingExpiry]'s own `leadDays` parameter, exposed
/// rather than hard-coded per that function's own dartdoc ("always
/// caller-supplied, never a fixed default").
CurrencyDashboard buildCurrencyDashboard({
  required List<CurrencyLicenceSpec> licences,
  required CurrencyRuleLoader loader,
  required EvaluationSubject subject,
  required CalendarDate asOf,
  CurrencyRuleEvaluator evaluator = const CurrencyRuleEvaluator(),
  int heroLeadDays = 30,
}) {
  final groups = <CurrencyLicenceGroup>[];
  for (final licence in licences) {
    final rows = <CurrencyDashboardRow>[
      for (final ruleId in licence.ruleIds)
        _evaluateRow(ruleId, loader, evaluator, subject, asOf, heroLeadDays),
    ];
    groups.add(
      CurrencyLicenceGroup(
        jurisdictionId: licence.jurisdictionId,
        label: licence.label,
        isPrimary: licence.isPrimary,
        privilegeSummary: licence.privilegeSummary,
        rows: rows,
      ),
    );
  }
  return CurrencyDashboard(groups: groups);
}

CurrencyDashboardRow _evaluateRow(
  String ruleId,
  CurrencyRuleLoader loader,
  CurrencyRuleEvaluator evaluator,
  EvaluationSubject subject,
  CalendarDate asOf,
  int heroLeadDays,
) {
  final rule = loader.resolve(ruleId, asOf);
  final evaluation = evaluator.evaluateRule(rule, subject, asOf);
  final expiresOn = evaluation.result.expiresOn;
  final isAtRisk =
      !evaluation.result.satisfied ||
      (expiresOn != null &&
          isNearingExpiry(expiresOn, asOf, leadDays: heroLeadDays));
  return CurrencyDashboardRow(
    title: rule.title,
    evaluation: evaluation,
    isAtRisk: isAtRisk,
  );
}
