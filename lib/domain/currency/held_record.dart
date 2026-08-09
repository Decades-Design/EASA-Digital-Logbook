import '../model/calendar_date.dart';

/// A pilot-held document the currency engine can check the validity of — a
/// medical certificate, a class or type rating, an instrument rating.
///
/// Deliberately minimal and decoupled from the real pilot-record model
/// (`Licence`, `MedicalCertificate` — M3's PR3): this is the stable shape
/// [CurrencyRuleEvaluator] depends on, so the engine (#42) can be built and
/// tested before the concrete pilot-record model exists. PR3 projects real
/// held ratings and medical certificates into [HeldRecord]s rather than the
/// evaluator depending on those models directly — the same reason
/// `ProjectionResult` is a named-quantity map instead of per-jurisdiction
/// fields (see `derived_quantity.dart`).
///
/// [validUntil] is resolved ahead of time — by whichever primitive computes
/// an EASA medical's age-dependent duration, for instance — not recomputed
/// here. The evaluator only ever asks "is this date within the stored
/// range", never "how long is this class of document valid for": that
/// question is real logic and belongs in a primitive, per CLAUDE.md's
/// "declarative stops" rule.
class HeldRecord {
  const HeldRecord({
    required this.kind,
    required this.validFrom,
    this.validUntil,
  });

  /// Identifies which kind of document this is, e.g. `medical_certificate`,
  /// `eu.easa.sep_class_rating`, `us.faa.instrument_rating`. Matched against
  /// a rule's `of` field — see `currency_rule.dart`.
  final String kind;

  final CalendarDate validFrom;

  /// Null means never expires — the FAA endorsement case
  /// (`docs/ratings-and-endorsements.md` §1): "an FAA endorsement is a
  /// permanent record with no expiry that feeds an eligibility check only."
  final CalendarDate? validUntil;

  /// Whether [date] falls within this record's validity, [validFrom]
  /// inclusive.
  bool coversDate(CalendarDate date) {
    if (date < validFrom) {
      return false;
    }
    final until = validUntil;
    return until == null || date <= until;
  }
}
