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

  final parsed = loadYaml(file.readAsStringSync());
  if (parsed is! YamlMap) {
    throw StateError(
      'Fixture $path parsed as ${parsed.runtimeType}, expected a YAML map.',
    );
  }

  return parsed;
}
