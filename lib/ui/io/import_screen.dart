import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../io/foreflight/foreflight_adapter.dart';
import '../../io/garmin/garmin_adapter.dart';
import '../../io/import_adapter.dart';
import '../theme/app_colors.dart';
import 'generic_csv_mapping_screen.dart';
import 'import_preview_screen.dart';

/// Entry point for #73's transactional import flow, reached from Settings.
/// Picks a format, reads whichever file(s) that format's [ImportAdapter]
/// needs from disk, and hands the resulting [ImportParseResult] to
/// [ImportPreviewScreen] — nothing here writes to the database; parsing a
/// file is pure (`ImportAdapter.parse`'s own contract).
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  bool _busy = false;

  Future<String?> _pickCsv({required String dialogTitle}) async {
    final picked = await FilePicker.pickFile(
      dialogTitle: dialogTitle,
      type: FileType.custom,
      allowedExtensions: ['csv'],
    );
    final path = picked?.path;
    if (path == null) return null;
    return File(path).readAsString();
  }

  Future<void> _run(
    String sourceLabel,
    Future<ImportParseResult?> Function() build,
  ) async {
    setState(() => _busy = true);
    try {
      final result = await build();
      if (result == null) return; // pilot cancelled a file picker.
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => ImportPreviewScreen(
            parseResult: result,
            sourceLabel: sourceLabel,
          ),
        ),
      );
    } on FormatException catch (error) {
      _showError(error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _importForeFlight() => _run('ForeFlight', () async {
    final csv = await _pickCsv(dialogTitle: 'Select logbook_template.csv');
    if (csv == null) return null;
    return ForeFlightAdapter().parse({ForeFlightAdapter.logbookKey: csv});
  });

  Future<void> _importGarmin() => _run('Garmin Pilot', () async {
    final aircraftTypesCsv = await _pickCsv(
      dialogTitle: 'Select the aircraft-types export',
    );
    if (aircraftTypesCsv == null) return null;
    if (!mounted) return null;
    final logEntriesCsv = await _pickCsv(
      dialogTitle: 'Select the logbook export',
    );
    if (logEntriesCsv == null) return null;
    return GarminAdapter().parse({
      GarminAdapter.aircraftTypesKey: aircraftTypesCsv,
      GarminAdapter.logEntriesKey: logEntriesCsv,
    });
  });

  Future<void> _startGenericCsv() async {
    setState(() => _busy = true);
    try {
      final csv = await _pickCsv(dialogTitle: 'Select a CSV logbook export');
      if (csv == null) return;
      if (!mounted) return;
      await Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => GenericCsvMappingScreen(csv: csv)),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Text('Import', style: theme.textTheme.titleMedium),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
              child: Text(
                'Choose the format your logbook was exported in. You\'ll '
                'see every flight before anything is imported.',
                style: theme.textTheme.bodyMedium?.copyWith(color: ink.muted),
              ),
            ),
            if (_busy) const LinearProgressIndicator(),
            _FormatRow(
              title: 'ForeFlight',
              subtitle: 'logbook_template.csv',
              onTap: _busy ? null : _importForeFlight,
            ),
            const Divider(height: 1),
            _FormatRow(
              title: 'Garmin Pilot',
              subtitle: 'Aircraft types + logbook CSV (two files)',
              onTap: _busy ? null : _importGarmin,
            ),
            const Divider(height: 1),
            _FormatRow(
              title: 'Generic CSV',
              subtitle:
                  'LogTen, Skylog, MCC Pilot Log, or your own spreadsheet',
              onTap: _busy ? null : _startGenericCsv,
            ),
            const Divider(height: 1),
          ],
        ),
      ),
    );
  }
}

class _FormatRow extends StatelessWidget {
  const _FormatRow({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleSmall),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ink.muted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: ink.faint),
          ],
        ),
      ),
    );
  }
}
