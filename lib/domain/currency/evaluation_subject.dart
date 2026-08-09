import '../model/aircraft.dart';
import '../repository/flight_read_repository.dart';
import 'held_record.dart';

/// Everything [CurrencyRuleEvaluator.evaluate] needs about one pilot to
/// evaluate one [CurrencyRule] against them — a flight set plus held
/// documents, never just "a flight set" (#42's issue text says that, but a
/// document-validity or held-rating requirement has no flights in it at
/// all).
///
/// Hand-written, not `@freezed`: constructed fresh for each evaluation call
/// from data a repository already owns, with no need for `copyWith` or
/// value equality — the same reasoning as `PrimitiveRegistry`.
class EvaluationSubject {
  const EvaluationSubject({
    required this.flights,
    this.referenceAircraft,
    this.heldRecords = const [],
  });

  /// This pilot's flights, each paired with the aircraft it names — needed
  /// so [FlightCondition.aircraftMatch] can compare against
  /// [referenceAircraft].
  final List<FlightRecord> flights;

  /// The aircraft a recency question is being asked about, e.g. "am I
  /// current to carry passengers in this aircraft" — null when the rule
  /// being evaluated has no [FlightCondition.aircraftMatch] condition and so
  /// never reads it.
  final Aircraft? referenceAircraft;

  /// Medical certificates, ratings and other held documents — see
  /// `held_record.dart` for why this is the minimal, decoupled shape rather
  /// than the real pilot-record model.
  final List<HeldRecord> heldRecords;
}
