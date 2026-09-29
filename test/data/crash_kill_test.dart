import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easa_digital_log/data/database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// #90 AC3/AC4: "a test simulating process kill mid-transaction, asserting
/// the database opens clean with no partial write," specifically for a
/// single write and for an import batch. Spawns the real subprocess in
/// `test/support/crash_kill_helper.dart` and SIGKILLs it once it signals a
/// write is issued but uncommitted, then reopens through the app's real
/// `openAppDatabase` path and asserts nothing partial survived. This proves
/// the actual guarantee WAL + synchronous=FULL (#90, ADR-0013) gives, not a
/// simulation of it.
void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('crash_kill_test');
    dbFile = File(p.join(tempDir.path, 'live.sqlite'));
  });

  tearDown(() => tempDir.delete(recursive: true));

  Future<void> runAndKill(String mode) async {
    final process = await Process.start('dart', [
      'test/support/crash_kill_helper.dart',
      dbFile.path,
      mode,
    ]);

    final ready = Completer<void>();
    final stderrBuffer = StringBuffer();
    final stdoutSub = process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          if (line.trim() == 'READY' && !ready.isCompleted) {
            ready.complete();
          }
        });
    final stderrSub = process.stderr
        .transform(utf8.decoder)
        .listen(stderrBuffer.write);

    try {
      await ready.future.timeout(
        const Duration(seconds: 20),
        onTimeout: () => throw StateError(
          'crash_kill_helper never signalled READY. stderr:\n$stderrBuffer',
        ),
      );
    } finally {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
      await stdoutSub.cancel();
      await stderrSub.cancel();
    }
  }

  test(
    'AC3: killing a process mid-single-write leaves no partial write, and '
    'the database opens clean afterwards',
    () async {
      await runAndKill('single-write');

      final db = await openAppDatabase(dbFile);
      addTearDown(db.close);

      final quickCheck = await db.customSelect('PRAGMA quick_check').getSingle();
      expect(quickCheck.data.values.single, 'ok');

      final flightRows = await db.select(db.flightsTable).get();
      expect(flightRows, isEmpty);
      final legRows = await db.select(db.flightRouteLegsTable).get();
      expect(legRows, isEmpty);

      // The precondition write (the aircraft, committed before the killed
      // transaction started) did survive -- confirms the kill genuinely
      // landed mid-scenario rather than before anything ran at all.
      final aircraftRows = await db.select(db.aircraftsTable).get();
      expect(aircraftRows, hasLength(1));
    },
    // Spawns a real subprocess and waits on real OS signal delivery.
    timeout: const Timeout(Duration(seconds: 30)),
  );

  test(
    'AC4: killing a process mid-import-batch leaves no partial write, and '
    'the database opens clean afterwards',
    () async {
      await runAndKill('import-batch');

      final db = await openAppDatabase(dbFile);
      addTearDown(db.close);

      final quickCheck = await db.customSelect('PRAGMA quick_check').getSingle();
      expect(quickCheck.data.values.single, 'ok');

      final flightRows = await db.select(db.flightsTable).get();
      expect(flightRows, isEmpty);
      final batchRows = await db.select(db.importBatchesTable).get();
      expect(batchRows, isEmpty);

      final aircraftRows = await db.select(db.aircraftsTable).get();
      expect(aircraftRows, hasLength(1));
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );
}
