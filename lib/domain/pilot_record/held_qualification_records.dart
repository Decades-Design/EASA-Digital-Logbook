import '../currency/held_record.dart';
import '../currency/rule_window.dart';
import '../model/calendar_date.dart';
import 'held_aircraft_qualification.dart';
import 'held_rating.dart';

/// [HeldAircraftQualification] projected to the generic [HeldRecord] shape
/// the currency engine consumes — #52. Never expires, on either authority
/// (see the class dartdoc), so this is a straight field copy with no
/// computation at all.
HeldRecord heldAircraftQualificationHeldRecord(HeldAircraftQualification held) {
  return HeldRecord(
    kind:
        'aircraft_qualification.${held.jurisdictionId}.'
        '${held.qualification.name}',
    validFrom: held.dateGranted,
    validUntil: null,
  );
}

/// FCL.055's fixed per-level validity: Level 6 never expires, Level 5 is
/// valid 6 years, Level 4 is valid 4 years — EASA's implemented figure,
/// not ICAO Doc 9835's own 3-year recommendation for Level 4, which EASA
/// did not adopt as-is.
const Map<int, int> _languageProficiencyValidityMonths = {5: 72, 4: 48};

/// [HeldRating] projected to the generic [HeldRecord] shape the currency
/// engine consumes — #52.
///
/// Every kind but [HeldRatingKind.languageProficiency] passes
/// [HeldRating.expiryDate] straight through — it is already the raw fact
/// the licence states, not something to recompute (see the class
/// dartdoc). Language proficiency is the one case with real logic: the
/// duration is fixed per level, so it is worth computing from
/// [HeldRating.languageProficiencyLevel] rather than trusting a
/// hand-entered date to match FCL.055 exactly.
HeldRecord heldRatingHeldRecord(HeldRating held) {
  return HeldRecord(
    kind: 'rating.${held.jurisdictionId}.${held.kind.name}.${held.designator}',
    validFrom: held.issueDate,
    validUntil: held.kind == HeldRatingKind.languageProficiency
        ? _languageProficiencyExpiry(
            held.issueDate,
            held.languageProficiencyLevel,
          )
        : held.expiryDate,
  );
}

CalendarDate? _languageProficiencyExpiry(CalendarDate issueDate, int? level) {
  final months = _languageProficiencyValidityMonths[level];
  if (months == null) {
    return null; // Level 6, or an unrecognised level -- never expires.
  }
  return RuleWindow.calendarMonths(months).expiryFrom(issueDate);
}
