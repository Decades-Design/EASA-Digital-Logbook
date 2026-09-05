import 'package:flutter/material.dart';

/// A minimal, standalone chip for picking a jurisdiction — shared by
/// Currency (an optional filter, `T = String?` where `null` means "Both")
/// and Totals (`T = String`, always exactly one held licence, no "Both").
///
/// Always renders [label] as its own trigger text, so a selection is a
/// visible, chosen state rather than a silent default — CLAUDE.md's
/// Multi-jurisdiction UX section requires exactly this: "never a global
/// toggle that silently changes what the numbers mean." Deliberately never
/// wrapped in a sentence ("Derived under ... licence") by a caller — the
/// chip is meant to read on its own, the way a filter or segmented control
/// does elsewhere in this app.
///
/// A dropdown, not the pill switches used elsewhere in this app (Totals'
/// granularity switch, Aerodromes' Map/List, Settings' Theme/Time-display):
/// those all pick from a small fixed set that will never grow, where a
/// dropdown's extra tap would be friction for no reason. A jurisdiction list
/// grows as licences are added (CLAUDE.md's jurisdiction registry is
/// explicitly open-ended), so this needs to scale past two or three options
/// without redesigning the control.
///
/// Built on [showMenu] directly rather than [PopupMenuButton]: the latter's
/// `showButtonMenu` treats *any* `null` return from the overlay as "dismissed
/// without a selection" and calls `onCanceled` instead of `onSelected` --
/// indistinguishable from a genuine selection when `T` is itself nullable
/// (Currency's `T = String?`, where `null` *is* "Both"). Selecting by index
/// instead of by value sidesteps that ambiguity entirely, for any `T`.
class JurisdictionDropdown<T> extends StatelessWidget {
  const JurisdictionDropdown({
    super.key,
    required this.value,
    required this.label,
    required this.options,
    required this.onChanged,
    this.dark = false,
  });

  final T value;
  final String label;

  /// Menu items in display order, value to label.
  final Map<T, String> options;
  final ValueChanged<T> onChanged;

  /// Renders a fixed light-on-dark chip regardless of the app's own theme
  /// brightness -- for a caller like Totals' hero card, which (like the
  /// NIGHT badge) stays dark always rather than following Settings' Light/
  /// Dark/System choice.
  final bool dark;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = dark ? Colors.white : theme.colorScheme.primary;
    final background = dark
        ? Colors.white.withValues(alpha: 0.16)
        : theme.colorScheme.primary.withValues(alpha: 0.09);
    final entries = options.entries.toList(growable: false);

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _openMenu(context, entries, foreground),
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: theme.textTheme.labelLarge?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 3),
            Icon(Icons.expand_more, size: 16, color: foreground),
          ],
        ),
      ),
    );
  }

  Future<void> _openMenu(
    BuildContext context,
    List<MapEntry<T, String>> entries,
    Color foreground,
  ) async {
    final button = context.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        button.localToGlobal(
          Offset(0, button.size.height + 4),
          ancestor: overlay,
        ),
        button.localToGlobal(
          button.size.bottomRight(Offset.zero),
          ancestor: overlay,
        ),
      ),
      Offset.zero & overlay.size,
    );

    // Selecting by index rather than by `entries[i].key` directly -- see the
    // class dartdoc -- so a legitimate `null` value is never confused with
    // the overlay's own "dismissed without choosing" result.
    final index = await showMenu<int>(
      context: context,
      position: position,
      items: [
        for (var i = 0; i < entries.length; i++)
          PopupMenuItem<int>(
            value: i,
            child: Text(
              entries[i].value,
              style: entries[i].key == value
                  ? const TextStyle(fontWeight: FontWeight.w700)
                  : null,
            ),
          ),
      ],
    );
    if (index != null) onChanged(entries[index].key);
  }
}
