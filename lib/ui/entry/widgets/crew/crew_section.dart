import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../entry_card.dart';
import '../entry_section_label.dart';
import 'crew_just_me.dart';
import 'crew_selection.dart';
import 'crew_with_instructor.dart';
import 'crew_with_other_pilot.dart';
import 'crew_with_passengers.dart';

/// §4: one question — "who else was on board?" — with the answer expanding
/// inline into one of four field sets. Each path keeps its own fields'
/// state internally; nothing downstream reads them yet, since there's no
/// real Flight submission to feed until #56 wires up the repository.
class CrewSection extends StatefulWidget {
  const CrewSection({super.key});

  @override
  State<CrewSection> createState() => _CrewSectionState();
}

class _CrewSectionState extends State<CrewSection> {
  CrewSelection? _selection;

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
                child: _OptionCard(
                  option: _options[0],
                  selection: _selection,
                  onSelect: _select,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _OptionCard(
                  option: _options[1],
                  selection: _selection,
                  onSelect: _select,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _OptionCard(
                  option: _options[2],
                  selection: _selection,
                  onSelect: _select,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _OptionCard(
                  option: _options[3],
                  selection: _selection,
                  onSelect: _select,
                ),
              ),
            ],
          ),
          if (_selection != null) ...[
            const SizedBox(height: 12),
            EntryCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              child: switch (_selection!) {
                CrewSelection.justMe => const CrewJustMe(),
                CrewSelection.withInstructor => const CrewWithInstructor(),
                CrewSelection.withOtherPilot => const CrewWithOtherPilot(),
                CrewSelection.withPassengers => const CrewWithPassengers(),
              },
            ),
          ],
        ],
      ),
    );
  }

  void _select(CrewSelection s) => setState(() => _selection = s);
}

class _OptionCard extends StatelessWidget {
  const _OptionCard({
    required this.option,
    required this.selection,
    required this.onSelect,
  });

  final (CrewSelection, String) option;
  final CrewSelection? selection;
  final ValueChanged<CrewSelection> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ink = context.inkTiers;
    final selected = option.$1 == selection;

    return InkWell(
      onTap: () => onSelect(option.$1),
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
