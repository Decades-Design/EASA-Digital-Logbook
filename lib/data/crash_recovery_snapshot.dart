import 'dart:io';

import 'package:flutter/foundation.dart';

import 'database.dart';
import 'database_backup.dart';

/// #90 AC5: gives startup corruption detection (`bootstrapRealAppDatabase`)
/// something to route a restore to even for a pilot who has never used
/// #37's own user-triggered, share-sheeted export. A single rotating local
/// snapshot, not a history — retention is #37's concern once it has a real
/// UI; this is a safety net, not a backup strategy. Distinct from
/// `open_with_backup.dart`'s migration-scoped net (ADR-0010, unchanged by
/// this) and from #37's format (ADR-0011) only in trigger and retention —
/// both use the same `VACUUM INTO` mechanism via [exportDatabaseBackup].
const _snapshotFileName = 'crash_recovery_backup.sqlite';

File crashRecoverySnapshotFile(Directory appSupportDirectory) =>
    File('${appSupportDirectory.path}/$_snapshotFileName');

/// Overwrites the rotating snapshot with [db]'s current state. Called once
/// per clean startup, after [db] has opened and passed its integrity check
/// — never on a database already known to be corrupt, which would just
/// enshrine the corruption as "known good."
///
/// Never throws: a failed snapshot is a missed safety net, not a reason to
/// block the pilot from using the app. Logged via [debugPrint] since this
/// codebase has no dedicated logging facility yet.
Future<void> takeCrashRecoverySnapshot(
  AppDatabase db,
  Directory appSupportDirectory,
) async {
  try {
    await exportDatabaseBackup(
      db,
      crashRecoverySnapshotFile(appSupportDirectory),
    );
  } catch (error) {
    debugPrint('takeCrashRecoverySnapshot failed (non-fatal): $error');
  }
}
