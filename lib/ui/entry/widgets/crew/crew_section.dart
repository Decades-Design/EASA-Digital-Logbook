import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../entry_card.dart';
import '../entry_section_label.dart';
import 'crew_form_data.dart';
import 'crew_just_me.dart';
import 'crew_selection.dart';
import 'crew_with_instructor.dart';
import 'crew_with_other_pilot.dart';
import 'crew_with_passengers.dart';

/// §4: one question — "who else was on board?" — with the answer expanding
/// inline into one of four field sets. Fully controlled from
/// `NewFlightScreen` via [data], so the derivation strip and the remarks
/// section's countersignature block can read what the pilot has entered
/// here.
class CrewSection extends StatelessWidget {
  const CrewSection({super.key, required this.data});

  final CrewFormData data;

  static const _options = [
    (CrewSelection.justMe, 'Just me'),
    (CrewSelection.withInstructor, 'With an instructor'),
    (CrewSelection.withOtherPilot, 'With another pilot'),
    (CrewSelection.withPassengers, 'With passengers'),
  ];

  @override
  Widget build(BuildContext context) {
    return EntrySection(
      label: 'Who else was on board?',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _OptionCard(option: _options[0], data: data),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _OptionCard(option: _options[1], data: data),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _OptionCard(option: _options[2], data: data),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _OptionCard(option: _options[3], data: data),
              ),
            ],
          ),
          if (data.crew != null) ...[
            const SizedBox(height: 12),
            EntryCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: switch (data.crew!) {
                CrewSelection.justMe => CrewJustMe(data: data),
                CrewSelection.withInstructor => CrewWithInstructor(data: data),
                CrewSelection.withOtherPilot => CrewWithOtherPilot(data: data),
                CrewSelection.withPassengers => const CrewWithPassengers(),
              },
            ),
          ],
        ],
      ),
    );
  }
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({required this.option, required this.data});

  final (CrewSelection, String) option;
  final CrewFormData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ink = context.inkTiers;
    final selected = option.$1 == data.crew;

    return InkWell(
      onTap: () => data.onSelectCrew(option.$1),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        decoration: BoxDecoration(
          color: selected ? scheme.onSurface : scheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? scheme.onSurface : scheme.outlineVariant,
          ),
        ),
        alignment: Alignment.centerLeft,
        child: Text(
          option.$2,
          style: theme.textTheme.titleMedium?.copyWith(
            color: selected ? scheme.surface : ink.medium,
          ),
        ),
      ),
    );
  }
}
