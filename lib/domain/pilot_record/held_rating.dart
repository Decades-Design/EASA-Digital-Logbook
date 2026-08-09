import 'package:freezed_annotation/freezed_annotation.dart';

import '../model/calendar_date.dart';

part 'held_rating.freezed.dart';

/// One privilege rating or certificate the pilot holds — a class or type
/// rating, an instrument rating, an instructor certificate, or a language
/// proficiency endorsement — #52.
///
/// **[expiryDate] is a stored raw fact, not a computed one.** Unlike
/// medical certificate validity (`medical_certificate_validity.dart`),
/// which genuinely depends on age-band logic worth computing, a rating's
/// expiry is simply what the issuing authority printed on the licence at
/// the last issue or revalidation — the pilot transcribes it, the same way
/// they transcribe an aircraft's registration. `docs/ratings-and-
/// endorsements.md` §1, §6: EASA-side records carry that expiry and gate
/// legality on it (lapsed = grounded); FAA-side ratings — type rating,
/// instrument rating — never expire and [expiryDate] stays null for them,
/// never a forced date. [languageProficiencyLevel] 6 is the one EASA-side
/// exception that also never expires; see [heldRatingHeldRecord] for the
/// one case ([HeldRatingKind.languageProficiency]) where a duration *is*
/// computed, from `FCL.055`'s fixed per-level periods.
///
/// [jurisdictionId] is what keeps two licences' rating sets independent —
/// an EASA instrument rating and an FAA instrument rating are two
/// [HeldRating]s with the same [kind] and different [jurisdictionId]s, and
/// nothing about this type lets one satisfy a currency check scoped to the
/// other (#52's "independent rating sets that do not interfere").
@freezed
abstract class HeldRating with _$HeldRating {
  const factory HeldRating({
    required HeldRatingKind kind,

    /// Identifies which specific rating within [kind], e.g. `SEP(land)`,
    /// `MEP(land)` for [HeldRatingKind.classRating]; the type-certificate
    /// designator for [HeldRatingKind.typeRating] — deliberately the same
    /// string space as `Aircraft.typeRatingDesignator`, so two
    /// registrations of one type resolve to the one held record (#52); a
    /// certificate identifier such as `CFI` for
    /// [HeldRatingKind.instructorCertificate]; a language name such as
    /// `english` for [HeldRatingKind.languageProficiency].
    required String designator,

    required String jurisdictionId,

    required CalendarDate issueDate,

    /// Null means never expires — the ordinary FAA case, and the EASA
    /// language-proficiency Level 6 case ([languageProficiencyLevel] `6`).
    CalendarDate? expiryDate,

    /// Set only when [kind] is [HeldRatingKind.languageProficiency] — the
    /// ICAO/`FCL.055` level (4, 5 or 6) this record certifies.
    int? languageProficiencyLevel,
  }) = _HeldRating;
}

enum HeldRatingKind {
  classRating,
  typeRating,
  instrumentRating,
  instructorCertificate,
  languageProficiency,
}
