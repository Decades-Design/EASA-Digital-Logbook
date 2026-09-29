import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../data/crash_recovery_snapshot.dart';
import '../../data/database_backup.dart';

/// #90 AC5: shown instead of the normal app when startup finds the database
/// corrupt (`RootApp` in `lib/main.dart`). Offers the automatic local
/// safety snapshot (`crash_recovery_snapshot.dart`) when one exists, and a
/// manual file picker for a backup the pilot exported themselves (#37).
/// [onRestored] re-runs the app's bootstrap; a restore that produces
/// another unhealthy database keeps the pilot here with the new error
/// rather than silently looping.
class DatabaseRecoveryScreen extends StatefulWidget {
  const DatabaseRecoveryScreen({
    super.key,
    required this.dbFile,
    required this.appSupportDirectory,
    required this.onRestored,
    this.detail,
  });

  final File dbFile;
  final Directory appSupportDirectory;
  final Future<void> Function() onRestored;

  /// The exception or `quick_check` result that triggered recovery mode,
  /// shown so a pilot who contacts support has something concrete to quote.
  final String? detail;

  @override
  State<DatabaseRecoveryScreen> createState() => _DatabaseRecoveryScreenState();
}

class _DatabaseRecoveryScreenState extends State<DatabaseRecoveryScreen> {
  bool _busy = false;
  String? _error;

  File get _snapshotFile =>
      crashRecoverySnapshotFile(widget.appSupportDirectory);

  Future<bool> _confirm(String backupDescription) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore this backup?'),
        content: Text(
          'This replaces the current, unreadable database with '
          '$backupDescription. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    return confirmed ?? false;
  }

  Future<void> _restoreFrom(File backupFile, String description) async {
    if (!await _confirm(description)) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await restoreDatabaseBackup(backupFile, widget.dbFile);
      await widget.onRestored();
      // A successful restore leading to a healthy reopen navigates away
      // from this screen entirely (RootApp swaps it for the real app) --
      // if we're still here and still mounted, the reopen found the
      // restored file unhealthy too.
      if (mounted) {
        setState(() {
          _busy = false;
          _error =
              'The restored file did not open cleanly either. Try a '
              'different backup.';
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Restore failed: $error';
        });
      }
    }
  }

  Future<void> _pickAndRestore() async {
    final picked = await FilePicker.pickFile(
      dialogTitle: 'Choose a logbook backup file',
      type: FileType.custom,
      allowedExtensions: ['sqlite'],
    );
    final path = picked?.path;
    if (path == null) return; // pilot cancelled the picker.
    await _restoreFrom(File(path), 'the backup file you chose');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasSnapshot = _snapshotFile.existsSync();

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.warning_amber_rounded,
                    size: 48,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Your logbook could not be opened',
                    style: theme.textTheme.headlineSmall,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'The database file on this device appears to be '
                    'damaged. Nothing has been deleted — it is still on '
                    'disk — but the app cannot safely read it. Restore '
                    'from a backup below to continue.',
                    textAlign: TextAlign.center,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  const SizedBox(height: 24),
                  if (hasSnapshot)
                    FilledButton(
                      onPressed: _busy
                          ? null
                          : () => _restoreFrom(
                              _snapshotFile,
                              'the automatic backup from '
                              '${_snapshotFile.lastModifiedSync().toLocal()}',
                            ),
                      child: const Text('Restore last known-good state'),
                    ),
                  if (hasSnapshot) const SizedBox(height: 12),
                  OutlinedButton(
                    onPressed: _busy ? null : _pickAndRestore,
                    child: const Text('Choose a backup file…'),
                  ),
                  if (widget.detail != null) ...[
                    const SizedBox(height: 24),
                    Text(
                      widget.detail!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                  if (_busy) ...[
                    const SizedBox(height: 24),
                    const Center(child: CircularProgressIndicator()),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
