/// Shared field readers for the fixture decoders.
///
/// Every reader fails loudly and names the fixture and the key. Nothing here
/// substitutes a default for a missing value: a silently defaulted
/// discriminator is indistinguishable from a deliberate one, and CLAUDE.md
/// rule 2 is that those facts cannot be recovered afterwards.
library;

import 'package:yaml/yaml.dart';

/// Thrown when a fixture field is missing or the wrong shape, naming the
/// fixture and the key so the failure is actionable without opening the YAML.
class FixtureFieldException implements Exception {
  const FixtureFieldException(this.fixture, this.key, this.expected);

  final String fixture;
  final String key;
  final String expected;

  @override
  String toString() =>
      'FixtureFieldException: fixture "$fixture" key "$key" — '
      'expected $expected';
}

/// Describes an unexpected value for an error message.
String describe(Object? value) =>
    value == null ? 'nothing' : '${value.runtimeType} ($value)';

bool requiredBool(YamlMap yaml, String key, String fixture) {
  final value = optionalBool(yaml, key, fixture);
  if (value == null) {
    throw FixtureFieldException(fixture, key, 'a boolean, got nothing');
  }
  return value;
}

bool? optionalBool(YamlMap yaml, String key, String fixture) {
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
    'a boolean, got ${describe(value)}',
  );
}

String requiredString(YamlMap yaml, String key, String fixture) {
  final value = optionalString(yaml, key, fixture);
  if (value == null) {
    throw FixtureFieldException(fixture, key, 'a string, got nothing');
  }
  return value;
}

String? optionalString(YamlMap yaml, String key, String fixture) {
  final value = yaml[key];
  if (value == null) {
    return null;
  }
  if (value is String) {
    return value;
  }
  throw FixtureFieldException(fixture, key, 'a string, got ${describe(value)}');
}

YamlMap requiredMap(YamlMap yaml, String key, String fixture) {
  final value = optionalMap(yaml, key, fixture);
  if (value == null) {
    throw FixtureFieldException(fixture, key, 'a map, got nothing');
  }
  return value;
}

YamlMap? optionalMap(YamlMap yaml, String key, String fixture) {
  final value = yaml[key];
  if (value == null) {
    return null;
  }
  if (value is YamlMap) {
    return value;
  }
  throw FixtureFieldException(fixture, key, 'a map, got ${describe(value)}');
}

int requiredInt(YamlMap yaml, String key, String fixture) {
  final value = optionalInt(yaml, key, fixture);
  if (value == null) {
    throw FixtureFieldException(fixture, key, 'an integer, got nothing');
  }
  return value;
}

int? optionalInt(YamlMap yaml, String key, String fixture) {
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

List<String> requiredStringList(YamlMap yaml, String key, String fixture) {
  final value = yaml[key];
  if (value is! YamlList) {
    throw FixtureFieldException(
      fixture,
      key,
      'a list of strings, got ${describe(value)}',
    );
  }
  return [
    for (final item in value)
      if (item is String)
        item
      else
        throw FixtureFieldException(
          fixture,
          key,
          'a list of strings, got an entry ${describe(item)}',
        ),
  ];
}
