import 'package:freezed_annotation/freezed_annotation.dart';

part 'flight_condition.freezed.dart';

/// A filter on which flights contribute toward a [Requirement] — #40's
/// "conditions on the flights that count: aircraft class, day/night,
/// full-stop landings, aircraft type match". Exactly these three kinds and
/// no more: they are the complete list #40's acceptance criteria name: a new
/// kind is a schema change (#40), not something a rule author should be able
/// to invent inline.
///
/// One flat class with a [kind] discriminator, matching this codebase's
/// existing union style (see `Countersignature`, `CapacityFilter`) rather
/// than a sealed class — there is no precedent for sealed unions here and
/// introducing the first one for a three-variant type is not worth the
/// inconsistency.
@freezed
abstract class FlightCondition with _$FlightCondition {
  const factory FlightCondition({
    required ConditionKind kind,
    DayNight? dayNight,
    LandingType? landingType,
    AircraftMatch? aircraftMatch,
  }) = _FlightCondition;

  factory FlightCondition.dayNight(DayNight value) =>
      FlightCondition(kind: ConditionKind.dayNight, dayNight: value);

  factory FlightCondition.landingType(LandingType value) =>
      FlightCondition(kind: ConditionKind.landingType, landingType: value);

  factory FlightCondition.aircraftMatch(AircraftMatch value) =>
      FlightCondition(kind: ConditionKind.aircraftMatch, aircraftMatch: value);
}

enum ConditionKind { dayNight, landingType, aircraftMatch }

enum DayNight { day, night }

enum LandingType { fullStop, touchAndGo }

/// How closely the flown aircraft must match the aircraft the recency
/// question is being asked about (`EvaluationSubject.referenceAircraft`).
///
/// `sameType` compares [Aircraft.typeRatingDesignator] when the reference
/// aircraft has one, else [Aircraft.icaoTypeDesignator]; `sameClass`
/// compares engine type, engine count and operating surface — the same
/// tuple that determines an EASA class rating (SEP(land), MEP(sea), ...).
enum AircraftMatch { sameType, sameClass, sameTypeOrClass }
