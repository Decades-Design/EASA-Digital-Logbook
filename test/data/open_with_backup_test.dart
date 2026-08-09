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

  test(
    'on success, deletes the backup and leaves the file content-preserving',
    () async {
      await dbFile.writeAsString('original content');

      final result = await openWithBackup(dbFile, () async {
        await dbFile.writeAsString('modified content');
        return 'ok';
      });

      expect(result, 'ok');
      expect(await dbFile.readAsString(), 'modified content');
      expect(await File('${dbFile.path}.backup').exists(), isFalse);
    },
  );

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

  test(
    'works when the file does not exist yet (first run, nothing to back up)',
    () async {
      final result = await openWithBackup(dbFile, () async {
        await dbFile.writeAsString('created');
        return 'ok';
      });

      expect(result, 'ok');
      expect(await dbFile.readAsString(), 'created');
    },
  );

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
