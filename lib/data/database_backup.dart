import 'dart:io';

import 'database.dart';

/// #37: user-facing backup/restore of the whole logbook. Distinct from
/// `open_with_backup.dart`, which is an internal, migration-scoped safety
/// net with no restore UI and no retention story (see ADR-0010) — that one
/// protects a single `openAppDatabase` call; this one is what a pilot
/// invokes deliberately, from the UI M4 eventually builds.
///
/// **Format decision (see `docs/adr/0011-backup-format.md`): the backup
/// *is* an ordinary SQLite file, produced by `VACUUM INTO`.** The live
/// database already is the complete legal record — every flight, every
/// `flight_revisions` row, every draft/committed/tombstoned state, all
/// reference data — so no separate export format is needed to satisfy "full
/// export including revision history and entry states." Versioning is free
/// too: SQLite's own `user_version` pragma is drift's `schemaVersion`, so an
/// old backup restored years from now runs through the exact migration
/// framework (#36) that already exists to open an old on-device database.

/// Writes a complete, consistent snapshot of [db] to [destination] using
/// SQLite's `VACUUM INTO`. Safe to call while [db] is open and in normal
/// use — `VACUUM INTO` reads a transactionally consistent view without
/// requiring exclusive access or a prior checkpoint, unlike a raw file copy
/// while a connection is live.
///
/// Overwrites [destination] if it already exists.
Future<void> exportDatabaseBackup(AppDatabase db, File destination) async {
  if (await destination.exists()) {
    await destination.delete();
  }
  await destination.parent.create(recursive: true);
  await db.customStatement('VACUUM INTO ?', [destination.path]);
}

/// Replaces [liveDbFile] with [backupFile]'s content.
///
/// The caller must have closed any open connection to [liveDbFile] first —
/// this operates purely on files, matching `openWithBackup`'s contract —
/// and must have already warned the user that this discards whatever is
/// currently there; this function does not ask. Reopen [liveDbFile]
/// afterwards via `openAppDatabase`, which migrates it forward if
/// [backupFile] predates the app's current schema version.
///
/// Throws [ArgumentError] if [backupFile] does not exist.
Future<void> restoreDatabaseBackup(File backupFile, File liveDbFile) async {
  if (!await backupFile.exists()) {
    throw ArgumentError.value(backupFile.path, 'backupFile', 'does not exist');
  }

  if (await liveDbFile.exists()) {
    await liveDbFile.delete();
  }
  // A rollback-journal sidecar can survive an app crash mid-write. VACUUM
  // INTO's output never has one, but leaving a stale one next to the file
  // it replaces would make SQLite think a crashed transaction needs
  // recovering against data that was never actually mid-write.
  final journal = File('${liveDbFile.path}-journal');
  if (await journal.exists()) {
    await journal.delete();
  }

  await liveDbFile.parent.create(recursive: true);
  await backupFile.copy(liveDbFile.path);
}

/// Whether a backup reminder should be shown, given the last successful
/// backup time ([lastBackupAt], `null` if none has ever been taken) and the
/// current time.
///
/// Pure decision logic only. Where [lastBackupAt] is persisted and how the
/// reminder is actually surfaced (a banner, a notification) is M4's
/// concern, once there is a UI to put it in — kept separate here so the
/// decision itself is written and tested now rather than guessed at later.
bool isBackupOverdue(
  DateTime? lastBackupAt,
  DateTime now, {
  Duration interval = const Duration(days: 30),
}) {
  if (lastBackupAt == null) {
    return true;
  }
  return now.difference(lastBackupAt) >= interval;
}
