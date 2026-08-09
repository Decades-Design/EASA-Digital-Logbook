import 'package:freezed_annotation/freezed_annotation.dart';

import '../model/aircraft.dart';
import '../model/calendar_date.dart';
import 'held_aircraft_qualification.dart';
import 'held_qualification_records.dart';
import 'held_rating.dart';

part 'qualification_gap.freezed.dart';

/// One qualification [aircraft] requires under a jurisdiction, that the
/// pilot did not hold on the evaluation date — [qualificationGaps] (#105).
///
/// Flat class with a [kind] discriminator, matching [FlightCondition]'s
/// style: an [AircraftQualification] and a type-rating designator are
/// different shapes of "missing", not variants worth a sealed hierarchy.
@freezed
abstract class QualificationGap with _$QualificationGap {
  const factory QualificationGap({
    required QualificationGapKind kind,
    AircraftQualification? aircraftQualification,
    String? typeRatingDesignator,
  }) = _QualificationGap;

  factory QualificationGap.aircraftQualification(AircraftQualification value) =>
      QualificationGap(
        kind: QualificationGapKind.aircraftQualification,
        aircraftQualification: value,
      );

  factory QualificationGap.typeRating(String designator) => QualificationGap(
    kind: QualificationGapKind.typeRating,
    typeRatingDesignator: designator,
  );
}

enum QualificationGapKind { aircraftQualification, typeRating }

/// Qualifications [aircraft] requires under [jurisdictionId] that are not
/// covered by [heldAircraftQualifications]/[heldRatings] on [asOf] —
/// `docs/ratings-and-endorsements.md` §8's `required_qualifications` vs
/// `held_qualifications` comparison.
///
/// Two independently-required things get compared:
///
/// - [Aircraft.requiredQualifications]'s declared list for [jurisdictionId]
///   — skipped entirely when the key is absent. #104's absent-vs-empty
///   distinction: a missing key means the aircraft was never set up for
///   this authority, which is a "we don't know" the caller must not read
///   as "requires nothing" — silence, not a warning, is the only honest
///   response.
/// - [Aircraft.typeRatingDesignator], checked whenever it is set,
///   independently of whether the qualification list above has been set
///   up. It is a plain fact about the airframe rather than a declared
///   list, so there is no "not set up" state for it to be missing from.
///
/// A pure query, never blocking anything itself — the caller (#58's entry
/// form, once built) surfaces the result as a non-blocking warning, per
/// §8: "the pilot may be logging a flight flown under a different licence,
/// on a permit aircraft, or under an exemption the app doesn't model."
///
/// Scoped to a single [jurisdictionId] on purpose. §8's night-rating
/// example — an EASA-primary pilot legally flying at night on an FAA
/// ticket with no EASA night rating — requires evaluating each held
/// licence's jurisdiction independently rather than against the primary
/// jurisdiction only; the caller runs this once per held licence, not this
/// function fanning out internally, since only the caller knows which
/// licences the pilot holds.
List<QualificationGap> qualificationGaps({
  required Aircraft aircraft,
  required String jurisdictionId,
  required List<HeldAircraftQualification> heldAircraftQualifications,
  required List<HeldRating> heldRatings,
  required CalendarDate asOf,
}) {
  final gaps = <QualificationGap>[];

  final required = aircraft.requiredQualifications[jurisdictionId];
  if (required != null) {
    for (final qualification in required) {
      final held = heldAircraftQualifications.any(
        (h) =>
            h.qualification == qualification &&
            h.jurisdictionId == jurisdictionId &&
            heldAircraftQualificationHeldRecord(h).coversDate(asOf),
      );
      if (!held) {
        gaps.add(QualificationGap.aircraftQualification(qualification));
      }
    }
  }

  final typeRating = aircraft.typeRatingDesignator;
  if (typeRating != null) {
    final held = heldRatings.any(
      (h) =>
          h.kind == HeldRatingKind.typeRating &&
          h.designator == typeRating &&
          h.jurisdictionId == jurisdictionId &&
          heldRatingHeldRecord(h).coversDate(asOf),
    );
    if (!held) {
      gaps.add(QualificationGap.typeRating(typeRating));
    }
  }

  return gaps;
}
