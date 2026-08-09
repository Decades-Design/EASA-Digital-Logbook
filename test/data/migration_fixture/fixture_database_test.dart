import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
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
    db.execute(
      'CREATE TABLE fixture_items (id TEXT NOT NULL, name TEXT NOT NULL, '
      'PRIMARY KEY (id))',
    );
    db.execute('INSERT INTO fixture_items (id, name) VALUES (?, ?)', [
      id,
      name,
    ]);
    db.execute('PRAGMA user_version = 1');
  } finally {
    db.close();
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

  test(
    'a migration step that throws leaves the original file intact',
    () async {
      _seedV1Database(dbFile.path, id: 'item-1', name: 'Original');
      final originalBytes = await dbFile.readAsBytes();

      // The failing open() throws before returning, so openWithBackup never
      // gets a reference to close — captured here instead, and closed in
      // teardown, so the native sqlite connection doesn't keep the file
      // handle open (which blocks the temp dir's deletion on Windows).
      _AlwaysFailsMigrationDatabase? failingDb;
      addTearDown(() => failingDb?.close());

      await expectLater(
        () => openWithBackup(dbFile, () async {
          // A database whose onUpgrade always throws, to force the failure
          // path without depending on addColumn actually failing.
          failingDb = _AlwaysFailsMigrationDatabase(NativeDatabase(dbFile));
          await failingDb!.customStatement('SELECT 1');
          return failingDb!;
        }),
        throwsA(anything),
      );

      expect(await dbFile.readAsBytes(), originalBytes);
    },
  );

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
