import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/repositories/aircraft_repository.dart';
import '../providers/aircraft_providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import 'aircraft_edit_screen.dart';

/// #61: add, edit and archive the aircraft the pilot flies. Reached from
/// Settings — the entry form's own aircraft picker is still the sample
/// fleet stand-in (#58's own dartdoc), a separate piece of work from
/// managing the underlying records this screen writes.
class AircraftListScreen extends ConsumerWidget {
  const AircraftListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final recordsAsync = ref.watch(aircraftRecordsProvider);

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
                    child: Text('Aircraft', style: theme.textTheme.titleMedium),
                  ),
                  IconButton(
                    icon: const Icon(Icons.add),
                    tooltip: 'Add aircraft',
                    onPressed: () => Navigator.of(context).push<void>(
                      MaterialPageRoute(
                        builder: (_) => const AircraftEditScreen(),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: recordsAsync.when(
                loading: () =>
                    const Center(child: CircularProgressIndicator()),
                error: (error, stackTrace) => const Padding(
                  padding: EdgeInsets.all(20),
                  child: Text('Aircraft could not be loaded.'),
                ),
                data: (records) {
                  final active = [
                    for (final r in records)
                      if (!r.aircraft.archived) r,
                  ]..sort(
                    (a, b) => a.aircraft.registration.compareTo(
                      b.aircraft.registration,
                    ),
                  );
                  final archived = [
                    for (final r in records)
                      if (r.aircraft.archived) r,
                  ]..sort(
                    (a, b) => a.aircraft.registration.compareTo(
                      b.aircraft.registration,
                    ),
                  );

                  if (active.isEmpty && archived.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(20),
                      child: Text(
                        'No aircraft yet. Tap + to add one.',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: context.inkTiers.muted,
                        ),
                      ),
                    );
                  }

                  return ListView(
                    padding: const EdgeInsets.only(bottom: 32),
                    children: [
                      for (final record in active)
                        _AircraftRow(record: record),
                      if (archived.isNotEmpty) ...[
                        const _SectionHeader('ARCHIVED'),
                        for (final record in archived)
                          _AircraftRow(record: record),
                      ],
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

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final ink = context.inkTiers;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: Text(
        label,
        style: AppMonoText.tag(ink.muted).copyWith(letterSpacing: 1.1),
      ),
    );
  }
}

class _AircraftRow extends StatelessWidget {
  const _AircraftRow({required this.record});

  final AircraftRecord record;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;
    final aircraft = record.aircraft;
    final qualificationCount = [
      for (final set in aircraft.requiredQualifications.values) ...set,
    ].length;

    return InkWell(
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => AircraftEditScreen(existing: record),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    aircraft.registration,
                    style: AppMonoText.value(
                      aircraft.archived
                          ? ink.faint
                          : theme.colorScheme.onSurface,
                      size: 15,
                      weight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${aircraft.manufacturer} ${aircraft.model}'.trim(),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: aircraft.archived ? ink.faint : ink.muted,
                    ),
                  ),
                ],
              ),
            ),
            if (qualificationCount > 0)
              Text(
                '$qualificationCount qual${qualificationCount == 1 ? '' : 's'}',
                style: theme.textTheme.labelSmall?.copyWith(color: ink.faint),
              ),
          ],
        ),
      ),
    );
  }
}
