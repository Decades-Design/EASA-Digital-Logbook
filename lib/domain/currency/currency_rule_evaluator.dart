import '../model/aircraft.dart';
import '../model/calendar_date.dart';
import '../model/flight.dart';
import '../model/flight_duration.dart';
import '../repository/flight_read_repository.dart';
import 'currency_rule.dart';
import 'evaluation_subject.dart';
import 'flight_condition.dart';
import 'held_record.dart';
import 'rule_result.dart';

/// Evaluates any schema-conformant [CurrencyRule] against an
/// [EvaluationSubject] with no rule-specific code — #42. If a new
/// jurisdiction rule needs a change here rather than just a new
/// [CurrencyRule] value, the schema (#40) is missing an expression; see
/// that issue's own acceptance criterion.
///
/// Stateless and deterministic: the only inputs to [evaluateRequirement]
/// are its three arguments, so the same call always produces the same
/// [RuleResult] — #42's "deterministic given the same inputs and evaluation
/// date".
class CurrencyRuleEvaluator {
  const CurrencyRuleEvaluator();

  /// Evaluates [rule] as a whole, labelling the result with its id and
  /// citation for display.
  CurrencyRuleEvaluation evaluateRule(
    CurrencyRule rule,
    EvaluationSubject subject,
    CalendarDate asOf,
  ) => CurrencyRuleEvaluation(
    ruleId: rule.id,
    citation: rule.citation,
    result: evaluateRequirement(rule.requirement, subject, asOf),
  );

  /// Evaluates one [Requirement] node, recursing into [Requirement.of] for
  /// [RequirementKind.allOf]/[RequirementKind.anyOf].
  RuleResult evaluateRequirement(
    Requirement requirement,
    EvaluationSubject subject,
    CalendarDate asOf,
  ) {
    switch (requirement.kind) {
      case RequirementKind.flightEventCount:
        return _evaluateFlightEventCount(requirement, subject, asOf);
      case RequirementKind.flightEventHours:
        return _evaluateFlightEventHours(requirement, subject, asOf);
      case RequirementKind.heldRecordCurrentlyValid:
        return _evaluateHeldRecordCurrentlyValid(requirement, subject, asOf);
      case RequirementKind.allOf:
        return _evaluateAllOf(requirement, subject, asOf);
      case RequirementKind.anyOf:
        return _evaluateAnyOf(requirement, subject, asOf);
    }
  }

  RuleResult _evaluateFlightEventCount(
    Requirement requirement,
    EvaluationSubject subject,
    CalendarDate asOf,
  ) {
    final window = requirement.window!;
    final range = window.rangeEndingAt(asOf, heldRecords: subject.heldRecords);

    final occurrences = <_Occurrence<int>>[];
    for (final record in subject.flights) {
      if (!_passesAircraftMatch(
        record,
        requirement.conditions,
        subject.referenceAircraft,
      )) {
        continue;
      }
      final date = CalendarDate.fromUtcInstant(record.flight.offBlocks);
      if (date < range.start || date > range.end) {
        continue;
      }
      final weight = _eventCount(
        record.flight,
        requirement.event!,
        requirement.conditions,
      );
      if (weight > 0) {
        occurrences.add(_Occurrence(record.id, date, weight));
      }
    }
    occurrences.sort((a, b) => b.date.compareTo(a.date));

    var cumulative = 0;
    final contributingIds = <String>[];
    CalendarDate? anchorDate;
    for (final occurrence in occurrences) {
      if (cumulative >= requirement.count!) {
        break;
      }
      cumulative += occurrence.weight;
      contributingIds.add(occurrence.flightId);
      anchorDate = occurrence.date;
    }

    final satisfied = cumulative >= requirement.count!;
    final label = _describeEvent(requirement.event!, requirement.conditions);
    return RuleResult(
      satisfied: satisfied,
      explanation: satisfied
          ? '$cumulative of ${requirement.count} $label within the window'
          : '$cumulative of ${requirement.count} $label; needs '
                '${requirement.count! - cumulative} more',
      expiresOn: satisfied ? window.expiryFrom(anchorDate!) : null,
      contributingFlightIds: contributingIds,
    );
  }

  RuleResult _evaluateFlightEventHours(
    Requirement requirement,
    EvaluationSubject subject,
    CalendarDate asOf,
  ) {
    final window = requirement.window!;
    final range = window.rangeEndingAt(asOf, heldRecords: subject.heldRecords);

    final occurrences = <_Occurrence<FlightDuration>>[];
    for (final record in subject.flights) {
      if (!_passesAircraftMatch(
        record,
        requirement.conditions,
        subject.referenceAircraft,
      )) {
        continue;
      }
      final date = CalendarDate.fromUtcInstant(record.flight.offBlocks);
      if (date < range.start || date > range.end) {
        continue;
      }
      final qualifies =
          _eventCount(
            record.flight,
            requirement.event!,
            requirement.conditions,
          ) >
          0;
      if (!qualifies) {
        continue;
      }
      final blockTime = record.flight.onBlocks.difference(
        record.flight.offBlocks,
      );
      occurrences.add(
        _Occurrence(record.id, date, FlightDuration(blockTime.inMinutes)),
      );
    }
    occurrences.sort((a, b) => b.date.compareTo(a.date));

    var cumulative = FlightDuration.zero;
    final contributingIds = <String>[];
    CalendarDate? anchorDate;
    for (final occurrence in occurrences) {
      if (cumulative >= requirement.hours!) {
        break;
      }
      cumulative += occurrence.weight;
      contributingIds.add(occurrence.flightId);
      anchorDate = occurrence.date;
    }

    final satisfied = cumulative >= requirement.hours!;
    final label = _describeEvent(requirement.event!, requirement.conditions);
    return RuleResult(
      satisfied: satisfied,
      explanation: satisfied
          ? '${cumulative.toDecimalHours()} of '
                '${requirement.hours!.toDecimalHours()} hours ($label flights) '
                'within the window'
          : '${cumulative.toDecimalHours()} of '
                '${requirement.hours!.toDecimalHours()} hours ($label flights); '
                'needs ${(requirement.hours! - cumulative).toDecimalHours()} more',
      expiresOn: satisfied ? window.expiryFrom(anchorDate!) : null,
      contributingFlightIds: contributingIds,
    );
  }

  RuleResult _evaluateHeldRecordCurrentlyValid(
    Requirement requirement,
    EvaluationSubject subject,
    CalendarDate asOf,
  ) {
    final kind = requirement.heldRecordKind!;
    HeldRecord? covering;
    for (final record in subject.heldRecords) {
      if (record.kind == kind && record.coversDate(asOf)) {
        covering = record;
        break;
      }
    }
    return RuleResult(
      satisfied: covering != null,
      explanation: covering == null
          ? 'No currently-valid "$kind" held'
          : 'Currently-valid "$kind" held'
                '${covering.validUntil != null ? ', expires ${covering.validUntil}' : ''}',
      expiresOn: covering?.validUntil,
    );
  }

  RuleResult _evaluateAllOf(
    Requirement requirement,
    EvaluationSubject subject,
    CalendarDate asOf,
  ) {
    final components = [
      for (final sub in requirement.of) evaluateRequirement(sub, subject, asOf),
    ];
    final satisfied = components.every((c) => c.satisfied);

    // Lapses at the earliest of its components' expiries — the first
    // component to lapse breaks the whole conjunction.
    CalendarDate? expiresOn;
    if (satisfied) {
      for (final component in components) {
        final componentExpiry = component.expiresOn;
        if (componentExpiry != null &&
            (expiresOn == null || componentExpiry < expiresOn)) {
          expiresOn = componentExpiry;
        }
      }
    }

    return RuleResult(
      satisfied: satisfied,
      explanation: satisfied
          ? 'All ${components.length} requirements met'
          : '${components.where((c) => c.satisfied).length} of '
                '${components.length} requirements met',
      expiresOn: expiresOn,
      contributingFlightIds: _mergedContributingIds(components),
      components: components,
    );
  }

  RuleResult _evaluateAnyOf(
    Requirement requirement,
    EvaluationSubject subject,
    CalendarDate asOf,
  ) {
    final components = [
      for (final sub in requirement.of) evaluateRequirement(sub, subject, asOf),
    ];
    final satisfied = components.any((c) => c.satisfied);

    // The most generous satisfied alternative decides when the whole
    // disjunction lapses.
    CalendarDate? expiresOn;
    for (final component in components) {
      final componentExpiry = component.expiresOn;
      if (component.satisfied &&
          componentExpiry != null &&
          (expiresOn == null || componentExpiry > expiresOn)) {
        expiresOn = componentExpiry;
      }
    }

    return RuleResult(
      satisfied: satisfied,
      explanation: satisfied
          ? 'Satisfied by at least one of ${components.length} alternatives'
          : 'None of ${components.length} alternatives satisfied',
      expiresOn: expiresOn,
      contributingFlightIds: _mergedContributingIds(components),
      components: components,
    );
  }

  List<String> _mergedContributingIds(List<RuleResult> components) {
    final ids = <String>{};
    for (final component in components) {
      ids.addAll(component.contributingFlightIds);
    }
    return ids.toList();
  }
}

class _Occurrence<W> {
  const _Occurrence(this.flightId, this.date, this.weight);

  final String flightId;
  final CalendarDate date;
  final W weight;
}

/// The count [event], narrowed by [conditions], contributes from [flight] —
/// e.g. `landings` narrowed to [DayNight.night] and [LandingType.fullStop]
/// reads only [CircuitCounts.nightFullStop].
int _eventCount(
  Flight flight,
  CountableFlightEvent event,
  List<FlightCondition> conditions,
) {
  switch (event) {
    case CountableFlightEvent.landings:
      return _circuitCount(flight.landings, conditions);
    case CountableFlightEvent.takeoffs:
      return _circuitCount(flight.takeoffs, conditions);
    case CountableFlightEvent.approaches:
      var total = 0;
      for (final approach in flight.approaches) {
        total += approach.count;
      }
      return total;
    case CountableFlightEvent.holdingProcedures:
      return flight.holdingProceduresCount;
    case CountableFlightEvent.trackingPerformed:
      return flight.trackingPerformed ? 1 : 0;
    case CountableFlightEvent.faaFlightReview:
      return flight.alternativeComplianceEvents.contains(
            AlternativeComplianceEvent.faaFlightReview,
          )
          ? 1
          : 0;
    case CountableFlightEvent.faaInstrumentProficiencyCheck:
      return flight.alternativeComplianceEvents.contains(
            AlternativeComplianceEvent.faaInstrumentProficiencyCheck,
          )
          ? 1
          : 0;
    case CountableFlightEvent.easaClassRatingProficiencyCheck:
      return flight.alternativeComplianceEvents.contains(
            AlternativeComplianceEvent.easaClassRatingProficiencyCheck,
          )
          ? 1
          : 0;
  }
}

int _circuitCount(CircuitCounts counts, List<FlightCondition> conditions) {
  DayNight? dayNight;
  LandingType? landingType;
  for (final condition in conditions) {
    switch (condition.kind) {
      case ConditionKind.dayNight:
        dayNight = condition.dayNight;
      case ConditionKind.landingType:
        landingType = condition.landingType;
      case ConditionKind.aircraftMatch:
        break; // Applied at the flight-filter level, not here.
    }
  }

  final includeDay = dayNight == null || dayNight == DayNight.day;
  final includeNight = dayNight == null || dayNight == DayNight.night;
  final includeFullStop =
      landingType == null || landingType == LandingType.fullStop;
  final includeTouchAndGo =
      landingType == null || landingType == LandingType.touchAndGo;

  var total = 0;
  if (includeDay && includeFullStop) total += counts.dayFullStop;
  if (includeDay && includeTouchAndGo) total += counts.dayTouchAndGo;
  if (includeNight && includeFullStop) total += counts.nightFullStop;
  if (includeNight && includeTouchAndGo) total += counts.nightTouchAndGo;
  return total;
}

/// Whether [record] passes every [ConditionKind.aircraftMatch] condition in
/// [conditions] against [referenceAircraft].
///
/// Throws [StateError] if an aircraft-match condition is present but
/// [referenceAircraft] is null — a rule asking "same type as what?" with
/// nothing supplied to compare against is a caller error, not a state to
/// silently treat as passing or failing.
bool _passesAircraftMatch(
  FlightRecord record,
  List<FlightCondition> conditions,
  Aircraft? referenceAircraft,
) {
  for (final condition in conditions) {
    if (condition.kind != ConditionKind.aircraftMatch) {
      continue;
    }
    if (referenceAircraft == null) {
      throw StateError(
        'Requirement has an aircraftMatch condition but '
        'EvaluationSubject.referenceAircraft is null',
      );
    }
    if (!_aircraftMatches(
      record.aircraft,
      referenceAircraft,
      condition.aircraftMatch!,
    )) {
      return false;
    }
  }
  return true;
}

bool _aircraftMatches(Aircraft flown, Aircraft reference, AircraftMatch level) {
  final flownType = flown.typeRatingDesignator ?? flown.icaoTypeDesignator;
  final referenceType =
      reference.typeRatingDesignator ?? reference.icaoTypeDesignator;
  final sameType = flownType != null && flownType == referenceType;
  final sameClass =
      flown.engineType == reference.engineType &&
      flown.engineCount == reference.engineCount &&
      flown.operatingSurface == reference.operatingSurface;

  return switch (level) {
    AircraftMatch.sameType => sameType,
    AircraftMatch.sameClass => sameClass,
    AircraftMatch.sameTypeOrClass => sameType || sameClass,
    // §61.57(a): a type match only if the reference aircraft is itself
    // type-rated — tested against the actual type-rating designators, not
    // the icaoTypeDesignator fallback [sameType] uses, since this is
    // specifically about type-rating currency.
    AircraftMatch.classOrTypeIfRequired =>
      reference.typeRatingDesignator == null
          ? sameClass
          : flown.typeRatingDesignator == reference.typeRatingDesignator,
  };
}

String _eventLabel(CountableFlightEvent event) => switch (event) {
  CountableFlightEvent.landings => 'landings',
  CountableFlightEvent.takeoffs => 'takeoffs',
  CountableFlightEvent.approaches => 'approaches',
  CountableFlightEvent.holdingProcedures => 'holding procedures',
  CountableFlightEvent.trackingPerformed => 'tracking tasks performed',
  CountableFlightEvent.faaFlightReview => 'flight reviews',
  CountableFlightEvent.faaInstrumentProficiencyCheck =>
    'instrument proficiency checks',
  CountableFlightEvent.easaClassRatingProficiencyCheck =>
    'class rating proficiency checks',
};

/// [_eventLabel] qualified by [conditions]' day/night and landing-type
/// values, e.g. "night full-stop landings" — #43's own example explanation
/// names the qualifiers, not just the bare event ("needs 1 more full-stop
/// night landing", not "needs 1 more landing"). Silent about
/// [ConditionKind.aircraftMatch]: that condition narrows *which flights*
/// count, not what kind of event is being counted, so it belongs in a
/// result's flight list, not its event description.
String _describeEvent(
  CountableFlightEvent event,
  List<FlightCondition> conditions,
) {
  DayNight? dayNight;
  LandingType? landingType;
  for (final condition in conditions) {
    switch (condition.kind) {
      case ConditionKind.dayNight:
        dayNight = condition.dayNight;
      case ConditionKind.landingType:
        landingType = condition.landingType;
      case ConditionKind.aircraftMatch:
        break;
    }
  }

  final qualifiers = [
    if (dayNight != null) dayNight.name,
    if (landingType == LandingType.fullStop) 'full-stop',
    if (landingType == LandingType.touchAndGo) 'touch-and-go',
  ];
  return qualifiers.isEmpty
      ? _eventLabel(event)
      : '${qualifiers.join(' ')} ${_eventLabel(event)}';
}
