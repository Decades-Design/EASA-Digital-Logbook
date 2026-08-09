# Schema Migration Framework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make schema changes to `AppDatabase` safe: a pre-migration file backup with
automatic rollback, a committed schema snapshot with a CI check that catches an unversioned
schema change, and a real, tested migration path — proven against a throwaway fixture schema
since `AppDatabase` itself has nothing pending to migrate yet.

**Architecture:** A generic `openWithBackup` helper wraps any database open in a
copy-before/delete-or-restore-after sequence. `drift_dev schema dump` produces the committed
JSON snapshot; a hand-rolled `tool/check_schema_snapshot.dart` (matching this project's existing
`check_layering.dart`/`check_domain_coverage.dart` style) diffs it against the current schema in
CI. A small fixture-only Drift database proves the actual migration mechanics.

**Tech Stack:** `drift`/`drift_dev` (already installed, 2.34.x) — no new dependency.

## Global Constraints

- The pre-migration backup is internal-only: no restore UI, no retention policy, not #37. A
  private mechanism whose only job is guaranteeing the on-disk file is never left corrupted.
- `AppDatabase.schemaVersion` stays at `1` — nothing in this plan changes the real app schema.
  The migration machinery is proven against a throwaway fixture schema under `test/` instead.
- `drift_schemas/*.json` snapshot files are committed to git — unlike `.g.dart` output, they are
  the only record of an old schema's shape and cannot be regenerated later.
- The exact `drift_dev schema dump`/`Migrator.addColumn`/`MigrationStrategy` signatures below
  were confirmed by reading the installed `drift`/`drift_dev` 2.34.x source directly (not
  guessed) — `dart run drift_dev schema dump <input.dart> <output-dir>`; `OnUpgrade` is
  `Future<void> Function(Migrator m, int from, int to)`; `Migrator.addColumn(TableInfo table,
  GeneratedColumn column)`. If a future `drift`/`drift_dev` upgrade changes these, that's normal
  API drift — adjust the call site, not the design.
- Everything here must run via PowerShell, same as every other check in this project (`dart`/
  `flutter` are puro shims that only resolve there) — `tool/check_schema_snapshot.dart` shells
  out to `dart run drift_dev ...` as a subprocess, which only resolves under the same shell.

---

## Task 1: `openWithBackup` — the generic backup/rollback wrapper

**Files:**
- Create: `lib/data/open_with_backup.dart`
- Test: `test/data/open_with_backup_test.dart`

**Interfaces:**
- Produces: `Future<T> openWithBackup<T>(File dbFile, Future<T> Function() open)`. Task 2's
  `openAppDatabase` and Task 3's fixture test both call this directly.

`open` is fully caller-controlled — this keeps the wrapper generic without needing to
hand-subclass `GeneratedDatabase` (a codegen-produced base class not meant to be subclassed by
hand) just to test it. The failure path is tested with a plain throwing callback; no fake
database needed.

- [ ] **Step 1: Write the failing tests**

Create `test/data/open_with_backup_test.dart`:

```dart
import 'dart:io';

import 'package:easa_digital_log/data/open_with_backup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('open_with_backup_test');
    dbFile = File(p.join(tempDir.path, 'test.sqlite'));
  });

  tearDown(() => tempDir.delete(recursive: true));

  test('on success, deletes the backup and leaves the file content-preserving', () async {
    await dbFile.writeAsString('original content');

    final result = await openWithBackup(dbFile, () async {
      await dbFile.writeAsString('modified content');
      return 'ok';
    });

    expect(result, 'ok');
    expect(await dbFile.readAsString(), 'modified content');
    expect(await File('${dbFile.path}.backup').exists(), isFalse);
  });

  test('on failure, restores the original file and rethrows', () async {
    await dbFile.writeAsString('original content');

    await expectLater(
      () => openWithBackup(dbFile, () async {
        await dbFile.writeAsString('corrupted mid-write');
        throw StateError('migration failed');
      }),
      throwsStateError,
    );

    expect(await dbFile.readAsString(), 'original content');
    expect(await File('${dbFile.path}.backup').exists(), isFalse);
  });

  test('works when the file does not exist yet (first run, nothing to back up)', () async {
    final result = await openWithBackup(dbFile, () async {
      await dbFile.writeAsString('created');
      return 'ok';
    });

    expect(result, 'ok');
    expect(await dbFile.readAsString(), 'created');
  });

  test('propagates the original exception unchanged', () async {
    await dbFile.writeAsString('original content');

    await expectLater(
      () => openWithBackup(dbFile, () async {
        throw ArgumentError('a specific error');
      }),
      throwsArgumentError,
    );
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/open_with_backup_test.dart`
Expected: FAIL — `open_with_backup.dart` does not exist.

- [ ] **Step 3: Implement `openWithBackup`**

Create `lib/data/open_with_backup.dart`:

```dart
import 'dart:io';

/// Copies [dbFile] to a sibling `.backup` file before calling [open]. On
/// success, deletes the backup. On failure, restores [dbFile] from the
/// backup and rethrows — [dbFile] is never left in a partially-written
/// state, whatever [open] does to it.
///
/// [open] is fully caller-controlled: it decides what "opening" means
/// (construct a database, run a query to force migrations, whatever) and
/// returns whatever it wants. This keeps the wrapper generic without
/// needing to model a specific database type.
Future<T> openWithBackup<T>(File dbFile, Future<T> Function() open) async {
  final backupFile = File('${dbFile.path}.backup');

  if (await dbFile.exists()) {
    await dbFile.copy(backupFile.path);
  }

  try {
    final result = await open();
    if (await backupFile.exists()) {
      await backupFile.delete();
    }
    return result;
  } catch (_) {
    if (await backupFile.exists()) {
      if (await dbFile.exists()) {
        await dbFile.delete();
      }
      await backupFile.rename(dbFile.path);
    }
    rethrow;
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/open_with_backup_test.dart`
Expected: PASS

- [ ] **Step 5: Full local verification and commit**

```powershell
dart format --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test
```

```bash
git add lib/data/open_with_backup.dart test/data/open_with_backup_test.dart
git commit -m "feat: generic pre-migration backup/rollback wrapper (#36)"
```

---

## Task 2: Committed schema snapshot and the CI check

**Files:**
- Create: `drift_schemas/drift_schema_v1.json` (generated, then committed)
- Create: `tool/check_schema_snapshot.dart`
- Modify: `lib/data/database.dart` (add `openAppDatabase`)
- Modify: `.github/workflows/ci.yaml`
- Test: `test/tool/check_schema_snapshot_test.dart`

**Interfaces:**
- Consumes: `openWithBackup` (Task 1).
- Produces: `Future<AppDatabase> openAppDatabase(File dbFile)`; `bool schemasMatch(String
  dumpedJson, String committedJson)` (the pure, unit-testable comparison `main()` uses).

- [ ] **Step 1: Generate and commit the real v1 snapshot**

Run:
```powershell
dart run drift_dev schema dump lib/data/database.dart drift_schemas
```
Expected: writes `drift_schemas/drift_schema_v1.json`. This file is committed, not gitignored —
unlike `.g.dart` output, it's the only record of what v1 actually looked like.

- [ ] **Step 2: Add `openAppDatabase` to `database.dart`**

In `lib/data/database.dart`, add these imports at the top:

```dart
import 'dart:io';

import 'open_with_backup.dart';
```

Add this function at the end of the file, after the `AppDatabase` class:

```dart
/// Opens [dbFile] as an [AppDatabase], guarded by [openWithBackup]. Querying
/// once (`SELECT 1`) forces drift's open-and-migrate sequence to run and
/// surface any error here, rather than lazily on whatever query a caller
/// happens to run first.
Future<AppDatabase> openAppDatabase(File dbFile) {
  return openWithBackup(dbFile, () async {
    final db = AppDatabase(NativeDatabase(dbFile));
    await db.customStatement('SELECT 1');
    return db;
  });
}
```

Add `import 'package:drift/native.dart';` to the top of `database.dart` too, for
`NativeDatabase`.

- [ ] **Step 3: Write the failing test for the comparison logic**

Create `test/tool/check_schema_snapshot_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_schema_snapshot.dart';

void main() {
  group('schemasMatch', () {
    test('true for identical JSON', () {
      const json = '{"a": 1, "b": [1, 2, 3]}';
      expect(schemasMatch(json, json), isTrue);
    });

    test('true when formatting differs but content is the same', () {
      const a = '{"a": 1, "b": 2}';
      const b = '{\n  "b": 2,\n  "a": 1\n}';
      expect(schemasMatch(a, b), isTrue);
    });

    test('false when a value differs', () {
      const a = '{"a": 1}';
      const b = '{"a": 2}';
      expect(schemasMatch(a, b), isFalse);
    });

    test('false when a key is added or removed', () {
      const a = '{"a": 1}';
      const b = '{"a": 1, "b": 2}';
      expect(schemasMatch(a, b), isFalse);
    });

    test('false when a list differs', () {
      const a = '{"a": [1, 2]}';
      const b = '{"a": [1, 3]}';
      expect(schemasMatch(a, b), isFalse);
    });
  });
}
```

- [ ] **Step 4: Run test to verify it fails**

Run: `flutter test test/tool/check_schema_snapshot_test.dart`
Expected: FAIL — `tool/check_schema_snapshot.dart` does not exist.

- [ ] **Step 5: Implement the check tool**

Create `tool/check_schema_snapshot.dart`:

```dart
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
  final tempDir = await Directory.systemTemp.createTemp('check_schema_snapshot');
  try {
    final result = await Process.run('dart', [
      'run',
      'drift_dev',
      'schema',
      'dump',
      _databaseSource,
      tempDir.path,
    ]);
    if (result.exitCode != 0) {
      stderr.writeln('check_schema_snapshot: failed to dump the current schema:');
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
        '  dart run drift_dev schema dump $_databaseSource $_snapshotsDir\n'
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
        '  dart run drift_dev schema dump $_databaseSource $_snapshotsDir\n'
        'then commit the result.',
      );
      exit(1);
    }

    stdout.writeln('check_schema_snapshot: drift_schema_v$version.json is up to date.');
  } finally {
    await tempDir.delete(recursive: true);
  }
}
```

- [ ] **Step 6: Run test to verify it passes**

Run: `flutter test test/tool/check_schema_snapshot_test.dart`
Expected: PASS

- [ ] **Step 7: Run the tool itself against the real, just-committed snapshot**

Run: `dart run tool/check_schema_snapshot.dart`
Expected: `check_schema_snapshot: drift_schema_v1.json is up to date.`, exit 0 — this is the
tool's own end-to-end proof, checking the file it wrote in Step 1 against itself.

- [ ] **Step 8: Wire the check into CI**

In `.github/workflows/ci.yaml`, add this step after the existing `Check domain coverage` step
(same file structure this project already uses for `check_layering.dart`/
`check_domain_types.dart`):

```yaml
      - name: Check schema snapshot
        run: dart run tool/check_schema_snapshot.dart
```

- [ ] **Step 9: Full local verification and commit**

```powershell
dart format --set-exit-if-changed .
flutter analyze --fatal-infos
dart run tool/check_layering.dart
dart run tool/check_domain_types.dart
flutter test
```

```bash
git add drift_schemas/ tool/check_schema_snapshot.dart lib/data/database.dart test/tool/check_schema_snapshot_test.dart .github/workflows/ci.yaml
git commit -m "feat: commit the v1 schema snapshot and enforce it in CI (#36)"
```

---

## Task 3: Fixture schema — proving the migration mechanism end-to-end

**Files:**
- Create: `test/data/migration_fixture/fixture_database.dart`
- Create: `test/data/migration_fixture/fixture_database_test.dart`
- Create: `test/data/migration_fixture/drift_schemas/drift_schema_v1.json` (generated)
- Create: `test/data/migration_fixture/drift_schemas/drift_schema_v2.json` (generated)

**Interfaces:**
- Consumes: `openWithBackup` (Task 1).
- Produces: nothing later tasks depend on — this is the proof, not new production surface.

A tiny, throwaway database: one table, two versions. v1 has `id`/`name`; v2 adds a nullable
`notes` column — real enough to prove an actual `ALTER TABLE` migration works, small enough to
read in one sitting.

- [ ] **Step 1: Define the fixture database at v2**

Create `test/data/migration_fixture/fixture_database.dart`:

```dart
import 'package:drift/drift.dart';

part 'fixture_database.g.dart';

@DataClassName('FixtureItemRow')
class FixtureItemsTable extends Table {
  @override
  String get tableName => 'fixture_items';

  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get notes => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [FixtureItemsTable])
class FixtureDatabase extends _$FixtureDatabase {
  FixtureDatabase(super.executor);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (Migrator m, int from, int to) async {
      if (from == 1 && to == 2) {
        await m.addColumn(fixtureItemsTable, fixtureItemsTable.notes);
      }
    },
  );
}
```

- [ ] **Step 2: Generate code and both schema snapshots**

Run:
```powershell
flutter pub run build_runner build
```
Expected: generates `test/data/migration_fixture/fixture_database.g.dart` (gitignored, like
every other `.g.dart` — not committed).

The v2 snapshot comes from the current source:
```powershell
dart run drift_dev schema dump test/data/migration_fixture/fixture_database.dart test/data/migration_fixture/drift_schemas
```
Expected: writes `test/data/migration_fixture/drift_schemas/drift_schema_v2.json`.

The v1 snapshot can't be dumped from source (the table class only ever represents the current
version) — write it by hand, matching what v1 actually looked like (no `notes` column). Create
`test/data/migration_fixture/drift_schemas/drift_schema_v1.json`:

```json
{
  "_meta": {
    "description": "This file contains a serialized version of schema entities for drift.",
    "version": "1.2.0"
  },
  "options": {
    "store_date_time_values_as_text": false
  },
  "entities": [
    {
      "id": "table(fixture_items)",
      "references": [],
      "type": "table",
      "data": {
        "name": "fixture_items",
        "was_declared_in_moor": false,
        "columns": [
          {
            "name": "id",
            "getter_name": "id",
            "moor_type": "string",
            "nullable": false,
            "customConstraints": null,
            "defaultConstraints": null,
            "default_dart": null,
            "dsl_features": []
          },
          {
            "name": "name",
            "getter_name": "name",
            "moor_type": "string",
            "nullable": false,
            "customConstraints": null,
            "defaultConstraints": null,
            "default_dart": null,
            "dsl_features": []
          }
        ],
        "is_virtual": false,
        "without_rowid": false,
        "constraints": [],
        "explicit_pk": ["id"]
      }
    }
  ]
}
```

Both committed snapshot files are test fixtures, not generated output — commit them.

- [ ] **Step 3: Write the failing migration test**

Create `test/data/migration_fixture/fixture_database_test.dart`:

```dart
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:easa_digital_log/data/open_with_backup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

import 'fixture_database.dart';

/// Creates a v1-shaped database file directly with sqlite3 — the only way
/// to get a "v1 database" to migrate from, since the Dart table class only
/// ever represents the current (v2) schema.
void _seedV1Database(String path, {required String id, required String name}) {
  final db = sqlite3.sqlite3.open(path);
  try {
    db.execute('CREATE TABLE fixture_items (id TEXT NOT NULL, name TEXT NOT NULL, '
        'PRIMARY KEY (id))');
    db.execute('INSERT INTO fixture_items (id, name) VALUES (?, ?)', [id, name]);
    db.execute('PRAGMA user_version = 1');
  } finally {
    db.dispose();
  }
}

void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('fixture_database_test');
    dbFile = File(p.join(tempDir.path, 'fixture.sqlite'));
  });

  tearDown(() => tempDir.delete(recursive: true));

  test('migrating a v1 database to v2 preserves existing data', () async {
    _seedV1Database(dbFile.path, id: 'item-1', name: 'Original');

    final db = await openWithBackup(dbFile, () async {
      final database = FixtureDatabase(NativeDatabase(dbFile));
      await database.customStatement('SELECT 1');
      return database;
    });
    addTearDown(db.close);

    final rows = await db.select(db.fixtureItemsTable).get();
    expect(rows, hasLength(1));
    expect(rows.single.id, 'item-1');
    expect(rows.single.name, 'Original');
    expect(rows.single.notes, isNull);
  });

  test('a migration step that throws leaves the original file intact', () async {
    _seedV1Database(dbFile.path, id: 'item-1', name: 'Original');
    final originalBytes = await dbFile.readAsBytes();

    await expectLater(
      () => openWithBackup(dbFile, () async {
        // A database whose onUpgrade always throws, to force the failure
        // path without depending on addColumn actually failing.
        final database = _AlwaysFailsMigrationDatabase(NativeDatabase(dbFile));
        await database.customStatement('SELECT 1');
        return database;
      }),
      throwsA(anything),
    );

    expect(await dbFile.readAsBytes(), originalBytes);
  });

  test('the backup file is gone after a successful migration', () async {
    _seedV1Database(dbFile.path, id: 'item-1', name: 'Original');

    final db = await openWithBackup(dbFile, () async {
      final database = FixtureDatabase(NativeDatabase(dbFile));
      await database.customStatement('SELECT 1');
      return database;
    });
    addTearDown(db.close);

    expect(await File('${dbFile.path}.backup').exists(), isFalse);
  });
}

/// Same schema as [FixtureDatabase] but always throws during upgrade — used
/// only to prove the rollback path without relying on a real migration step
/// failing.
class _AlwaysFailsMigrationDatabase extends FixtureDatabase {
  _AlwaysFailsMigrationDatabase(super.executor);

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onUpgrade: (Migrator m, int from, int to) async {
      throw StateError('simulated migration failure');
    },
  );
}
```

Add `path` and `sqlite3` to `dev_dependencies` if not already present — check first:

```powershell
flutter pub add -d path sqlite3
```
`sqlite3` is already a transitive dependency (via `drift`), but must be a **direct**
`dev_dependency` here to be importable from this test file. `path` is very likely already
present as a transitive dependency too; `flutter pub add` is a no-op if it's already direct.

- [ ] **Step 4: Run test to verify it fails**

Run: `flutter test test/data/migration_fixture/fixture_database_test.dart`
Expected: FAIL — `fixture_database.g.dart` doesn't exist yet if Step 2 wasn't completed, or the
test fails naturally if it was. If Step 2 was already done, this step should largely pass except
for whatever a fresh look reveals — treat any failure here as real signal, not as expected
scaffolding (unlike the M2/#35 "intentionally incomplete class" pattern, nothing here is
deliberately left unbuilt).

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/data/migration_fixture/fixture_database_test.dart`
Expected: PASS — all three tests, proving: data survives a real migration, a thrown migration
step leaves the original file byte-for-byte intact, and the backup file is cleaned up on
success.

- [ ] **Step 6: Full local verification and commit**

```powershell
dart format --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test
```

```bash
git add test/data/migration_fixture/ pubspec.yaml pubspec.lock
git commit -m "test: prove the migration mechanism against a fixture schema (#36)"
```

---

## Task 4: ADR-0010 — migration safety strategy

**Files:**
- Create: `docs/adr/0010-migration-safety.md`
- Modify: `docs/adr/README.md` (index row)

Records the two decisions from this plan that are genuinely hard to reverse once real user data
exists on a real device: the two-layer rollback (SQL transaction + file-level backup) and the
internal-only backup scope (not #37).

- [ ] **Step 1: Write the ADR**

Create `docs/adr/0010-migration-safety.md`, following the existing ADR format (see
`docs/adr/template.md` and `docs/adr/0005-offline-first.md` for the established style —
Context/Decision/Alternatives considered/Consequences):

```markdown
# ADR-0010: Two-layer migration safety, backup scoped to migration only

**Status:** Accepted
**Date:** 2026-08-09

## Context

The database holds the pilot's legal record. A botched schema migration is data loss a fresh
install cannot recover from — #36's whole premise. Two related decisions needed settling before
building the migration framework: how many layers of protection a migration gets, and whether
the pre-migration backup this needs is the same thing as #37's (not yet designed) backup/restore
feature.

## Decision

Two independent layers protect a migration, not one:

1. SQLite's own transactional DDL — a migration step that throws partway through already rolls
   back at the SQL level, restoring the pre-migration schema and data with no extra code.
2. A file-level backup (`lib/data/open_with_backup.dart`), copied before opening/migrating and
   restored on any exception. This covers what a transaction can't: the app being killed
   mid-write, or a migration that throws no exception but is simply wrong.

The backup is internal-only — no restore UI, no retention policy, not #37. #37 designs its own
user-facing backup/restore feature later, informed by nothing this ADR commits to.

## Alternatives considered

Relying on SQL transactional rollback alone. Rejected: it protects against a migration that
*fails loudly*, not one that fails silently or is interrupted by the process dying — exactly the
failure modes a legal record on a personal device is most exposed to (a phone losing power or an
OS killing the app mid-write).

Building the file backup as a first cut of #37's general backup/restore feature. Rejected: #37
has no design yet, and guessing at its shape now risks building the wrong reusable primitive
before the actual requirements (retention, restore UI, what "a backup" even means to a pilot) are
known. Keeping this one purpose-built and narrow costs nothing and commits to nothing.

## Consequences

`openAppDatabase`/`openWithBackup` is the only sanctioned way to open the real database file —
any other call site that constructs `AppDatabase(NativeDatabase(file))` directly bypasses the
safety net. #37, whenever it happens, is free to design its own thing without being constrained
by this one.
```

- [ ] **Step 2: Update the ADR index**

Read `docs/adr/README.md` and add a row for ADR-0010 following the existing table's format.

- [ ] **Step 3: Full local verification and commit**

```powershell
dart format --set-exit-if-changed .
flutter test
```

```bash
git add docs/adr/0010-migration-safety.md docs/adr/README.md
git commit -m "docs: record the migration safety strategy (ADR-0010, #36)"
```

---

## Self-Review

**Spec coverage:** Schema versioning + committed snapshots — Task 2. Migration tests opening a
v(n-1) database and asserting integrity — Task 3. Pre-migration backup retained until confirmed
— Task 1 (generic mechanism) + Task 2 (`openAppDatabase` wiring). CI failing on an unversioned
schema change — Task 2. Rollback rather than a half-migrated database — Task 1 (file-level) +
Task 3 (proves SQL-level rollback too, via the "throws leaves file intact" test). The ADR — Task
4. Every Non-goal (backup/restore UI, a real `AppDatabase` schema change, encryption) has no
task — correctly, since the spec excludes them.

**Placeholder scan:** No stub methods, no invented product schema change. Task 3's hand-written
v1 snapshot JSON is a genuine fixture value, not a placeholder — it's what a real `schema dump`
of that exact table shape produces, written by hand only because there's no v1 source left to
dump it from.

**Type consistency:** `openWithBackup<T>(File, Future<T> Function())` (Task 1) is called
identically in Task 2's `openAppDatabase` and Task 3's fixture tests. `schemasMatch` (Task 2) is
the one function both `check_schema_snapshot_test.dart` and `main()` use — no duplicate
comparison logic.
