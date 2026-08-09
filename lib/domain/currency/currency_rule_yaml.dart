import 'package:yaml/yaml.dart';

import '../model/calendar_date.dart';
import '../model/flight_duration.dart';
import 'currency_rule.dart';
import 'flight_condition.dart';
import 'rule_window.dart';

/// Parses one `assets/rules/*.yaml` document into a [CurrencyRule] — #40.
///
/// Validation happens here, in Dart, the same way
/// `parseJurisdictionProfileYaml` validates jurisdiction profiles: every
/// failure is a [FormatException] naming the rule id (once known) and the
/// offending field, never a silent default. `currency_rule.schema.json`
/// (published alongside this file) exists for editor autocomplete and as an
/// independently-checked cross-reference — see the test that asserts the
/// two agree on which fields are required — not as the enforcement
/// mechanism itself.
CurrencyRule parseCurrencyRuleYaml(String yamlContent) {
  final yaml = loadYaml(yamlContent);
  if (yaml is! YamlMap) {
    throw const FormatException('Currency rule YAML must be a map');
  }

  final id = _requiredString(yaml, 'id', 'currency rule');
  final jurisdictionId = _requiredString(yaml, 'jurisdiction', id);
  final citation = _requiredString(yaml, 'citation', id);
  final effectiveFrom = _requiredDate(yaml, 'effective_from', id);
  final expiresOn = _optionalDate(yaml, 'expires_on', id);

  final requirementYaml = yaml['requirement'];
  if (requirementYaml is! YamlMap) {
    throw FormatException('Currency rule "$id" is missing a "requirement" map');
  }
  final requirement = _parseRequirement(requirementYaml, id);

  return CurrencyRule(
    id: id,
    jurisdictionId: jurisdictionId,
    citation: citation,
    effectiveFrom: effectiveFrom,
    expiresOn: expiresOn,
    requirement: requirement,
  );
}

const Map<String, RequirementKind> _requirementKinds = {
  'flight_event_count': RequirementKind.flightEventCount,
  'flight_event_hours': RequirementKind.flightEventHours,
  'held_record_currently_valid': RequirementKind.heldRecordCurrentlyValid,
  'all_of': RequirementKind.allOf,
  'any_of': RequirementKind.anyOf,
};

Requirement _parseRequirement(YamlMap yaml, String ruleId) {
  final kindText = _requiredString(
    yaml,
    'kind',
    ruleId,
    context: 'requirement',
  );
  final kind = _requirementKinds[kindText];
  if (kind == null) {
    throw FormatException(
      'Currency rule "$ruleId": requirement "kind" must be one of '
      '${_requirementKinds.keys.join(', ')}, got "$kindText"',
    );
  }

  switch (kind) {
    case RequirementKind.flightEventCount:
      return Requirement.flightEventCount(
        event: _requiredEvent(yaml, ruleId),
        count: _requiredInt(yaml, 'count', ruleId, context: 'requirement'),
        window: _parseWindow(_requiredMap(yaml, 'window', ruleId), ruleId),
        conditions: _parseConditions(yaml, ruleId),
      );
    case RequirementKind.flightEventHours:
      return Requirement.flightEventHours(
        event: _requiredEvent(yaml, ruleId),
        hours: _requiredHours(yaml, ruleId),
        window: _parseWindow(_requiredMap(yaml, 'window', ruleId), ruleId),
        conditions: _parseConditions(yaml, ruleId),
      );
    case RequirementKind.heldRecordCurrentlyValid:
      return Requirement.heldRecordCurrentlyValid(
        _requiredString(
          yaml,
          'held_record_kind',
          ruleId,
          context: 'requirement',
        ),
      );
    case RequirementKind.allOf:
      return Requirement.allOf(_parseSubRequirements(yaml, ruleId));
    case RequirementKind.anyOf:
      return Requirement.anyOf(_parseSubRequirements(yaml, ruleId));
  }
}

List<Requirement> _parseSubRequirements(YamlMap yaml, String ruleId) {
  final of = yaml['of'];
  if (of is! YamlList || of.isEmpty) {
    throw FormatException(
      'Currency rule "$ruleId": requirement "of" must be a non-empty list',
    );
  }
  return [
    for (final entry in of)
      if (entry is YamlMap)
        _parseRequirement(entry, ruleId)
      else
        throw FormatException(
          'Currency rule "$ruleId": requirement "of" entries must be maps',
        ),
  ];
}

const Map<String, CountableFlightEvent> _events = {
  'landings': CountableFlightEvent.landings,
  'takeoffs': CountableFlightEvent.takeoffs,
  'approaches': CountableFlightEvent.approaches,
  'holding_procedures': CountableFlightEvent.holdingProcedures,
  'tracking_performed': CountableFlightEvent.trackingPerformed,
  'faa_flight_review': CountableFlightEvent.faaFlightReview,
  'faa_instrument_proficiency_check':
      CountableFlightEvent.faaInstrumentProficiencyCheck,
  'easa_class_rating_proficiency_check':
      CountableFlightEvent.easaClassRatingProficiencyCheck,
};

CountableFlightEvent _requiredEvent(YamlMap yaml, String ruleId) {
  final text = _requiredString(yaml, 'event', ruleId, context: 'requirement');
  final event = _events[text];
  if (event == null) {
    throw FormatException(
      'Currency rule "$ruleId": requirement "event" must be one of '
      '${_events.keys.join(', ')}, got "$text"',
    );
  }
  return event;
}

FlightDuration _requiredHours(YamlMap yaml, String ruleId) {
  final value = yaml['hours'];
  if (value is! num) {
    throw FormatException(
      'Currency rule "$ruleId": requirement is missing a numeric "hours"',
    );
  }
  return FlightDuration.parseDecimalHours(value.toString());
}

const Map<String, WindowAnchor> _anchors = {
  'evaluation_date': WindowAnchor.evaluationDate,
  'held_record_expiry': WindowAnchor.heldRecordExpiry,
};

RuleWindow _parseWindow(YamlMap yaml, String ruleId) {
  final kindText = _requiredString(yaml, 'kind', ruleId, context: 'window');
  switch (kindText) {
    case 'rolling_days':
      return RuleWindow.rollingDays(
        _requiredInt(yaml, 'days', ruleId, context: 'window'),
      );
    case 'calendar_months':
      final anchorText = yaml['anchor'] as String? ?? 'evaluation_date';
      final anchor = _anchors[anchorText];
      if (anchor == null) {
        throw FormatException(
          'Currency rule "$ruleId": window "anchor" must be one of '
          '${_anchors.keys.join(', ')}, got "$anchorText"',
        );
      }
      final anchorHeldRecordKind = yaml['anchor_held_record_kind'] as String?;
      if (anchor == WindowAnchor.heldRecordExpiry &&
          anchorHeldRecordKind == null) {
        throw FormatException(
          'Currency rule "$ruleId": window anchor "held_record_expiry" '
          'requires "anchor_held_record_kind"',
        );
      }
      return RuleWindow.calendarMonths(
        _requiredInt(yaml, 'months', ruleId, context: 'window'),
        anchor: anchor,
        anchorHeldRecordKind: anchorHeldRecordKind,
      );
    default:
      throw FormatException(
        'Currency rule "$ruleId": window "kind" must be "rolling_days" or '
        '"calendar_months", got "$kindText"',
      );
  }
}

const Map<String, DayNight> _dayNightValues = {
  'day': DayNight.day,
  'night': DayNight.night,
};

const Map<String, LandingType> _landingTypeValues = {
  'full_stop': LandingType.fullStop,
  'touch_and_go': LandingType.touchAndGo,
};

const Map<String, AircraftMatch> _aircraftMatchValues = {
  'same_type': AircraftMatch.sameType,
  'same_class': AircraftMatch.sameClass,
  'same_type_or_class': AircraftMatch.sameTypeOrClass,
  'class_or_type_if_required': AircraftMatch.classOrTypeIfRequired,
};

List<FlightCondition> _parseConditions(YamlMap yaml, String ruleId) {
  final conditions = yaml['conditions'];
  if (conditions == null) {
    return const [];
  }
  if (conditions is! YamlList) {
    throw FormatException(
      'Currency rule "$ruleId": requirement "conditions" must be a list',
    );
  }
  return [for (final entry in conditions) _parseCondition(entry, ruleId)];
}

FlightCondition _parseCondition(Object? entry, String ruleId) {
  if (entry is! YamlMap) {
    throw FormatException(
      'Currency rule "$ruleId": each entry in "conditions" must be a map',
    );
  }
  final kindText = _requiredString(entry, 'kind', ruleId, context: 'condition');
  switch (kindText) {
    case 'day_night':
      final value = _requiredString(
        entry,
        'value',
        ruleId,
        context: 'condition',
      );
      final dayNight = _dayNightValues[value];
      if (dayNight == null) {
        throw FormatException(
          'Currency rule "$ruleId": condition "value" must be "day" or '
          '"night", got "$value"',
        );
      }
      return FlightCondition.dayNight(dayNight);
    case 'landing_type':
      final value = _requiredString(
        entry,
        'value',
        ruleId,
        context: 'condition',
      );
      final landingType = _landingTypeValues[value];
      if (landingType == null) {
        throw FormatException(
          'Currency rule "$ruleId": condition "value" must be "full_stop" '
          'or "touch_and_go", got "$value"',
        );
      }
      return FlightCondition.landingType(landingType);
    case 'aircraft_match':
      final level = _requiredString(
        entry,
        'level',
        ruleId,
        context: 'condition',
      );
      final match = _aircraftMatchValues[level];
      if (match == null) {
        throw FormatException(
          'Currency rule "$ruleId": condition "level" must be one of '
          '${_aircraftMatchValues.keys.join(', ')}, got "$level"',
        );
      }
      return FlightCondition.aircraftMatch(match);
    default:
      throw FormatException(
        'Currency rule "$ruleId": condition "kind" must be "day_night", '
        '"landing_type" or "aircraft_match", got "$kindText"',
      );
  }
}

// ---- Small, shared field-reading helpers. Deliberately not imported from
// test/fixtures/decoders/fixture_fields.dart: that file is test-only, and
// production parsing needs its own error wording (rule id, not fixture
// name).

String _requiredString(
  YamlMap yaml,
  String key,
  String ruleId, {
  String? context,
}) {
  final value = yaml[key];
  if (value is! String || value.isEmpty) {
    final where = context == null
        ? 'Currency rule'
        : 'Currency rule "$ruleId"\'s $context';
    throw FormatException('$where is missing a non-empty "$key"');
  }
  return value;
}

int _requiredInt(YamlMap yaml, String key, String ruleId, {String? context}) {
  final value = yaml[key];
  if (value is! int) {
    final where = context == null
        ? 'Currency rule "$ruleId"'
        : 'Currency rule "$ruleId"\'s $context';
    throw FormatException('$where is missing an integer "$key"');
  }
  return value;
}

YamlMap _requiredMap(YamlMap yaml, String key, String ruleId) {
  final value = yaml[key];
  if (value is! YamlMap) {
    throw FormatException('Currency rule "$ruleId" is missing a "$key" map');
  }
  return value;
}

CalendarDate _requiredDate(YamlMap yaml, String key, String ruleId) {
  final value = yaml[key];
  if (value is! String) {
    throw FormatException('Currency rule "$ruleId" is missing a "$key" date');
  }
  try {
    return CalendarDate.parse(value);
  } on FormatException {
    throw FormatException(
      'Currency rule "$ruleId": "$key" must be YYYY-MM-DD, got "$value"',
    );
  }
}

CalendarDate? _optionalDate(YamlMap yaml, String key, String ruleId) {
  final value = yaml[key];
  if (value == null) {
    return null;
  }
  if (value is! String) {
    throw FormatException('Currency rule "$ruleId": "$key" must be a date');
  }
  try {
    return CalendarDate.parse(value);
  } on FormatException {
    throw FormatException(
      'Currency rule "$ruleId": "$key" must be YYYY-MM-DD, got "$value"',
    );
  }
}
