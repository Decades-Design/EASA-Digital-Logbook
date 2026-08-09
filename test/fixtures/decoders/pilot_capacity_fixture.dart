import 'package:easa_digital_log/domain/model/calendar_date.dart';
import 'package:easa_digital_log/domain/model/countersignature.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/instructor_presence.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:yaml/yaml.dart';

import '../fixture_loader.dart';
import 'fixture_fields.dart';

/// Decodes `test/fixtures/capacities/<name>.yaml` into a [PilotCapacity].
///
/// Lives in `test/` rather than `lib/domain/` because YAML fixture shape is a
/// test concern; the domain model knows nothing about how fixtures are spelt.
PilotCapacity pilotCapacityFromFixture(String name) {
  final yaml = loadFixture('capacities', name);
  return pilotCapacityFromYaml(yaml, name);
}

/// As [pilotCapacityFromFixture], but decodes an already-loaded [YamlMap] —
/// the shape `flight_fixture.dart` needs for the nested `capacity:` block
/// inside a flight fixture, rather than a whole file of its own.
PilotCapacity pilotCapacityFromYaml(YamlMap yaml, String fixture) {
  return PilotCapacity(
    commandAuthority: requiredBool(yaml, 'command_authority', fixture),
    soleManipulator: requiredBool(yaml, 'sole_manipulator', fixture),
    soleOccupant: requiredBool(yaml, 'sole_occupant', fixture),
    multiPilotOperation: requiredBool(yaml, 'multi_pilot_operation', fixture),
    additionalCrewRequiredByRule: requiredBool(
      yaml,
      'additional_crew_required_by_rule',
      fixture,
    ),
    soloEndorsementHeld: optionalBool(yaml, 'solo_endorsement_held', fixture),
    endorsingInstructorName: optionalString(
      yaml,
      'endorsing_instructor_name',
      fixture,
    ),
    actingAsInstructor: requiredBool(yaml, 'acting_as_instructor', fixture),
    actingAsExaminer: requiredBool(yaml, 'acting_as_examiner', fixture),
    picusClaimed: requiredBool(yaml, 'picus_claimed', fixture),
    picInterventionNotRequired: requiredBool(
      yaml,
      'pic_intervention_not_required',
      fixture,
    ),
    manipulationTime: _duration(yaml, 'manipulation_time', fixture),
    instructor: _instructor(optionalMap(yaml, 'instructor', fixture), fixture),
    otherPilotRole: _otherPilotRole(yaml, fixture),
    countersignature: _countersignature(
      optionalMap(yaml, 'countersignature', fixture),
      fixture,
    ),
  );
}

InstructorPresence? _instructor(YamlMap? yaml, String fixture) {
  if (yaml == null) {
    return null;
  }

  const capacities = <String, InstructorCapacity>{
    'FI': InstructorCapacity.flightInstructor,
    'FE': InstructorCapacity.flightExaminer,
  };

  final raw = requiredString(yaml, 'capacity', fixture);
  final capacity = capacities[raw];
  if (capacity == null) {
    throw FixtureFieldException(
      fixture,
      'instructor.capacity',
      'one of ${capacities.keys.join(', ')}, got "$raw"',
    );
  }

  return InstructorPresence(
    capacity: capacity,
    influencedFlight: requiredBool(yaml, 'influenced_flight', fixture),
    name: optionalString(yaml, 'name', fixture),
    credentialNumber: optionalString(yaml, 'credential_number', fixture),
    credentialExpiry: _date(yaml, 'credential_expiry', fixture),
  );
}

Countersignature? _countersignature(YamlMap? yaml, String fixture) {
  if (yaml == null) {
    return null;
  }

  const statuses = <String, CountersignatureStatus>{
    'pending': CountersignatureStatus.pending,
    'signed': CountersignatureStatus.signed,
    'refused': CountersignatureStatus.refused,
  };

  final raw = requiredString(yaml, 'status', fixture);
  final status = statuses[raw];
  if (status == null) {
    throw FixtureFieldException(
      fixture,
      'countersignature.status',
      'one of ${statuses.keys.join(', ')}, got "$raw"',
    );
  }

  return Countersignature(
    status: status,
    signatoryName: optionalString(yaml, 'signatory_name', fixture),
    signatoryCredentialNumber: optionalString(
      yaml,
      'signatory_credential_number',
      fixture,
    ),
    signatoryCredentialExpiry: _date(
      yaml,
      'signatory_credential_expiry',
      fixture,
    ),
    signedAt: _instant(yaml, 'signed_at', fixture),
  );
}

OtherPilotRole? _otherPilotRole(YamlMap yaml, String fixture) {
  const roles = <String, OtherPilotRole>{
    'required_crew': OtherPilotRole.requiredCrew,
    'not_required_crew': OtherPilotRole.notRequiredCrew,
    'safety_pilot': OtherPilotRole.safetyPilot,
  };

  final raw = optionalString(yaml, 'other_pilot_role', fixture);
  if (raw == null) {
    return null;
  }

  final role = roles[raw];
  if (role == null) {
    throw FixtureFieldException(
      fixture,
      'other_pilot_role',
      'one of ${roles.keys.join(', ')}, got "$raw"',
    );
  }
  return role;
}

/// Durations are written `"H:MM"` and quoted — see the YAML caveat in
/// `test/fixtures/README.md`.
FlightDuration? _duration(YamlMap yaml, String key, String fixture) {
  final value = optionalString(yaml, key, fixture);
  if (value == null) {
    return null;
  }
  try {
    return FlightDuration.parseHoursMinutes(value);
  } on FormatException {
    throw FixtureFieldException(fixture, key, 'a quoted "H:MM", got "$value"');
  }
}

/// Credential expiry dates are quoted `YYYY-MM-DD`; [CalendarDate.parse]
/// rejects anything else, so a malformed fixture value fails loudly.
CalendarDate? _date(YamlMap yaml, String key, String fixture) {
  final value = optionalString(yaml, key, fixture);
  if (value == null) {
    return null;
  }
  try {
    return CalendarDate.parse(value);
  } on FormatException {
    throw FixtureFieldException(
      fixture,
      key,
      'a quoted "YYYY-MM-DD", got "$value"',
    );
  }
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
