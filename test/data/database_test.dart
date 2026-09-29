import 'dart:io';

import 'package:drift/native.dart';
import 'package:easa_digital_log/data/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  test('opens an in-memory database with all fifteen tables', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    expect(db.allTables, hasLength(15));
  });

  group('#90 crash-safety PRAGMA configuration', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('database_pragma_test');
    });

    tearDown(() => tempDir.delete(recursive: true));

    test(
      'a real on-disk database opens in WAL mode with synchronous=FULL',
      () async {
        // journal_mode=WAL is silently ignored for :memory: databases (SQLite
        // reports "memory" instead), so this needs a real file to prove.
        final dbFile = File(p.join(tempDir.path, 'test.sqlite'));
        final db = AppDatabase(NativeDatabase(dbFile));
        addTearDown(db.close);
        // Any statement forces beforeOpen to run.
        await db.customStatement('SELECT 1');

        final journalMode = await db
            .customSelect('PRAGMA journal_mode')
            .getSingle();
        final synchronous = await db
            .customSelect('PRAGMA synchronous')
            .getSingle();

        expect(journalMode.data.values.single, 'wal');
        // 2 == FULL; SQLite reports synchronous as an integer, not a name.
        expect(synchronous.data.values.single, 2);
      },
    );
  });
}
