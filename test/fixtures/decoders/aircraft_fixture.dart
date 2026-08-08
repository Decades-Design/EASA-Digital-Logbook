import 'package:easa_digital_log/domain/model/aircraft.dart';
import 'package:easa_digital_log/domain/model/mass.dart';
import 'package:yaml/yaml.dart';

import '../fixture_loader.dart';
import 'fixture_fields.dart';

/// Snake-case YAML spellings for [AircraftEquipment].
///
/// Spelt out rather than derived from the enum name, so renaming a Dart value
/// cannot silently change what a fixture means.
const Map<String, AircraftEquipment> _equipment = <String, AircraftEquipment>{
  'retractable_undercarriage': AircraftEquipment.retractableUndercarriage,
  'variable_pitch_propeller': AircraftEquipment.variablePitchPropeller,
  'flaps': AircraftEquipment.flaps,
  'turbocharged': AircraftEquipment.turbocharged,
  'supercharged': AircraftEquipment.supercharged,
  'pressurised': AircraftEquipment.pressurised,
  'tailwheel': AircraftEquipment.tailwheel,
  'electronic_flight_instrument_system':
      AircraftEquipment.electronicFlightInstrumentSystem,
  'single_lever_power_control': AircraftEquipment.singleLeverPowerControl,
  'primary_flight_display': AircraftEquipment.primaryFlightDisplay,
  'multi_function_display_with_moving_map':
      AircraftEquipment.multiFunctionDisplayWithMovingMap,
  'integrated_autopilot': AircraftEquipment.integratedAutopilot,
};

const Map<String, AircraftCategory> _categories = <String, AircraftCategory>{
  'aeroplane': AircraftCategory.aeroplane,
  'helicopter': AircraftCategory.helicopter,
  'powered_lift': AircraftCategory.poweredLift,
  'glider': AircraftCategory.glider,
  'touring_motor_glider': AircraftCategory.touringMotorGlider,
  'airship': AircraftCategory.airship,
  'balloon': AircraftCategory.balloon,
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
    typeRatingDesignator: optionalString(yaml, 'type_rating_designator', name),
    requiresMultiCrew: requiredBool(yaml, 'requires_multi_crew', name),
    horsepower: _optionalInt(yaml, 'horsepower', name),
    maximumTakeoffMass: _mass(yaml, name),
    serviceCeilingFeet: _optionalInt(yaml, 'service_ceiling_feet', name),
    maximumOperatingAltitudeFeet: _optionalInt(
      yaml,
      'maximum_operating_altitude_feet',
      name,
    ),
    equipment: _equipmentSet(yaml, name),
  );
}

Set<AircraftEquipment> _equipmentSet(YamlMap yaml, String fixture) {
  final value = yaml['equipment'];
  if (value == null) {
    return const <AircraftEquipment>{};
  }
  if (value is! YamlList) {
    throw FixtureFieldException(
      fixture,
      'equipment',
      'a list, got ${describe(value)}',
    );
  }

  final result = <AircraftEquipment>{};
  for (final entry in value) {
    if (entry is! String) {
      throw FixtureFieldException(
        fixture,
        'equipment',
        'a list of strings, got an entry ${describe(entry)}',
      );
    }
    final item = _equipment[entry];
    if (item == null) {
      throw FixtureFieldException(
        fixture,
        'equipment',
        'a known attribute, got "$entry"',
      );
    }
    if (!result.add(item)) {
      throw FixtureFieldException(
        fixture,
        'equipment',
        'no duplicates, got "$entry" twice',
      );
    }
  }
  return result;
}

/// Reads `maximum_takeoff_mass_kg` or `maximum_takeoff_mass_lb`, keeping the
/// unit the fixture states. See [Mass] on why the unit is part of the fact.
Mass? _mass(YamlMap yaml, String fixture) {
  final kilograms = _optionalInt(yaml, 'maximum_takeoff_mass_kg', fixture);
  final pounds = _optionalInt(yaml, 'maximum_takeoff_mass_lb', fixture);

  if (kilograms != null && pounds != null) {
    throw FixtureFieldException(
      fixture,
      'maximum_takeoff_mass_kg',
      'only one of _kg and _lb — the certificated unit is the fact, and two '
          'values can disagree',
    );
  }
  if (kilograms != null) {
    return Mass.kilograms(kilograms);
  }
  if (pounds != null) {
    return Mass.pounds(pounds);
  }
  return null;
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
  final value = _optionalInt(yaml, key, fixture);
  if (value == null) {
    throw FixtureFieldException(fixture, key, 'an integer, got nothing');
  }
  return value;
}

int? _optionalInt(YamlMap yaml, String key, String fixture) {
  final value = yaml[key];
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  throw FixtureFieldException(
    fixture,
    key,
    'an integer, got ${describe(value)}',
  );
}
