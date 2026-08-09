import 'dart:io';

import 'package:yaml/yaml.dart';

/// Thrown when a fixture file cannot be found, naming the category and fixture
/// so the failure is actionable without opening the loader.
class FixtureNotFoundException implements Exception {
  const FixtureNotFoundException(this.category, this.name, this.path);

  final String category;
  final String name;
  final String path;

  @override
  String toString() =>
      'FixtureNotFoundException: no fixture "$name" in category "$category" '
      '(looked for $path)';
}

/// Thrown when a fixture file exists but does not decode into a usable
/// [YamlMap] — either the YAML itself is malformed, or it's well-formed but
/// its top-level shape is a list, a scalar, or anything other than a map.
///
/// #101: a fixture author's typo (bad indentation, an unclosed quote) must
/// fail with the file path attached, not with a bare parser error that
/// leaves them guessing which of dozens of fixture files is broken —
/// `package:yaml`'s own [FormatException] carries a line/column but never a
/// path, since [loadYaml] only ever sees a raw string.
class FixtureParseException implements Exception {
  const FixtureParseException(this.path, this.reason);

  final String path;
  final String reason;

  @override
  String toString() => 'FixtureParseException: could not parse $path: $reason';
}

const String _fixtureRoot = 'test/fixtures';

/// Loads the YAML fixture at `test/fixtures/<category>/<name>.yaml`.
///
/// Tests are run from the package root, so the path is resolved relative to
/// the current working directory.
YamlMap loadFixture(String category, String name) {
  final path = '$_fixtureRoot/$category/$name.yaml';
  final file = File(path);

  if (!file.existsSync()) {
    throw FixtureNotFoundException(category, name, path);
  }

  final Object? parsed;
  try {
    parsed = loadYaml(file.readAsStringSync());
  } on FormatException catch (e) {
    throw FixtureParseException(path, e.message);
  }

  if (parsed is! YamlMap) {
    throw FixtureParseException(
      path,
      'parsed as ${parsed.runtimeType}, expected a YAML map',
    );
  }

  return parsed;
}
