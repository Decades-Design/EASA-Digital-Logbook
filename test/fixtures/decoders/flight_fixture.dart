import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:yaml/yaml.dart';

import '../fixture_loader.dart';
import 'fixture_fields.dart';
import 'pilot_capacity_fixture.dart';

const Map<String, AirworthinessBasis> _airworthinessBases =
    <String, AirworthinessBasis>{
      'us_registry_standard_or_special':
          AirworthinessBasis.usRegistryStandardOrSpecial,
      'foreign_registry_icao_member_approved':
          AirworthinessBasis.foreignRegistryIcaoMemberApproved,
      'us_military': AirworthinessBasis.usMilitary,
      'public_aircraft_operation': AirworthinessBasis.publicAircraftOperation,
    };

const Map<String, ApproachType> _approachTypes = <String, ApproachType>{
  'ils': ApproachType.ils,
  'rnav': ApproachType.rnav,
  'gps': ApproachType.gps,
  'vor': ApproachType.vor,
  'loc': ApproachType.loc,
  'ndb': ApproachType.ndb,
  'back_course': ApproachType.backCourse,
  'lda': ApproachType.lda,
  'sdf': ApproachType.sdf,
  'tacan': ApproachType.tacan,
  'par': ApproachType.par,
  'asr': ApproachType.asr,
  'mls': ApproachType.mls,
};

/// Decodes `test/fixtures/flights/<name>.yaml` into a [Flight].
Flight flightFromFixture(String name) {
  final yaml = loadFixture('flights', name);

  return Flight(
    aircraftRegistration: requiredString(yaml, 'aircraft_registration', name),
    route: requiredStringList(yaml, 'route', name),
    prePlannedNavigation: requiredBool(yaml, 'pre_planned_navigation', name),
    offBlocks: _instant(yaml, 'off_blocks', name)!,
    onBlocks: _instant(yaml, 'on_blocks', name)!,
    takeoff: _instant(yaml, 'takeoff', name),
    landing: _instant(yaml, 'landing', name),
    capacity: pilotCapacityFromYaml(requiredMap(yaml, 'capacity', name), name),
    otherPilotName: optionalString(yaml, 'other_pilot_name', name),
    otherPilotCredentialNumber: optionalString(
      yaml,
      'other_pilot_credential_number',
      name,
    ),
    carryingPassengers: requiredBool(yaml, 'carrying_passengers', name),
    takeoffs: _circuitCounts(requiredMap(yaml, 'takeoffs', name), name),
    landings: _circuitCounts(requiredMap(yaml, 'landings', name), name),
    ifrFlightPlanFiled: requiredBool(yaml, 'ifr_flight_plan_filed', name),
    actualInstrumentTime: FlightDuration(
      requiredInt(yaml, 'actual_instrument_minutes', name),
    ),
    simulatedInstrumentTime: FlightDuration(
      requiredInt(yaml, 'simulated_instrument_minutes', name),
    ),
    approaches: _approaches(yaml, name),
    holdingProceduresCount: requiredInt(yaml, 'holding_procedures_count', name),
    trackingPerformed: requiredBool(yaml, 'tracking_performed', name),
    seriesGroupId: optionalString(yaml, 'series_group_id', name),
    airworthinessBasis: _airworthinessBasis(yaml, name),
    remarks: requiredString(yaml, 'remarks', name),
  );
}

CircuitCounts _circuitCounts(YamlMap yaml, String fixture) => CircuitCounts(
  dayFullStop: optionalInt(yaml, 'day_full_stop', fixture) ?? 0,
  dayTouchAndGo: optionalInt(yaml, 'day_touch_and_go', fixture) ?? 0,
  nightFullStop: optionalInt(yaml, 'night_full_stop', fixture) ?? 0,
  nightTouchAndGo: optionalInt(yaml, 'night_touch_and_go', fixture) ?? 0,
);

/// Absent `approaches:` means an empty list — #11: "empty, not null, when
/// none" describes the *model*, but a fixture that never mentions approaches
/// is unambiguously describing zero, not an unrecorded discriminator, so
/// requiring `approaches: []` boilerplate on every non-instrument fixture
/// would add nothing.
List<Approach> _approaches(YamlMap yaml, String fixture) {
  final value = yaml['approaches'];
  if (value == null) {
    return const <Approach>[];
  }
  if (value is! YamlList) {
    throw FixtureFieldException(
      fixture,
      'approaches',
      'a list, got ${describe(value)}',
    );
  }
  return [
    for (final entry in value)
      if (entry is YamlMap)
        Approach(
          type: _approachType(entry, fixture),
          aerodromeIcao: requiredString(entry, 'aerodrome_icao', fixture),
          runway: _runway(entry, fixture),
          count: optionalInt(entry, 'count', fixture) ?? 1,
        )
      else
        throw FixtureFieldException(
          fixture,
          'approaches',
          'a list of maps, got an entry ${describe(entry)}',
        ),
  ];
}

ApproachType _approachType(YamlMap yaml, String fixture) {
  final raw = requiredString(yaml, 'type', fixture);
  final type = _approachTypes[raw];
  if (type == null) {
    throw FixtureFieldException(
      fixture,
      'approaches.type',
      'one of ${_approachTypes.keys.join(', ')}, got "$raw"',
    );
  }
  return type;
}

/// Two digits, `01`-`36`, optionally followed by `L`, `C` or `R`.
final RegExp _runwayPattern = RegExp(r'^(0[1-9]|[12][0-9]|3[0-6])[LCR]?$');

String _runway(YamlMap yaml, String fixture) {
  final runway = requiredString(yaml, 'runway', fixture);
  if (!_runwayPattern.hasMatch(runway)) {
    throw FixtureFieldException(
      fixture,
      'approaches.runway',
      'two digits 01-36 with an optional L/C/R suffix, got "$runway"',
    );
  }
  return runway;
}

AirworthinessBasis? _airworthinessBasis(YamlMap yaml, String fixture) {
  final raw = optionalString(yaml, 'airworthiness_basis', fixture);
  if (raw == null) {
    return null;
  }
  final basis = _airworthinessBases[raw];
  if (basis == null) {
    throw FixtureFieldException(
      fixture,
      'airworthiness_basis',
      'one of ${_airworthinessBases.keys.join(', ')}, got "$raw"',
    );
  }
  return basis;
}

/// Instants are ISO-8601 with an explicit `Z`; [UtcInstant.parse] rejects
/// anything without a zone designator, so a naive fixture value fails loudly.
UtcInstant? _instant(YamlMap yaml, String key, String fixture) {
  final value = optionalString(yaml, key, fixture);
  if (value == null) {
    return null;
  }
  try {
    return UtcInstant.parse(value);
  } on FormatException {
    throw FixtureFieldException(
      fixture,
      key,
      'an ISO-8601 instant ending in Z, got "$value"',
    );
  }
}
