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

/// Decodes `test/fixtures/flights/<name>.yaml` into a [Flight].
Flight flightFromFixture(String name) {
  final yaml = loadFixture('flights', name);

  return Flight(
    aircraftRegistration: requiredString(yaml, 'aircraft_registration', name),
    route: requiredStringList(yaml, 'route', name),
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
    holdingAndTrackingPerformed: requiredBool(
      yaml,
      'holding_and_tracking_performed',
      name,
    ),
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
          type: requiredString(entry, 'type', fixture),
          location: requiredString(entry, 'location', fixture),
        )
      else
        throw FixtureFieldException(
          fixture,
          'approaches',
          'a list of maps, got an entry ${describe(entry)}',
        ),
  ];
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
