/// Enforces that `drift_schemas/drift_schema_v<N>.json` (N = AppDatabase's
/// current schemaVersion) matches what the current code would actually
/// produce — the signal that a table changed without a version bump and a
/// fresh committed snapshot. Mirrors `check_layering.dart`/
/// `check_domain_coverage.dart`'s "small hand-rolled guard wired into CI"
/// style.
///
/// Run: `dart run tool/check_schema_snapshot.dart`
library;

import 'dart:convert';
import 'dart:io';

const String _databaseSource = 'lib/data/database.dart';
const String _snapshotsDir = 'drift_schemas';
final RegExp _snapshotFilename = RegExp(r'drift_schema_v(\d+)\.json$');

/// True if [dumpedJson] and [committedJson] decode to the same structure,
/// ignoring formatting differences (key order, whitespace).
bool schemasMatch(String dumpedJson, String committedJson) {
  return _deepEquals(jsonDecode(dumpedJson), jsonDecode(committedJson));
}

bool _deepEquals(Object? a, Object? b) {
  if (a is Map && b is Map) {
    if (a.length != b.length) {
      return false;
    }
    for (final key in a.keys) {
      if (!b.containsKey(key) || !_deepEquals(a[key], b[key])) {
        return false;
      }
    }
    return true;
  }
  if (a is List && b is List) {
    if (a.length != b.length) {
      return false;
    }
    for (var i = 0; i < a.length; i++) {
      if (!_deepEquals(a[i], b[i])) {
        return false;
      }
    }
    return true;
  }
  return a == b;
}

Future<void> main() async {
  final tempDir = await Directory.systemTemp.createTemp(
    'check_schema_snapshot',
  );
  try {
    // `dart run drift_dev ...` fails here — this project's `dart`/`flutter`
    // are puro shims, and plain `dart` can't find the Flutter SDK
    // (CLAUDE.md's documented build_runner gotcha applies to drift_dev's
    // CLI too). `flutter pub run` resolves correctly. `runInShell: true` is
    // required on Windows for Process.run to find a PATH-shimmed `flutter`
    // executable at all (it's a .bat wrapper, not resolved by a direct
    // executable lookup).
    final result = await Process.run('flutter', [
      'pub',
      'run',
      'drift_dev',
      'schema',
      'dump',
      _databaseSource,
      tempDir.path,
    ], runInShell: true);
    if (result.exitCode != 0) {
      stderr.writeln(
        'check_schema_snapshot: failed to dump the current schema:',
      );
      stderr.writeln(result.stderr);
      exit(1);
    }

    final dumped = tempDir
        .listSync()
        .whereType<File>()
        .where((f) => _snapshotFilename.hasMatch(f.path))
        .toList();
    if (dumped.length != 1) {
      stderr.writeln(
        'check_schema_snapshot: expected exactly one dumped schema file, '
        'found ${dumped.length}.',
      );
      exit(1);
    }

    final dumpedFile = dumped.single;
    final version = _snapshotFilename.firstMatch(dumpedFile.path)!.group(1);
    final committedFile = File('$_snapshotsDir/drift_schema_v$version.json');

    if (!committedFile.existsSync()) {
      stderr.writeln(
        'check_schema_snapshot: schemaVersion is $version but '
        '${committedFile.path} does not exist. Run:\n'
        '  flutter pub run drift_dev schema dump $_databaseSource $_snapshotsDir\n'
        'and commit the result.',
      );
      exit(1);
    }

    final dumpedJson = await dumpedFile.readAsString();
    final committedJson = await committedFile.readAsString();

    if (!schemasMatch(dumpedJson, committedJson)) {
      stderr.writeln(
        'check_schema_snapshot: the current schema no longer matches '
        '${committedFile.path}. If this is an intentional change, bump '
        'AppDatabase.schemaVersion, add an onUpgrade step, and regenerate '
        'the snapshot:\n'
        '  flutter pub run drift_dev schema dump $_databaseSource $_snapshotsDir\n'
        'then commit the result.',
      );
      exit(1);
    }

    stdout.writeln(
      'check_schema_snapshot: drift_schema_v$version.json is up to date.',
    );
  } finally {
    await tempDir.delete(recursive: true);
  }
}
