import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'database.dart';

/// The real on-device database file's name. Lives alongside the platform's
/// own app-support directory (`getApplicationSupportDirectory` — not the
/// documents directory, since this file is app-internal state the pilot
/// never browses directly, backups go through #37's explicit export
/// instead).
const _dbFileName = 'easa_digital_log.sqlite';

/// Resolves the on-device database's path and opens it via
/// [openAppDatabase] (itself guarded by `openWithBackup`). Called once from
/// `main()` before `runApp` — see `lib/ui/providers/database_provider.dart`
/// for why the resulting [AppDatabase] is threaded in as a provider
/// override rather than resolved lazily inside a provider body.
Future<AppDatabase> openRealAppDatabase() async {
  final directory = await getApplicationSupportDirectory();
  final dbFile = File('${directory.path}/$_dbFileName');
  return openAppDatabase(dbFile);
}
