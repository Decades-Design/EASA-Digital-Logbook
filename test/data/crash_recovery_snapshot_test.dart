import 'dart:io';

import 'package:drift/native.dart';
import 'package:easa_digital_log/data/crash_recovery_snapshot.dart';
import 'package:easa_digital_log/data/database.dart';
import 'package:easa_digital_log/data/repositories/aircraft_repository.dart';
import 'package:easa_digital_log/domain/model/aircraft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempDir;
  late AppDatabase db;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'crash_recovery_snapshot_test',
    );
    db = AppDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
    await tempDir.delete(recursive: true);
  });

  test('takes a snapshot at the fixed rotating path', () async {
    await takeCrashRecoverySnapshot(db, tempDir);

    expect(await crashRecoverySnapshotFile(tempDir).exists(), isTrue);
  });

  test(
    'overwrites the previous snapshot rather than accumulating history',
    () async {
      await takeCrashRecoverySnapshot(db, tempDir);
      final firstSnapshotBytes = await crashRecoverySnapshotFile(
        tempDir,
      ).readAsBytes();

      await AircraftRepository(db).upsert(
        const Aircraft(
          registration: 'G-ABCD',
          manufacturer: 'Cessna',
          model: '152',
          category: AircraftCategory.aeroplane,
          engineType: EngineType.piston,
          engineCount: 1,
          operatingSurface: OperatingSurface.land,
          requiresMultiCrew: false,
        ),
      );
      await takeCrashRecoverySnapshot(db, tempDir);
      final secondSnapshotBytes = await crashRecoverySnapshotFile(
        tempDir,
      ).readAsBytes();

      // Only one file exists at the fixed path -- the directory has nothing
      // else -- and its content reflects the second, later state.
      expect(tempDir.listSync(), hasLength(1));
      expect(secondSnapshotBytes, isNot(equals(firstSnapshotBytes)));
    },
  );

  test('a snapshot failure is swallowed, not thrown -- a missed safety net, '
      'never a reason to block startup', () async {
    // A destination whose parent "directory" is actually a plain file
    // forces exportDatabaseBackup's own directory creation to fail.
    final blockedPath = '${tempDir.path}/not-a-directory';
    await File(blockedPath).writeAsString('blocking');

    await expectLater(
      takeCrashRecoverySnapshot(db, Directory(blockedPath)),
      completes,
    );
  });
}
