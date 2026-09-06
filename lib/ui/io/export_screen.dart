import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/model/calendar_date.dart';
import '../../domain/repository/export_record_repository.dart';
import '../../domain/repository/flight_read_repository.dart';
import '../../io/export_formats.dart';
import '../providers/foreflight_export_providers.dart';
import '../providers/repository_providers.dart';
import '../theme/app_colors.dart';

/// #70's export screen: a mandatory date range (never inferred — CLAUDE.md's
/// "Export asks which jurisdiction explicitly" spirit applied to a range
/// too), a non-blocking warning when that range overlaps a previously
/// recorded export, then a save-file dialog for the resulting CSV.
///
/// Only committed, active flights are exported — a draft is still "freely
/// mutable... not yet asserted" (rule 4); sending an unfinished entry to
/// another app is premature regardless of how export there differs from
/// the official PDF logbook's own commit-on-export rule.
class ExportScreen extends ConsumerStatefulWidget {
  const ExportScreen({super.key});

  @override
  ConsumerState<ExportScreen> createState() => _ExportScreenState();
}

class _ExportScreenState extends ConsumerState<ExportScreen> {
  CalendarDate? _from;
  CalendarDate? _to;
  Future<List<ExportRecord>>? _overlapCheck;
  bool _exporting = false;

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = (isFrom ? _from : _to) ?? _todayAsCalendarDate();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      final date = CalendarDate(picked.year, picked.month, picked.day);
      if (isFrom) {
        _from = date;
      } else {
        _to = date;
      }
      _overlapCheck = null;
      final from = _from;
      final to = _to;
      if (from != null && to != null && from <= to) {
        _overlapCheck = ref
            .read(exportRecordRepositoryProvider)
            .findOverlapping(
              format: faaCsvExportFormatLabel,
              from: from,
              to: to,
            );
      }
    });
  }

  CalendarDate _todayAsCalendarDate() {
    final now = DateTime.now();
    return CalendarDate(now.year, now.month, now.day);
  }

  Future<void> _export() async {
    final from = _from;
    final to = _to;
    if (from == null || to == null) return;

    setState(() => _exporting = true);
    try {
      final faaProjection = await ref.read(faaProjectionProvider.future);
      final projected = await ref
          .read(flightReadRepositoryProvider)
          .watchFlights(
            projection: faaProjection,
            query: FlightQuery(from: from, to: to),
          )
          .first;
      final flights = [for (final p in projected) p.record];

      if (flights.isEmpty) {
        _showMessage('No committed flights between $from and $to.');
        return;
      }

      final csv = buildFaaCsvExport(
        flights: flights,
        faaProjection: faaProjection,
      );
      final fileName = faaCsvExportFilename(from: from, to: to);

      final savedUri = await FilePicker.saveFile(
        fileName: fileName,
        bytes: Uint8List.fromList(utf8.encode(csv)),
        mimeType: 'text/csv',
        dialogTitle: 'Save $faaCsvExportFormatLabel export',
        type: FileType.custom,
        allowedExtensions: ['csv'],
      );
      if (savedUri == null) return; // pilot cancelled the save dialog.

      await ref
          .read(exportRecordRepositoryProvider)
          .recordExport(format: faaCsvExportFormatLabel, from: from, to: to);

      _showMessage('${flights.length} flight(s) exported to $fileName.');
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;
    final semantic = context.semanticColors;
    final from = _from;
    final to = _to;
    final rangeValid = from != null && to != null && from <= to;

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
                    child: Text(
                      'Export to $faaCsvExportFormatLabel',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
                children: [
                  Text(
                    'Choose a date range to export. Only committed flights '
                    'are included.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: ink.muted,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('From'),
                    subtitle: Text(from?.toString() ?? 'Not set'),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () => _pickDate(isFrom: true),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('To'),
                    subtitle: Text(to?.toString() ?? 'Not set'),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () => _pickDate(isFrom: false),
                  ),
                  if (from != null && to != null && from > to)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'The "From" date must be on or before "To".',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  if (_overlapCheck != null)
                    FutureBuilder<List<ExportRecord>>(
                      future: _overlapCheck,
                      builder: (context, snapshot) {
                        final overlapping = snapshot.data ?? const [];
                        if (overlapping.isEmpty) return const SizedBox.shrink();
                        return Container(
                          margin: const EdgeInsets.only(top: 16),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: semantic.currencyWarningSurface,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'This range overlaps ${overlapping.length} '
                            'previous export(s) — re-importing this file '
                            'into $faaCsvExportFormatLabel may create '
                            'duplicates there.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: semantic.currencyWarning,
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: (rangeValid && !_exporting) ? _export : null,
              child: _exporting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Export'),
            ),
          ),
        ),
      ),
    );
  }
}
