import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/model/utc_instant.dart';
import '../../domain/repository/flight_read_repository.dart';
import '../../io/duplicate_matcher.dart';
import '../../io/import_adapter.dart';
import '../../io/import_pipeline.dart';
import '../providers/flight_records_providers.dart';
import '../providers/repository_providers.dart';
import '../theme/app_colors.dart';

String _formatUtcDate(UtcInstant instant) {
  final d = instant.asUtcDateTime;
  return '${d.year.toString().padLeft(4, '0')}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';
}

String _formatUtcTime(UtcInstant instant) {
  final d = instant.asUtcDateTime;
  return '${d.hour.toString().padLeft(2, '0')}:'
      '${d.minute.toString().padLeft(2, '0')}Z';
}

/// #73's preview step and #75's duplicate surfacing, in one screen: every
/// mappable row from [parseResult] with a per-row skip/import checkbox
/// (defaulting a flagged duplicate to skipped, everything else to
/// imported), every unmappable row shown read-only with its error, and a
/// bulk "skip all duplicates"/"select all" pair for the common case of a
/// wholly overlapping re-import. Nothing is written until "Import" is
/// pressed.
class ImportPreviewScreen extends ConsumerStatefulWidget {
  const ImportPreviewScreen({
    super.key,
    required this.parseResult,
    required this.sourceLabel,
  });

  final ImportParseResult parseResult;
  final String sourceLabel;

  @override
  ConsumerState<ImportPreviewScreen> createState() =>
      _ImportPreviewScreenState();
}

class _ImportPreviewScreenState extends ConsumerState<ImportPreviewScreen> {
  ImportPreview? _preview;
  Set<int> _excludedRowNumbers = {};
  bool _importing = false;
  bool _unreadableRowsAcknowledged = false;

  ImportPreview _buildPreview(List<FlightRecord> existingFlights) {
    final preview = buildImportPreview(
      parseResult: widget.parseResult,
      existingFlights: existingFlights,
    );
    // Default a flagged duplicate to skipped, everything else to imported
    // — computed once, the first time the existing-flights data resolves,
    // never recomputed just because the pilot toggled a checkbox.
    _excludedRowNumbers = {
      for (final row in preview.rows)
        if (row.duplicate != null) row.row.sourceRowNumber,
    };
    return preview;
  }

  Future<void> _import(ImportPreview preview) async {
    final selected = [
      for (final row in preview.rows)
        if (!_excludedRowNumbers.contains(row.row.sourceRowNumber)) row.row,
    ];
    if (selected.isEmpty) return;

    setState(() => _importing = true);
    try {
      final batchId = await applyImport(
        rows: selected,
        sourceLabel: widget.sourceLabel,
        aircraftRepository: ref.read(aircraftRepositoryProvider),
        flightRepository: ref.read(flightRepositoryProvider),
      );
      if (!mounted) return;
      // Captured before popping: ScaffoldMessenger.of resolves to the app's
      // single ancestor messenger (above the Navigator), which stays
      // mounted across this pop — the "Undo" SnackBar's own action, and its
      // own follow-up report, both need to post after this screen is gone.
      final messenger = ScaffoldMessenger.of(context);
      final flightRepository = ref.read(flightRepositoryProvider);
      Navigator.of(context).pop();
      messenger.showSnackBar(
        SnackBar(
          content: Text('${selected.length} flight(s) imported as drafts.'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () async {
              try {
                // #73: "reporting the split to the user" — a flight already
                // committed in the meantime is tombstoned, not deleted, so
                // the pilot needs to know both counts, not just "undone".
                final result = await flightRepository.undoImportBatch(batchId);
                // Replace the "imported" SnackBar immediately rather than
                // queuing behind its own display duration — the pilot just
                // asked for this outcome, they shouldn't wait ~4s to see it
                // confirmed.
                messenger.hideCurrentSnackBar();
                messenger.showSnackBar(
                  SnackBar(
                    content: Text(
                      result.tombstonedCommittedCount == 0
                          ? '${result.deletedDraftCount} flight(s) removed.'
                          : '${result.deletedDraftCount} flight(s) removed, '
                                '${result.tombstonedCommittedCount} already '
                                'committed flight(s) tombstoned.',
                    ),
                  ),
                );
              } on StateError {
                // Already undone (e.g. double-tapped) — nothing more to do.
              }
            },
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _importing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final existingAsync = ref.watch(allFlightRecordsProvider);

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
                      'Preview import',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: existingAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stackTrace) => Padding(
                  padding: const EdgeInsets.all(20),
                  child: Text(
                    'Could not check for duplicates: $error',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                data: (existingFlights) {
                  final preview = _preview ??= _buildPreview(existingFlights);
                  return _PreviewBody(
                    preview: preview,
                    excludedRowNumbers: _excludedRowNumbers,
                    importing: _importing,
                    unreadableRowsAcknowledged: _unreadableRowsAcknowledged,
                    onExcludedChanged: (updated) =>
                        setState(() => _excludedRowNumbers = updated),
                    onUnreadableRowsAcknowledgedChanged: (value) =>
                        setState(() => _unreadableRowsAcknowledged = value),
                    onImport: () => _import(preview),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewBody extends StatelessWidget {
  const _PreviewBody({
    required this.preview,
    required this.excludedRowNumbers,
    required this.importing,
    required this.unreadableRowsAcknowledged,
    required this.onExcludedChanged,
    required this.onUnreadableRowsAcknowledgedChanged,
    required this.onImport,
  });

  final ImportPreview preview;
  final Set<int> excludedRowNumbers;
  final bool importing;
  final bool unreadableRowsAcknowledged;
  final ValueChanged<Set<int>> onExcludedChanged;
  final ValueChanged<bool> onUnreadableRowsAcknowledgedChanged;
  final VoidCallback onImport;

  int get _selectedCount => preview.rows
      .where((r) => !excludedRowNumbers.contains(r.row.sourceRowNumber))
      .length;

  int get _duplicateCount =>
      preview.rows.where((r) => r.duplicate != null).length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(
            '${preview.rows.length} flight(s) found'
            '${_duplicateCount > 0 ? ' · $_duplicateCount possible duplicate(s)' : ''}'
            '${preview.errors.isNotEmpty ? ' · ${preview.errors.length} row(s) could not be read' : ''}.',
            style: theme.textTheme.bodySmall?.copyWith(color: ink.muted),
          ),
        ),
        if (_duplicateCount > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Wrap(
              spacing: 8,
              children: [
                TextButton(
                  onPressed: () => onExcludedChanged({
                    for (final row in preview.rows)
                      if (row.duplicate != null) row.row.sourceRowNumber,
                  }),
                  child: const Text('Skip all duplicates'),
                ),
                TextButton(
                  onPressed: () => onExcludedChanged({}),
                  child: const Text('Select all'),
                ),
              ],
            ),
          ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 96),
            children: [
              for (final row in preview.rows)
                _PreviewRowTile(
                  row: row,
                  selected: !excludedRowNumbers.contains(
                    row.row.sourceRowNumber,
                  ),
                  onChanged: (selected) {
                    final updated = Set<int>.of(excludedRowNumbers);
                    if (selected) {
                      updated.remove(row.row.sourceRowNumber);
                    } else {
                      updated.add(row.row.sourceRowNumber);
                    }
                    onExcludedChanged(updated);
                  },
                ),
              if (preview.errors.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                  child: Text(
                    'ROWS THAT COULD NOT BE READ',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: ink.muted,
                    ),
                  ),
                ),
                for (final error in preview.errors) _ErrorRowTile(error: error),
                CheckboxListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20),
                  value: unreadableRowsAcknowledged,
                  onChanged: (value) =>
                      onUnreadableRowsAcknowledgedChanged(value ?? false),
                  title: Text(
                    "I've reviewed the ${preview.errors.length} row(s) "
                    "above that won't be imported",
                    style: theme.textTheme.bodySmall,
                  ),
                ),
              ],
            ],
          ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed:
                    (_selectedCount == 0 ||
                        importing ||
                        (preview.errors.isNotEmpty &&
                            !unreadableRowsAcknowledged))
                    ? null
                    : onImport,
                child: importing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text('Import $_selectedCount flight(s)'),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PreviewRowTile extends StatelessWidget {
  const _PreviewRowTile({
    required this.row,
    required this.selected,
    required this.onChanged,
  });

  final ImportPreviewRow row;
  final bool selected;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;
    final semantic = context.semanticColors;
    final flight = row.row.flight;
    final duplicate = row.duplicate;

    return InkWell(
      onTap: () => onChanged(!selected),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Checkbox(value: selected, onChanged: (v) => onChanged(v ?? false)),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${_formatUtcDate(flight.offBlocks)} · '
                    '${row.row.aircraft.registration} · '
                    '${flight.route.join(" → ")}',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_formatUtcTime(flight.offBlocks)}–'
                    '${_formatUtcTime(flight.onBlocks)}'
                    '${row.row.reviewNotes.isNotEmpty ? ' · ${row.row.reviewNotes.length} note(s) to verify' : ''}',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ink.muted,
                    ),
                  ),
                  if (duplicate != null) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: semantic.currencyWarningSurface,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        duplicate.confidence == DuplicateConfidence.exact
                            ? 'Exact duplicate — ${duplicate.reason}'
                            : 'Possible duplicate — ${duplicate.reason}',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: semantic.currencyWarning,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorRowTile extends StatelessWidget {
  const _ErrorRowTile({required this.error});

  final ImportRowError error;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: colorScheme.error),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Row ${error.rowNumber}: ${error.message}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
