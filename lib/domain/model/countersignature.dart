import 'package:freezed_annotation/freezed_annotation.dart';

import 'calendar_date.dart';
import 'utc_instant.dart';

part 'countersignature.freezed.dart';

/// Countersignature state, plus who signed.
///
/// The countersignature *workflow* is out of scope; the *data* is not. Rule 2
/// lists countersignature state and signatory identity among the facts that
/// cannot be backfilled — a flight signed in 2023 cannot have its signatory
/// reconstructed in 2027 — so the shape is carried from the first version.
///
/// **Uncountersigned time is not silently anything.** `AMC1 FCL.050` requires
/// the PIC's name and signature on SPIC and PICUS entries, and at least one
/// competent authority (Ireland) treats unsigned PICUS time as unusable. PICUS
/// whose signature is [CountersignatureStatus.pending] or
/// [CountersignatureStatus.refused] is therefore not creditable as PIC, and
/// the projections (#18, #19) must say so with a reason — never silently zero
/// and never silently valid. Both are indistinguishable from a correct answer
/// at the point of use.
///
/// The fields are the union of two shapes: EASA wants name, signature and
/// licence number; an FAA endorsement adds the certificate expiry
/// (`§61.51(h)(2)(ii)`). Storing both keeps an entry made under one authority
/// readable under the other.
@freezed
abstract class Countersignature with _$Countersignature {
  const factory Countersignature({
    /// Where the signature has got to. A fact about the record, not a derived
    /// quantity — the projections read it rather than deciding it.
    required CountersignatureStatus status,

    /// The signatory's name. `AMC1 FCL.050`; `§61.51(h)(2)(i)`.
    String? signatoryName,

    /// The signatory's licence or certificate number. `AMC1 FCL.050` requires
    /// it alongside the signature for PICUS; `§61.51(h)(2)(ii)` for the FAA.
    String? signatoryCredentialNumber,

    /// The signatory's certificate expiry. `§61.51(h)(2)(ii)`; normally null
    /// on an EASA-only entry.
    CalendarDate? signatoryCredentialExpiry,

    /// When it was signed. Null until it actually is — a [pending] entry
    /// carrying a signing timestamp is a contradiction.
    UtcInstant? signedAt,
  }) = _Countersignature;
}

/// How far a countersignature has got. Three states rather than a `bool`,
/// because "asked and not yet signed" and "asked and declined" let a
/// projection explain a non-creditable entry instead of showing a bare zero.
///
/// There is deliberately no `notRequired` value: a null
/// [PilotCapacity.countersignature] already means none is required or
/// expected, which `AMC1 FCL.050` makes the ordinary case — it requires one
/// only for SPIC, PICUS, instruction received, and SEP/TMG revalidation
/// flights. Two ways to say the same thing is how they drift apart.
enum CountersignatureStatus {
  /// Expected and not yet arrived. PICUS in this state is not creditable.
  pending,

  /// Signed. [Countersignature.signedAt] and [Countersignature.signatoryName]
  /// are expected to be present.
  signed,

  /// The signatory declined. Distinct from [pending] because it is terminal
  /// and because it is evidence: the entry stands as the pilot recorded it.
  refused,
}
