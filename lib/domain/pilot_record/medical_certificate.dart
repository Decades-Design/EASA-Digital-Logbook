import 'package:freezed_annotation/freezed_annotation.dart';

import '../model/calendar_date.dart';

part 'medical_certificate.freezed.dart';

/// A medical certificate the pilot holds, as issued — class, issuing
/// authority and issue date only.
///
/// Validity is computed, never stored: see
/// `medical_certificate_validity.dart`. The duration depends on the
/// pilot's age at issue and, for EASA, on age bands the certificate can
/// age *into* during its own life (MED.A.045's birthday-crossing case) —
/// storing a `validUntil` here would be exactly the derived-quantity
/// mistake CLAUDE.md rule 1 warns against for `Flight`, one layer up.
///
/// UK Part-MED, the LAPL medical and the UK PMD are deliberately not
/// covered: CLAUDE.md scopes UK CAA as "planned", not current, and
/// `docs/ratings-and-endorsements.md` marks those specific rows ⚠️
/// unverified in any case.
@freezed
abstract class MedicalCertificate with _$MedicalCertificate {
  const factory MedicalCertificate({
    required MedicalCertificateClass certificateClass,

    /// The jurisdiction profile id this certificate was issued under, e.g.
    /// `eu.easa.part-fcl`, `us.faa.part61`.
    required String jurisdictionId,

    required CalendarDate issueDate,
  }) = _MedicalCertificate;
}

enum MedicalCertificateClass {
  easaClass1,
  easaClass2,
  faaFirstClass,
  faaSecondClass,
  faaThirdClass,
}
