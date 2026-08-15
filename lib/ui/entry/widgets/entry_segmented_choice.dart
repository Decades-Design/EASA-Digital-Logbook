import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// A row of pill buttons for a short, prominent either/or/or choice — the
/// crew four-way selector, the 4B arrangement question, and 4C's "who was
/// in command"/"who was flying" questions all use this rather than a
/// dropdown, matching how docs/entry-form.md presents them as buttons, not
/// menus.
class EntrySegmentedChoice<T> extends StatelessWidget {
  const EntrySegmentedChoice({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
  });

  final List<(T value, String label)> options;
  final T? selected;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ink = context.inkTiers;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (value, label) in options)
          ChoiceChip(
            label: Text(label),
            selected: selected == value,
            onSelected: (_) => onChanged(value),
            showCheckmark: false,
            backgroundColor: scheme.surface,
            selectedColor: scheme.primary,
            side: BorderSide(
              color: selected == value
                  ? Colors.transparent
                  : scheme.outlineVariant,
            ),
            labelStyle: theme.textTheme.labelLarge?.copyWith(
              color: selected == value ? scheme.onPrimary : ink.medium,
            ),
          ),
      ],
    );
  }
}
