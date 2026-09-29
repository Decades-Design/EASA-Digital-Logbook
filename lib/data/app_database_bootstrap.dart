import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'database.dart';

/// The real on-device database file's name. Lives alongside the platform's
/// own app-support directory (`getApplicationSupportDirectory` — not the
/// documents directory, since this file is app-internal state the pilot
/// never browses directly, backups go through #37's explicit export
/// instead).
const _dbFileName = 'easa_digital_log.sqlite';

/// What [bootstrapRealAppDatabase] found — #90 AC5's detection step. A
/// sealed result rather than a thrown exception, since "the database is
/// corrupt" is an expected, recoverable startup outcome here (`main()`
/// routes to `DatabaseRecoveryScreen`), not a bug to crash on.
sealed class DatabaseBootstrapResult {
  const DatabaseBootstrapResult({
    required this.dbFile,
    required this.appSupportDirectory,
  });

  final File dbFile;
  final Directory appSupportDirectory;
}

class DatabaseBootstrapReady extends DatabaseBootstrapResult {
  const DatabaseBootstrapReady(
    this.db, {
    required super.dbFile,
    required super.appSupportDirectory,
  });

  final AppDatabase db;
}

class DatabaseBootstrapCorrupt extends DatabaseBootstrapResult {
  const DatabaseBootstrapCorrupt({
    required super.dbFile,
    required super.appSupportDirectory,
    this.detail,
  });

  /// The exception or `quick_check` result that triggered recovery mode —
  /// shown on `DatabaseRecoveryScreen` so a pilot who contacts support has
  /// something concrete to quote, not a debugging aid this code relies on.
  final String? detail;
}

/// Resolves the on-device database's path, opens it via [openAppDatabase]
/// (itself guarded by `openWithBackup`'s migration-only safety net,
/// ADR-0010), and checks it's healthy (#90 AC5, `isDatabaseHealthy`).
/// Called once from `main()` before `runApp` — see
/// `lib/ui/providers/database_provider.dart` for why a ready result's
/// [AppDatabase] is threaded in as a provider override rather than resolved
/// lazily inside a provider body.
Future<DatabaseBootstrapResult> bootstrapRealAppDatabase() async {
  final directory = await getApplicationSupportDirectory();
  final dbFile = File('${directory.path}/$_dbFileName');

  final AppDatabase db;
  try {
    db = await openAppDatabase(dbFile);
  } catch (error) {
    return DatabaseBootstrapCorrupt(
      dbFile: dbFile,
      appSupportDirectory: directory,
      detail: error.toString(),
    );
  }

  if (await isDatabaseHealthy(db)) {
    return DatabaseBootstrapReady(
      db,
      dbFile: dbFile,
      appSupportDirectory: directory,
    );
  }

  // A corrupt database that still opened (SQLite's own quick_check caught
  // something the open/migration path didn't) must not be left holding a
  // live connection while recovery mode replaces the file underneath it.
  await db.close();
  return DatabaseBootstrapCorrupt(
    dbFile: dbFile,
    appSupportDirectory: directory,
    detail: 'PRAGMA quick_check reported a problem with the database file.',
  );
}
