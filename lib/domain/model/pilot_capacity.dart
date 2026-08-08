import 'package:freezed_annotation/freezed_annotation.dart';

import 'countersignature.dart';
import 'flight_duration.dart';
import 'instructor_presence.dart';

part 'pilot_capacity.freezed.dart';

/// The capacity in which the logbook holder operated on a flight, as
/// independent raw facts.
///
/// **Not a role enum, deliberately.** There is no `pic` / `spic` / `picus`
/// value here. SPIC and PICUS are EASA conclusions: `FCL.010` makes PICUS turn
/// on whether the PIC had to intervene, and `AMC1 FCL.050` makes it turn
/// additionally on a countersignature that arrives after the flight. A stored
/// role would be correct on Tuesday and wrong on Thursday — and it would be
/// *EASA's* conclusion, while an FAA reading needs [commandAuthority] and
/// [soleManipulator] separately. Neither survives being collapsed into the
/// word "PICUS". `docs/entry-form.md` §4C: capture the arrangement, not the
/// conclusion.
///
/// Every field here is unbackfillable (CLAUDE.md rule 2). Each exists because
/// at least one authority's numbers are unrecoverable without it —
/// `docs/jurisdiction-matrix.md` §9 is the list.
///
/// Deliberately elsewhere: `carryingPassengers` and crew identity are facts
/// about the flight, not this pilot's capacity, and land on `Flight` (#11);
/// `aircraftRequiresMultiCrew` is a type-certificate attribute on `Aircraft`
/// (#12) that pre-fills [multiPilotOperation] without replacing it.
@freezed
abstract class PilotCapacity with _$PilotCapacity {
  const factory PilotCapacity({
    /// Whether this pilot held command authority. `FCL.010`; `§91.3`.
    ///
    /// Independent of [soleManipulator] on purpose: under the FAA both pilots
    /// aboard can log PIC for the same hour, one under `§91.3` and one as sole
    /// manipulator under `§61.51(e)(1)(i)`. That is impossible under EASA, and
    /// merging the two flags destroys the distinction permanently.
    required bool commandAuthority,

    /// Whether this pilot was sole manipulator of the controls.
    /// `§61.51(e)(1)(i)` — the FAA PIC trigger. EASA has no general
    /// sole-manipulator concept, so the same hand-flying hour is not PIC time.
    ///
    /// Whether the pilot was *rated* for the aircraft is a licence fact; the
    /// FAA projection (#19) resolves it from the licences held on the date.
    /// See [manipulationTime] for the partial case.
    required bool soleManipulator,

    /// Whether this pilot was the sole occupant. `§61.51(d)` (solo) and
    /// `§61.51(e)(4)(i)` (student PIC) both test this, and both are binary —
    /// which is why no headcount is stored anywhere.
    required bool soleOccupant,

    /// Whether the flight was a multi-pilot operation. `AMC1 FCL.050` splits
    /// single-pilot (column 5) from multi-pilot (column 6) time, so an EASA
    /// logbook cannot be printed without it; `§61.51(f)` gates SIC time on it.
    ///
    /// Distinct from the aircraft's type-certificate attribute: an operation
    /// can require two pilots by regulation in a single-pilot aircraft
    /// (`docs/entry-form.md` §4C).
    required bool multiPilotOperation,

    /// Whether this pilot was the authorised instructor. `AMC1 FCL.050`
    /// column 11 records instructor time as its own function; `§61.51(e)(3)`
    /// lets a CFI log PIC for instruction given when rated to act as PIC.
    ///
    /// The mirror of [instructor]: this flag says *this* pilot instructed,
    /// [instructor] says somebody else did.
    required bool actingAsInstructor,

    /// Whether this pilot was the examiner. `AMC1 FCL.050` requires the
    /// details of all skill tests and proficiency checks in column 12, so the
    /// examiner case produces a mandatory remark the instructor case does not.
    required bool actingAsExaminer,

    /// Whether this pilot claimed the flight as PICUS. `FCL.010`.
    ///
    /// The *claim* is the pilot's assertion and so a raw fact. Whether it is
    /// creditable is a projection output depending additionally on
    /// [picInterventionNotRequired] and [countersignature]. Up to 500 hours
    /// counts toward the ATPL(A) PIC requirement under `FCL.510(a)(2)`; the
    /// FAA has no analogue, so this is inert under the FAA projection.
    required bool picusClaimed,

    /// Whether the PIC's intervention in the interest of safety was not
    /// required — the substantive PICUS condition under `FCL.010`.
    ///
    /// Affirmed at entry time because nobody can reconstruct it later. Carries
    /// no meaning unless [picusClaimed] is also true.
    required bool picInterventionNotRequired,

    /// Time spent manipulating the controls, when that was less than the whole
    /// flight. What makes a mid-flight takeover loggable under
    /// `§61.51(e)(1)(i)`; a bare boolean throws the figure away permanently.
    ///
    /// Scoped by [soleManipulator]:
    /// - true + null — manipulated throughout (the normal case).
    /// - false + null — did not manipulate at all.
    /// - false + value — manipulated for exactly that long.
    /// - true + value — contradictory. `Flight` (#11) validates it, since only
    ///   it knows the block time this must not exceed.
    FlightDuration? manipulationTime,

    /// The instructor or examiner aboard; null asserts nobody was instructing.
    /// `FCL.010` and `§61.51(h)(1)` both require a *properly authorised*
    /// instructor before the time counts as instruction.
    ///
    /// [InstructorPresence.influencedFlight] is the SPIC/dual discriminator —
    /// the single most consequential bit in this model under EASA.
    InstructorPresence? instructor,

    /// The role of another pilot aboard who was not an instructor; null when
    /// none was. Describes the **other** pilot — this pilot's own standing is
    /// carried by [commandAuthority], [multiPilotOperation] and
    /// [soleManipulator]. `docs/entry-form.md` §4C asks who was in command and
    /// who was flying as two separate questions, because they are two.
    OtherPilotRole? otherPilotRole,

    /// Countersignature state; null when none is required or expected.
    /// `AMC1 FCL.050` requires it for SPIC and PICUS entries and for each
    /// flight of instruction received (`AMC1 FCL.050(b)(1)(ii)`);
    /// `§61.51(h)(2)` sets the FAA endorsement requirements.
    Countersignature? countersignature,
  }) = _PilotCapacity;
}

/// The role of another pilot aboard who was not an instructor. Always
/// describes the *other* pilot.
enum OtherPilotRole {
  /// Required to be there by the type certificate or the operating rules.
  /// The EASA co-pilot case (`AMC1 FCL.050` column 11, multi-pilot only) and
  /// the FAA SIC case (`§61.51(f)`). Required crew are not passengers for
  /// `FCL.060(b)(1)` or `§61.57(a)`.
  requiredCrew,

  /// Aboard and qualified, but not required.
  ///
  /// EASA records nothing for a pilot who is neither required crew nor in
  /// command, whatever they did (`docs/jurisdiction-matrix.md` §4). Whether
  /// such a pilot counts as a passenger under EASA is unresolved — which is
  /// why the role is stored and the question is not forced.
  notRequiredCrew,

  /// An FAA safety pilot for simulated instrument flight. `§91.109(c)` makes
  /// them required crew; `§61.51(b)(1)(v)` makes their name mandatory logbook
  /// content. EASA has no equivalent, so this is inert under the EASA
  /// projection — stored anyway, because a flight logged under one licence may
  /// need reading under the other in ten years.
  safetyPilot,
}
