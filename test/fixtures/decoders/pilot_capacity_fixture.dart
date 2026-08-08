import 'package:easa_digital_log/domain/model/countersignature.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/instructor_presence.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:yaml/yaml.dart';

import '../fixture_loader.dart';

/// Thrown when a fixture field is missing or the wrong shape, naming the
/// fixture and the key so the failure is actionable without opening the YAML.
///
/// A missing required key must never fall back to a default: a silently
/// defaulted discriminator is exactly the failure CLAUDE.md rule 2 exists to
/// prevent, and it would be indistinguishable from a deliberate `false`.
class FixtureFieldException implements Exception {
  const FixtureFieldException(this.fixture, this.key, this.expected);

  final String fixture;
  final String key;
  final String expected;

  @override
  String toString() =>
      'FixtureFieldException: capacities/$fixture.yaml key "$key" — '
      'expected $expected';
}

/// Decodes `test/fixtures/capacities/<name>.yaml` into a [PilotCapacity].
///
/// Lives in `test/` rather than `lib/domain/` because YAML fixture shape is a
/// test concern; the domain model knows nothing about how fixtures are spelt.
PilotCapacity pilotCapacityFromFixture(String name) {
  final yaml = loadFixture('capacities', name);

  return PilotCapacity(
    commandAuthority: _bool(yaml, 'command_authority', name),
    soleManipulator: _bool(yaml, 'sole_manipulator', name),
    soleOccupant: _bool(yaml, 'sole_occupant', name),
    multiPilotOperation: _bool(yaml, 'multi_pilot_operation', name),
    additionalCrewRequiredByRule: _bool(
      yaml,
      'additional_crew_required_by_rule',
      name,
    ),
    soloEndorsementHeld: _optionalBool(yaml, 'solo_endorsement_held', name),
    endorsingInstructorName: _optionalString(
      yaml,
      'endorsing_instructor_name',
      name,
    ),
    actingAsInstructor: _bool(yaml, 'acting_as_instructor', name),
    actingAsExaminer: _bool(yaml, 'acting_as_examiner', name),
    picusClaimed: _bool(yaml, 'picus_claimed', name),
    picInterventionNotRequired: _bool(
      yaml,
      'pic_intervention_not_required',
      name,
    ),
    manipulationTime: _duration(yaml, 'manipulation_time', name),
    instructor: _instructor(_map(yaml, 'instructor', name), name),
    otherPilotRole: _otherPilotRole(yaml, name),
    countersignature: _countersignature(
      _map(yaml, 'countersignature', name),
      name,
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

  final raw = _string(yaml, 'capacity', fixture);
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
    influencedFlight: _bool(yaml, 'influenced_flight', fixture),
    name: _optionalString(yaml, 'name', fixture),
    credentialNumber: _optionalString(yaml, 'credential_number', fixture),
    credentialExpiry: _instant(yaml, 'credential_expiry', fixture),
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

  final raw = _string(yaml, 'status', fixture);
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
    signatoryName: _optionalString(yaml, 'signatory_name', fixture),
    signatoryCredentialNumber: _optionalString(
      yaml,
      'signatory_credential_number',
      fixture,
    ),
    signatoryCredentialExpiry: _instant(
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

  final raw = _optionalString(yaml, 'other_pilot_role', fixture);
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

bool _bool(YamlMap yaml, String key, String fixture) {
  final value = yaml[key];
  if (value is bool) {
    return value;
  }
  throw FixtureFieldException(
    fixture,
    key,
    'a boolean, got ${_describe(value)}',
  );
}

bool? _optionalBool(YamlMap yaml, String key, String fixture) {
  final value = yaml[key];
  if (value == null) {
    return null;
  }
  if (value is bool) {
    return value;
  }
  throw FixtureFieldException(
    fixture,
    key,
    'a boolean, got ${_describe(value)}',
  );
}

String _string(YamlMap yaml, String key, String fixture) {
  final value = _optionalString(yaml, key, fixture);
  if (value == null) {
    throw FixtureFieldException(fixture, key, 'a string, got nothing');
  }
  return value;
}

String? _optionalString(YamlMap yaml, String key, String fixture) {
  final value = yaml[key];
  if (value == null) {
    return null;
  }
  if (value is String) {
    return value;
  }
  throw FixtureFieldException(
    fixture,
    key,
    'a string, got ${_describe(value)}',
  );
}

YamlMap? _map(YamlMap yaml, String key, String fixture) {
  final value = yaml[key];
  if (value == null) {
    return null;
  }
  if (value is YamlMap) {
    return value;
  }
  throw FixtureFieldException(fixture, key, 'a map, got ${_describe(value)}');
}

/// Durations are written `"H:MM"` and quoted — see the YAML caveat in
/// `test/fixtures/README.md`.
FlightDuration? _duration(YamlMap yaml, String key, String fixture) {
  final value = _optionalString(yaml, key, fixture);
  if (value == null) {
    return null;
  }
  try {
    return FlightDuration.parseHoursMinutes(value);
  } on FormatException {
    throw FixtureFieldException(fixture, key, 'a quoted "H:MM", got "$value"');
  }
}

/// Instants are ISO-8601 with an explicit `Z`; [UtcInstant.parse] rejects
/// anything without a zone designator, so a naive fixture value fails loudly.
UtcInstant? _instant(YamlMap yaml, String key, String fixture) {
  final value = _optionalString(yaml, key, fixture);
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

String _describe(Object? value) =>
    value == null ? 'nothing' : '${value.runtimeType} ($value)';
