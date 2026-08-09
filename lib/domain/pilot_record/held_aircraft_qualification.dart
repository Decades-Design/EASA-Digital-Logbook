import 'package:freezed_annotation/freezed_annotation.dart';

import '../model/aircraft.dart';
import '../model/calendar_date.dart';

part 'held_aircraft_qualification.freezed.dart';

/// One aircraft-feature qualification the pilot holds — EASA differences
/// training or an FAA `§61.31` endorsement — #52.
///
/// Keyed on [AircraftQualification] directly, the same enum
/// `Aircraft.requiredQualifications` uses, so a held record and a
/// required one compare directly with no name-mapping layer between them
/// (#52's own acceptance criterion, and #105's whole premise).
///
/// **No expiry field, on either authority.** EASA differences training and
/// FAA `§61.31` endorsements are *both* non-expiring
/// (`docs/ratings-and-endorsements.md` §1, §3) — unlike [HeldRating], which
/// genuinely needs one on the EASA side. Forcing a nullable field that is
/// always null for every value this type can hold would be the kind of
/// field a reader has to double-check is never populated; leaving it off
/// entirely says the same thing in the type itself.
///
/// [signatoryName]/[signatoryCredentialNumber]/[signedOn] mirror
/// `Countersignature`'s identity fields, deliberately without its
/// [CountersignatureStatus] workflow: this is a self-attested record the
/// pilot enters from their own logbook, not an interactive instructor
/// sign-in flow — CLAUDE.md lists that workflow under "Deliberately out of
/// scope for now".
@freezed
abstract class HeldAircraftQualification with _$HeldAircraftQualification {
  const factory HeldAircraftQualification({
    required AircraftQualification qualification,

    /// The jurisdiction profile id this record was granted under, e.g.
    /// `eu.easa.part-fcl`, `us.faa.part61`.
    required String jurisdictionId,

    required CalendarDate dateGranted,

    String? signatoryName,
    String? signatoryCredentialNumber,
  }) = _HeldAircraftQualification;
}
