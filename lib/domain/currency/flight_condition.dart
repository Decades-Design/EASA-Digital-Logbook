import 'package:freezed_annotation/freezed_annotation.dart';

part 'flight_condition.freezed.dart';

/// A filter on which flights contribute toward a [Requirement] — #40's
/// "conditions on the flights that count: aircraft class, day/night,
/// full-stop landings, aircraft type match", grown by #47 with two more:
/// [capacity] (FCL.740.A's "6 hours as PIC") and [instructorAboard]
/// (its training-flight requirement). A new kind is still a schema change,
/// not something a rule author should be able to invent inline.
///
/// One flat class with a [kind] discriminator, matching this codebase's
/// existing union style (see `Countersignature`, `CapacityFilter`) rather
/// than a sealed class — there is no precedent for sealed unions here and
/// introducing the first one for a growing-but-still-small variant count
/// is not worth the inconsistency.
@freezed
abstract class FlightCondition with _$FlightCondition {
  const factory FlightCondition({
    required ConditionKind kind,
    DayNight? dayNight,
    LandingType? landingType,
    AircraftMatch? aircraftMatch,
    CapacityRequirement? capacity,
  }) = _FlightCondition;

  factory FlightCondition.dayNight(DayNight value) =>
      FlightCondition(kind: ConditionKind.dayNight, dayNight: value);

  factory FlightCondition.landingType(LandingType value) =>
      FlightCondition(kind: ConditionKind.landingType, landingType: value);

  factory FlightCondition.aircraftMatch(AircraftMatch value) =>
      FlightCondition(kind: ConditionKind.aircraftMatch, aircraftMatch: value);

  factory FlightCondition.capacity(CapacityRequirement value) =>
      FlightCondition(kind: ConditionKind.capacity, capacity: value);

  /// Whether an instructor was aboard — `PilotCapacity.instructor != null`,
  /// regardless of [InstructorCapacity]. No extra value: unlike [capacity],
  /// this condition is a pure presence gate.
  factory FlightCondition.instructorAboard() =>
      const FlightCondition(kind: ConditionKind.instructorAboard);
}

enum ConditionKind {
  dayNight,
  landingType,
  aircraftMatch,
  capacity,
  instructorAboard,
}

/// A raw fact on `PilotCapacity` a [FlightCondition.capacity] condition can
/// gate a flight on. Only [commandAuthority] exists so far — the one
/// FCL.740.A needs ("6 hours as PIC") — grown when another rule needs
/// another one.
enum CapacityRequirement { commandAuthority }

enum DayNight { day, night }

enum LandingType { fullStop, touchAndGo }

/// How closely the flown aircraft must match the aircraft the recency
/// question is being asked about (`EvaluationSubject.referenceAircraft`).
///
/// `sameType` compares [Aircraft.typeRatingDesignator] when the reference
/// aircraft has one, else [Aircraft.icaoTypeDesignator]; `sameClass`
/// compares engine type, engine count and operating surface — the same
/// tuple that determines an EASA class rating (SEP(land), MEP(sea), ...).
///
/// [classOrTypeIfRequired] is `§61.57(a)`'s own wording: "the same category
/// and class of aircraft (if a class rating is required) and, if the
/// aircraft is type-rated, ... the same type of aircraft" — same class
/// ordinarily, but same *type* when [Aircraft.typeRatingDesignator] is set,
/// since a type is always a subset of its class. A distinct value rather
/// than reusing [sameType]/[sameClass]: which one applies depends on the
/// *reference* aircraft, not on a rule author's static choice, and only
/// `§61.57(a)` needs that.
enum AircraftMatch {
  sameType,
  sameClass,
  sameTypeOrClass,
  classOrTypeIfRequired,
}
