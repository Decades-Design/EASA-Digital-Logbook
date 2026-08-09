import 'package:freezed_annotation/freezed_annotation.dart';

import '../model/calendar_date.dart';
import '../model/flight_duration.dart';
import 'flight_condition.dart';
import 'rule_window.dart';

part 'currency_rule.freezed.dart';

/// One versioned currency rule, as loaded from `assets/rules/*.yaml` — #40.
///
/// [id] identifies the rule across its whole lineage; [effectiveFrom] and
/// [expiresOn] place one version of it in time, per #41 — "a flight in 2019
/// must be evaluated against the rule in force in 2019". Superseded versions
/// are retained (never deleted, per #40's acceptance criteria), so several
/// [CurrencyRule]s can share the same [id].
@freezed
abstract class CurrencyRule with _$CurrencyRule {
  const factory CurrencyRule({
    /// Stable across every version of this rule, e.g.
    /// `easa.fcl060.passenger_recency`.
    required String id,

    /// The [JurisdictionProfile.id] this rule belongs to, e.g.
    /// `eu.easa.part-fcl`.
    required String jurisdictionId,

    /// The regulation this rule implements, e.g. `FCL.060(b)(1)`. Mandatory
    /// per #40 — every [RuleResult] carries it through for display.
    required String citation,

    /// The date this version takes effect. #41 selects, for a given
    /// evaluation date, the latest version with `effectiveFrom <=` that date.
    required CalendarDate effectiveFrom,

    /// The date this version was superseded, null while still current.
    /// Retained rather than deleted so a historical flight is always
    /// evaluated against the rule actually in force on its date.
    CalendarDate? expiresOn,

    required Requirement requirement,
  }) = _CurrencyRule;
}

/// What #40 calls "must express": a count or hours total of qualifying
/// flight events within a window, a held document's current validity, or a
/// composite of other requirements — the alternative-means-of-compliance
/// case (#40: "a proficiency check satisfying a requirement in place of
/// recency") is [anyOf] over two differently-shaped requirements, not a
/// distinct kind of its own.
///
/// One flat class with a [kind] discriminator — see `FlightCondition`'s
/// dartdoc for why that shape was chosen over a sealed union in this
/// codebase.
@freezed
abstract class Requirement with _$Requirement {
  const factory Requirement({
    required RequirementKind kind,

    // ---- flightEventCount / flightEventHours.
    CountableFlightEvent? event,
    int? count,
    FlightDuration? hours,
    RuleWindow? window,
    @Default(<FlightCondition>[]) List<FlightCondition> conditions,

    // ---- heldRecordCurrentlyValid. Also the "prerequisite on the pilot"
    // case (#40) -- "holds an instrument rating" and "the medical
    // certificate is valid" are the same check: is there a currently-valid
    // HeldRecord of this kind.
    String? heldRecordKind,

    // ---- allOf / anyOf.
    @Default(<Requirement>[]) List<Requirement> of,
  }) = _Requirement;

  factory Requirement.flightEventCount({
    required CountableFlightEvent event,
    required int count,
    required RuleWindow window,
    List<FlightCondition> conditions = const [],
  }) => Requirement(
    kind: RequirementKind.flightEventCount,
    event: event,
    count: count,
    window: window,
    conditions: conditions,
  );

  factory Requirement.flightEventHours({
    required CountableFlightEvent event,
    required FlightDuration hours,
    required RuleWindow window,
    List<FlightCondition> conditions = const [],
  }) => Requirement(
    kind: RequirementKind.flightEventHours,
    event: event,
    hours: hours,
    window: window,
    conditions: conditions,
  );

  factory Requirement.heldRecordCurrentlyValid(String heldRecordKind) =>
      Requirement(
        kind: RequirementKind.heldRecordCurrentlyValid,
        heldRecordKind: heldRecordKind,
      );

  factory Requirement.allOf(List<Requirement> of) =>
      Requirement(kind: RequirementKind.allOf, of: of);

  factory Requirement.anyOf(List<Requirement> of) =>
      Requirement(kind: RequirementKind.anyOf, of: of);
}

enum RequirementKind {
  flightEventCount,
  flightEventHours,
  heldRecordCurrentlyValid,
  allOf,
  anyOf,
}

/// A per-flight numeric fact [Requirement.flightEventCount] and
/// [Requirement.flightEventHours] can sum across a flight set.
///
/// `landings` and `takeoffs` read [Flight.landings]/[Flight.takeoffs]
/// narrowed by [FlightCondition.dayNight] and [FlightCondition.landingType];
/// `approaches` sums [Approach.count]; `holdingProcedures` reads
/// [Flight.holdingProceduresCount]; `trackingPerformed` reads
/// [Flight.trackingPerformed] as a presence fact (0 or 1, not a count);
/// the three alt-compliance values (#121) read
/// [Flight.alternativeComplianceEvents] the same way — each is a growth of
/// this enum with one more `_eventCount` dispatch case, the kind of
/// addition CLAUDE.md's jurisdiction-primitive acceptance test describes,
/// not "touching the evaluator" in the sense #42 warns against.
enum CountableFlightEvent {
  landings,
  takeoffs,
  approaches,
  holdingProcedures,
  trackingPerformed,
  faaFlightReview,
  faaInstrumentProficiencyCheck,
  easaClassRatingProficiencyCheck,
}
