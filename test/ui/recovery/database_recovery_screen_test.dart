import 'dart:io';

import 'package:easa_digital_log/data/crash_recovery_snapshot.dart';
import 'package:easa_digital_log/ui/recovery/database_recovery_screen.dart';
import 'package:easa_digital_log/ui/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempDir;
  late File dbFile;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp(
      'database_recovery_screen_test',
    );
    dbFile = File(p.join(tempDir.path, 'live.sqlite'));
  });

  tearDown(() => tempDir.delete(recursive: true));

  Future<void> pumpScreen(
    WidgetTester tester, {
    Future<void> Function()? onRestored,
    String? detail,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: DatabaseRecoveryScreen(
          dbFile: dbFile,
          appSupportDirectory: tempDir,
          detail: detail,
          onRestored: onRestored ?? () async {},
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'with no automatic snapshot, only the manual file picker is offered',
    (tester) async {
      await pumpScreen(tester);

      expect(find.text('Restore last known-good state'), findsNothing);
      expect(find.text('Choose a backup file…'), findsOneWidget);
    },
  );

  testWidgets(
    'once an automatic snapshot exists, both restore options are offered',
    (tester) async {
      // Real dart:io calls made directly in a testWidgets body can hang --
      // TestWidgetsFlutterBinding's zone doesn't reliably deliver real OS
      // IO completion callbacks to pump()/pumpAndSettle() the way it does
      // synthetic frame timers. tester.runAsync briefly leaves that zone to
      // run real async code normally. Every direct dart:io call below does
      // the same.
      await tester.runAsync(
        () => crashRecoverySnapshotFile(tempDir).writeAsBytes([1, 2, 3]),
      );

      await pumpScreen(tester);

      expect(find.text('Restore last known-good state'), findsOneWidget);
      expect(find.text('Choose a backup file…'), findsOneWidget);
    },
  );

  testWidgets('shows the failure detail when one is given', (tester) async {
    await pumpScreen(tester, detail: 'PRAGMA quick_check reported a problem');

    expect(find.text('PRAGMA quick_check reported a problem'), findsOneWidget);
  });

  testWidgets('tapping the automatic-restore option opens a named confirmation '
      'dialog before touching anything', (tester) async {
    await tester.runAsync(
      () => crashRecoverySnapshotFile(tempDir).writeAsBytes([9, 9, 9]),
    );

    await pumpScreen(tester);

    await tester.tap(find.text('Restore last known-good state'));
    await tester.pumpAndSettle();

    expect(find.text('Restore this backup?'), findsOneWidget);
    // Nothing has happened yet -- the dialog gates the actual restore
    // (exercised directly, without the widget layer's fake-async
    // complications, by database_backup_test.dart).
    final existsAfterDialog = await tester.runAsync(() => dbFile.exists());
    expect(existsAfterDialog, isFalse);
  });

  testWidgets('cancelling the confirm dialog restores nothing', (tester) async {
    await tester.runAsync(
      () => crashRecoverySnapshotFile(tempDir).writeAsBytes([9, 9, 9]),
    );
    var restoredCallCount = 0;

    await pumpScreen(
      tester,
      onRestored: () async {
        restoredCallCount++;
      },
    );

    await tester.tap(find.text('Restore last known-good state'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    final existsAfterCancel = await tester.runAsync(() => dbFile.exists());
    expect(existsAfterCancel, isFalse);
    expect(restoredCallCount, 0);
  });
}
