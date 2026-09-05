import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/model/utc_instant.dart';
import '../../domain/repository/flight_read_repository.dart';
import '../entry/flight_diff.dart';
import '../providers/flight_records_providers.dart';
import '../providers/repository_providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

/// #60: the full revision chain for a committed flight — CLAUDE.md rule 4
/// exists so a pilot can show this to an inspector, not just so the data is
/// technically retained, so every entry is rendered readable rather than
/// raw: a timestamp, what changed (reused from #59's own diff renderer, so
/// the two features describe the same edit the same way), and the reason
/// where one was given. [FlightDetailScreen] only opens this for a
/// committed flight — a draft has never been asserted to an authority, so
/// there is nothing here to show.
class RevisionHistoryScreen extends ConsumerWidget {
  const RevisionHistoryScreen({super.key, required this.flightId});

  final String flightId;

  Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore this flight?'),
        content: const Text(
          'It reappears in the logbook and in every total it used to count '
          'toward.',
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
    if (confirmed != true) return;

    await ref.read(flightRepositoryProvider).restore(flightId);
    ref.invalidate(flightHistoryProvider(flightId));
    if (context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final historyAsync = ref.watch(flightHistoryProvider(flightId));

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
                      'Revision history',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: historyAsync.when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (error, stackTrace) => const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('History could not be loaded.'),
                ),
                data: (history) {
                  if (history == null) {
                    return const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('This flight has no history to show.'),
                    );
                  }
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                    children: [
                      if (history.isTombstoned) ...[
                        _TombstonedBanner(
                          onRestore: () => _restore(context, ref),
                        ),
                        const SizedBox(height: 16),
                      ],
                      for (final entry in history.entries)
                        _RevisionCard(entry: entry),
                    ],
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

class _TombstonedBanner extends StatelessWidget {
  const _TombstonedBanner({required this.onRestore});

  final VoidCallback onRestore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semanticColors;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: semantic.currencyWarningSurface,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'This flight has been deleted. It no longer counts toward '
              'any total until restored.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: semantic.currencyWarning,
              ),
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(onPressed: onRestore, child: const Text('Restore')),
        ],
      ),
    );
  }
}

class _RevisionCard extends StatelessWidget {
  const _RevisionCard({required this.entry});

  final FlightRevisionEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;
    final changes = entry.before == null
        ? const <FlightFieldChange>[]
        : diffFlightsForDisplay(entry.before!, entry.after);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(_kindLabel(entry.kind), style: theme.textTheme.titleSmall),
              const Spacer(),
              Text(
                _formatUtcDateTime(entry.recordedAt),
                style: AppMonoText.value(ink.faint, size: 11.5),
              ),
            ],
          ),
          if (entry.reason != null && entry.reason!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              entry.reason!,
              style: theme.textTheme.bodySmall?.copyWith(color: ink.muted),
            ),
          ],
          const SizedBox(height: 10),
          switch (entry.kind) {
            FlightRevisionKind.commit => Text(
              'Raw facts recorded at commit — the record\'s starting point.',
              style: theme.textTheme.bodySmall?.copyWith(color: ink.faint),
            ),
            FlightRevisionKind.tombstone => Text(
              'Removed from the logbook and every total.',
              style: theme.textTheme.bodySmall?.copyWith(color: ink.faint),
            ),
            FlightRevisionKind.restore => Text(
              'Reinstated — counts toward totals again.',
              style: theme.textTheme.bodySmall?.copyWith(color: ink.faint),
            ),
            FlightRevisionKind.edit when changes.isEmpty => Text(
              'No raw-fact fields changed.',
              style: theme.textTheme.bodySmall?.copyWith(color: ink.faint),
            ),
            FlightRevisionKind.edit => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final change in changes) _ChangeRow(change: change),
              ],
            ),
          },
        ],
      ),
    );
  }
}

class _ChangeRow extends StatelessWidget {
  const _ChangeRow({required this.change});

  final FlightFieldChange change;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(change.label, style: theme.textTheme.labelMedium),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: change.before,
                  style: AppMonoText.value(
                    ink.faint,
                    size: 12,
                  ).copyWith(decoration: TextDecoration.lineThrough),
                ),
                TextSpan(
                  text: '  →  ',
                  style: AppMonoText.value(ink.faint, size: 12),
                ),
                TextSpan(
                  text: change.after,
                  style: AppMonoText.value(
                    theme.colorScheme.onSurface,
                    size: 12,
                    weight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _kindLabel(FlightRevisionKind kind) => switch (kind) {
  FlightRevisionKind.commit => 'Committed',
  FlightRevisionKind.edit => 'Edited',
  FlightRevisionKind.tombstone => 'Deleted',
  FlightRevisionKind.restore => 'Restored',
};

String _formatUtcDateTime(UtcInstant instant) {
  final d = instant.asUtcDateTime;
  final months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  return '${d.day} ${months[d.month - 1]} ${d.year}, $hh:${mm}Z';
}
