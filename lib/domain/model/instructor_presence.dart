import 'package:freezed_annotation/freezed_annotation.dart';

import 'calendar_date.dart';

part 'instructor_presence.freezed.dart';

/// An instructor or examiner aboard, and the facts a projection needs about
/// their presence. Records the arrangement, never the conclusion drawn from it
/// — whether a flight was dual, SPIC or a skill test is derived per
/// jurisdiction (CLAUDE.md rule 1).
///
/// A safety pilot is deliberately *not* an [InstructorCapacity]. CLAUDE.md
/// rule 2 lists "FI/FE/safety pilot" together, but under `§91.109(c)` a safety
/// pilot is a required crewmember in the other control seat, not a person
/// giving instruction. They are an `OtherPilotRole` instead, matching
/// `docs/entry-form.md` §4C.
@freezed
abstract class InstructorPresence with _$InstructorPresence {
  const factory InstructorPresence({
    /// Instructor or examiner. `AMC1 FCL.050(b)(1)(ii)` requires each flight
    /// of instruction to be certified by the instructor responsible, while
    /// skill tests and proficiency checks require column 12 remarks — two
    /// different obligations, so this cannot collapse to "instructor aboard".
    required InstructorCapacity capacity,

    /// Whether the instructor influenced or controlled the flight — the EASA
    /// SPIC discriminator.
    ///
    /// `FCL.010` defines SPIC as a student acting as PIC with an instructor
    /// who **only observes**. So `true` makes the flight dual, not SPIC; the
    /// two are mutually exclusive and cannot be recorded concurrently.
    ///
    /// Unbackfillable — nobody can reconstruct years later whether the
    /// instructor took the controls, so it is asked at entry time even though
    /// only one authority reads it.
    required bool influencedFlight,

    /// The instructor's name. Required by `AMC1 FCL.050` for an SEP/TMG
    /// revalidation refresher and by `§61.51(h)(2)(i)`. Nullable because an
    /// entry may be saved as a draft before the details are to hand.
    String? name,

    /// Licence or certificate number. Required for an EASA countersignature
    /// (`AMC1 FCL.050`) and for an FAA endorsement (`§61.51(h)(2)(ii)`).
    String? credentialNumber,

    /// Certificate expiry. `§61.51(h)(2)(ii)` requires it on an FAA training
    /// endorsement; EASA has no equivalent, so it is routinely null on an
    /// EASA-only flight.
    CalendarDate? credentialExpiry,
  }) = _InstructorPresence;
}

/// The capacity an instructor or examiner aboard was acting in. Two values,
/// not three — a safety pilot is an `OtherPilotRole`.
enum InstructorCapacity {
  /// Giving instruction, or observing an SPIC flight.
  /// `FCL.010`; `AMC1 FCL.050(b)(1)(ii)`.
  flightInstructor,

  /// Conducting a skill test or proficiency check, which `AMC1 FCL.050`
  /// requires to be detailed in column 12.
  flightExaminer,
}
