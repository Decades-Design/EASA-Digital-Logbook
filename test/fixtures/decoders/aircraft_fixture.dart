import 'package:easa_digital_log/domain/model/aircraft.dart';
import 'package:yaml/yaml.dart';

import '../fixture_loader.dart';
import 'fixture_fields.dart';

/// Snake-case YAML spellings for [AircraftQualification].
///
/// Spelt out rather than derived from the enum name, so renaming a Dart value
/// cannot silently change what a fixture means.
const Map<String, AircraftQualification>
_qualifications = <String, AircraftQualification>{
  'faa_complex': AircraftQualification.faaComplex,
  'faa_high_performance': AircraftQualification.faaHighPerformance,
  'faa_high_altitude': AircraftQualification.faaHighAltitude,
  'faa_tailwheel': AircraftQualification.faaTailwheel,
  'faa_towing': AircraftQualification.faaTowing,
  'easa_variable_pitch_propeller':
      AircraftQualification.easaVariablePitchPropeller,
  'easa_retractable_undercarriage':
      AircraftQualification.easaRetractableUndercarriage,
  'easa_turbo_or_supercharged': AircraftQualification.easaTurboOrSupercharged,
  'easa_cabin_pressurisation': AircraftQualification.easaCabinPressurisation,
  'easa_tailwheel': AircraftQualification.easaTailwheel,
  'easa_electronic_flight_instrument_system':
      AircraftQualification.easaElectronicFlightInstrumentSystem,
  'easa_single_lever_power_control':
      AircraftQualification.easaSingleLeverPowerControl,
  'easa_other_engine_type': AircraftQualification.easaOtherEngineType,
};

const Map<String, AircraftCategory> _categories = <String, AircraftCategory>{
  'aeroplane': AircraftCategory.aeroplane,
  'helicopter': AircraftCategory.helicopter,
  'powered_lift': AircraftCategory.poweredLift,
  'glider': AircraftCategory.glider,
  'touring_motor_glider': AircraftCategory.touringMotorGlider,
  'airship': AircraftCategory.airship,
  'balloon': AircraftCategory.balloon,
  'powered_parachute': AircraftCategory.poweredParachute,
};

const Map<String, EngineType> _engineTypes = <String, EngineType>{
  'none': EngineType.none,
  'piston': EngineType.piston,
  'turboprop': EngineType.turboprop,
  'turbojet': EngineType.turbojet,
  'turbofan': EngineType.turbofan,
  'electric': EngineType.electric,
};

const Map<String, OperatingSurface> _surfaces = <String, OperatingSurface>{
  'land': OperatingSurface.land,
  'sea': OperatingSurface.sea,
  'amphibian': OperatingSurface.amphibian,
};

/// Decodes `test/fixtures/aircraft/<name>.yaml` into an [Aircraft].
Aircraft aircraftFromFixture(String name) {
  final yaml = loadFixture('aircraft', name);

  return Aircraft(
    registration: requiredString(yaml, 'registration', name),
    manufacturer: requiredString(yaml, 'manufacturer', name),
    model: requiredString(yaml, 'model', name),
    icaoTypeDesignator: optionalString(yaml, 'icao_type_designator', name),
    category: _enumValue(yaml, 'category', name, _categories),
    engineType: _enumValue(yaml, 'engine_type', name, _engineTypes),
    engineCount: _int(yaml, 'engine_count', name),
    operatingSurface: _enumValue(yaml, 'operating_surface', name, _surfaces),
    requiresMultiCrew: requiredBool(yaml, 'requires_multi_crew', name),
    typeRatingDesignator: optionalString(yaml, 'type_rating_designator', name),
    requiredQualifications: _requiredQualifications(yaml, name),
  );
}

/// Reads the per-authority qualification lists.
///
/// A missing `required_qualifications` block, and a key absent from it, both
/// mean "not set up for that authority" — distinct from a present but empty
/// list, which means set up and requiring nothing.
Map<String, Set<AircraftQualification>> _requiredQualifications(
  YamlMap yaml,
  String fixture,
) {
  final block = optionalMap(yaml, 'required_qualifications', fixture);
  if (block == null) {
    return const <String, Set<AircraftQualification>>{};
  }

  final result = <String, Set<AircraftQualification>>{};
  for (final entry in block.entries) {
    final jurisdiction = entry.key;
    if (jurisdiction is! String) {
      throw FixtureFieldException(
        fixture,
        'required_qualifications',
        'jurisdiction ids as strings, got ${describe(jurisdiction)}',
      );
    }

    final listed = entry.value;
    if (listed is! YamlList) {
      throw FixtureFieldException(
        fixture,
        'required_qualifications.$jurisdiction',
        'a list, got ${describe(listed)}',
      );
    }

    final qualifications = <AircraftQualification>{};
    for (final item in listed) {
      if (item is! String) {
        throw FixtureFieldException(
          fixture,
          'required_qualifications.$jurisdiction',
          'a list of strings, got an entry ${describe(item)}',
        );
      }
      final qualification = _qualifications[item];
      if (qualification == null) {
        throw FixtureFieldException(
          fixture,
          'required_qualifications.$jurisdiction',
          'a known qualification, got "$item"',
        );
      }
      if (!qualifications.add(qualification)) {
        throw FixtureFieldException(
          fixture,
          'required_qualifications.$jurisdiction',
          'no duplicates, got "$item" twice',
        );
      }
    }
    result[jurisdiction] = qualifications;
  }
  return result;
}

T _enumValue<T extends Object>(
  YamlMap yaml,
  String key,
  String fixture,
  Map<String, T> spellings,
) {
  final raw = requiredString(yaml, key, fixture);
  final value = spellings[raw];
  if (value == null) {
    throw FixtureFieldException(
      fixture,
      key,
      'one of ${spellings.keys.join(', ')}, got "$raw"',
    );
  }
  return value;
}

int _int(YamlMap yaml, String key, String fixture) {
  final value = yaml[key];
  if (value is int) {
    return value;
  }
  throw FixtureFieldException(
    fixture,
    key,
    'an integer, got ${describe(value)}',
  );
}
