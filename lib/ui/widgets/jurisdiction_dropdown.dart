import 'package:flutter/material.dart';

/// A pill-styled dropdown for picking a jurisdiction — shared by Currency
/// (an optional filter, `T = String?` where `null` means "Both") and Totals
/// (`T = String`, always exactly one held licence, no "Both").
///
/// Always renders [label] as its own trigger text, so a selection is a
/// visible, chosen state rather than a silent default — CLAUDE.md's
/// Multi-jurisdiction UX section requires exactly this: "never a global
/// toggle that silently changes what the numbers mean."
///
/// A dropdown, not the pill switches used elsewhere in this app (Totals'
/// granularity switch, Aerodromes' Map/List, Settings' Theme/Time-display):
/// those all pick from a small fixed set that will never grow, where a
/// dropdown's extra tap would be friction for no reason. A jurisdiction list
/// grows as licences are added (CLAUDE.md's jurisdiction registry is
/// explicitly open-ended), so this needs to scale past two or three options
/// without redesigning the control.
class JurisdictionDropdown<T> extends StatelessWidget {
  const JurisdictionDropdown({
    super.key,
    required this.value,
    required this.label,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final String label;

  /// Menu items in display order, value to label.
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return PopupMenuButton<T>(
      initialValue: value,
      onSelected: onChanged,
      position: PopupMenuPosition.under,
      itemBuilder: (context) => [
        for (final entry in options.entries)
          PopupMenuItem<T>(value: entry.key, child: Text(entry.value)),
      ],
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: scheme.surface,
          border: Border.all(color: scheme.outlineVariant),
          borderRadius: BorderRadius.circular(15),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: scheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 2),
            Icon(Icons.arrow_drop_down, size: 18, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}
