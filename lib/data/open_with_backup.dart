import 'dart:io';

/// Copies [dbFile] to a sibling `.backup` file before calling [open]. On
/// success, deletes the backup. On failure, restores [dbFile] from the
/// backup and rethrows — [dbFile] is never left in a partially-written
/// state, whatever [open] does to it.
///
/// [open] is fully caller-controlled: it decides what "opening" means
/// (construct a database, run a query to force migrations, whatever) and
/// returns whatever it wants. This keeps the wrapper generic without
/// needing to model a specific database type.
Future<T> openWithBackup<T>(File dbFile, Future<T> Function() open) async {
  final backupFile = File('${dbFile.path}.backup');

  if (await dbFile.exists()) {
    await dbFile.copy(backupFile.path);
  }

  try {
    final result = await open();
    if (await backupFile.exists()) {
      await backupFile.delete();
    }
    return result;
  } catch (_) {
    if (await backupFile.exists()) {
      if (await dbFile.exists()) {
        await dbFile.delete();
      }
      await backupFile.rename(dbFile.path);
    }
    rethrow;
  }
}
