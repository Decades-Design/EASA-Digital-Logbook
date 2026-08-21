import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../sample_fleet_data.dart';
import 'entry_card.dart';
import 'entry_section_label.dart';

/// §1 of docs/entry-form.md: aircraft first, registration only — it
/// determines the shape of everything below. Entering a registration that
/// matches [sampleFleet] resolves type, chips and the pushback note; one
/// that doesn't match resolves nothing, rather than guessing (CLAUDE.md:
/// "never guess a missing discriminator"). Real resolution against
/// `AircraftRepository` lands with #56/#61 — [sampleFleet] is the same kind
/// of stand-in `lib/ui/logbook/sample_logbook_data.dart` already uses.
/// Fleet list rows shown before a search narrows them down, and the most a
/// search can ever bring back — a defensive cap for when a real fleet
/// (post-#56/#61) is far larger than this screen's five-entry sample data,
/// so the picker never tries to render an unbounded list.
const int _maxFleetResults = 20;

class AircraftSection extends StatelessWidget {
  const AircraftSection({
    super.key,
    required this.controller,
    required this.resolved,
    required this.fleetOpen,
    required this.onToggleFleet,
    required this.onFocusRegistration,
    required this.onPickAircraft,
    required this.searchController,
  });

  final TextEditingController controller;

  /// Null until the typed registration matches a fleet entry.
  final SampleFleetAircraft? resolved;

  final bool fleetOpen;
  final VoidCallback onToggleFleet;
  final VoidCallback onFocusRegistration;
  final ValueChanged<SampleFleetAircraft> onPickAircraft;

  /// Filters the fleet list by registration or type — docs/entry-form.md
  /// §10: recent/matching aircraft should be quick to find, not a long
  /// scroll. Owned by the parent screen like every other text field here,
  /// so its listener-driven rebuild (see `NewFlightScreen.initState`)
  /// re-filters as the pilot types.
  final TextEditingController searchController;

  List<SampleFleetAircraft> get _fleetMatches {
    final query = searchController.text.trim().toLowerCase();
    final matches = query.isEmpty
        ? sampleFleet
        : sampleFleet.where(
            (entry) =>
                entry.registration.toLowerCase().contains(query) ||
                entry.typeLabel.toLowerCase().contains(query),
          );
    return matches.take(_maxFleetResults).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;

    return EntrySection(
      label: 'Aircraft',
      child: EntryCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: controller,
                    textCapitalization: TextCapitalization.characters,
                    onTap: onFocusRegistration,
                    style: const TextStyle(
                      fontFamily: 'IBM Plex Mono',
                      fontWeight: FontWeight.w600,
                      fontSize: 19,
                    ),
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 4),
                      hintText: 'Registration, e.g. G-EZTK',
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onToggleFleet,
                  child: Text(fleetOpen ? 'Close' : 'Change aircraft'),
                ),
              ],
            ),
            if (resolved != null) ...[
              const SizedBox(height: 4),
              Text(
                '${resolved!.typeLabel} · '
                '${resolved!.aircraft.category.name == 'helicopter' ? 'helicopter' : 'aeroplane'}',
                style: theme.textTheme.bodyMedium?.copyWith(color: ink.muted),
              ),
              const SizedBox(height: 9),
              Wrap(
                spacing: 5,
                runSpacing: 5,
                children: [
                  for (final chip in resolved!.displayChips) _Chip(label: chip),
                ],
              ),
            ],
            if (fleetOpen) ...[
              const SizedBox(height: 11),
              TextField(
                controller: searchController,
                textCapitalization: TextCapitalization.characters,
                style: const TextStyle(fontSize: 13.5),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  hintText: 'Search registration or type',
                  contentPadding: const EdgeInsets.symmetric(vertical: 10),
                ),
              ),
              const SizedBox(height: 9),
              if (_fleetMatches.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  child: Text(
                    'No aircraft match "${searchController.text.trim()}"',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: ink.muted,
                    ),
                  ),
                )
              else
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: theme.colorScheme.outlineVariant),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final entry in _fleetMatches)
                          _FleetRow(
                            entry: entry,
                            selected:
                                entry.registration.toUpperCase() ==
                                controller.text.trim().toUpperCase(),
                            onTap: () => onPickAircraft(entry),
                          ),
                      ],
                    ),
                  ),
                ),
            ],
            if (resolved != null && resolved!.pushbackOperations) ...[
              const SizedBox(height: 11),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 11,
                  vertical: 9,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLow,
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Text(
                  'Pushback operations: EASA counts from first movement, '
                  'the FAA from movement under own power. Block start is '
                  'recorded per profile.',
                  style: theme.textTheme.bodySmall?.copyWith(color: ink.muted),
                ),
              ),
            ],
            const SizedBox(height: 2),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ink = context.inkTiers;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        border: Border.all(color: scheme.outlineVariant),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'IBM Plex Mono',
          fontWeight: FontWeight.w500,
          fontSize: 10.5,
          color: ink.medium,
        ),
      ),
    );
  }
}

class _FleetRow extends StatelessWidget {
  const _FleetRow({
    required this.entry,
    required this.selected,
    required this.onTap,
  });

  final SampleFleetAircraft entry;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;
    return InkWell(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
          color: selected
              ? theme.colorScheme.primary.withValues(alpha: 0.08)
              : theme.colorScheme.surface,
          border: Border(
            bottom: BorderSide(color: theme.colorScheme.outlineVariant),
          ),
        ),
        child: Row(
          children: [
            Text(
              entry.registration,
              style: const TextStyle(
                fontFamily: 'IBM Plex Mono',
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                entry.typeLabel,
                textAlign: TextAlign.right,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(color: ink.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
