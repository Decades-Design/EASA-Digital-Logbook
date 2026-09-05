import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// The one enclosing surface each section's content sits inside — a single
/// rounded card, not a bordered box per field. Rows within it are
/// separated by [EntryCardDivider], a hairline rule, rather than each row
/// getting its own container. This is the "cohesive form" shape from the
/// 1a/2b mockups: one card per group, thin internal rules, no nesting.
class EntryCard extends StatelessWidget {
  const EntryCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
  });

  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: child,
    );
  }
}

/// The hairline rule between rows inside an [EntryCard].
class EntryCardDivider extends StatelessWidget {
  const EntryCardDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

/// A label-left, value-right row inside an [EntryCard] — "Date", "Route",
/// and similar single-line facts. Wrap in [InkWell] via [onTap] when the
/// row opens a picker.
class EntryCardRow extends StatelessWidget {
  const EntryCardRow({
    super.key,
    required this.label,
    required this.child,
    this.onTap,
  });

  final String label;
  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;
    // #66: merges this row's own label into whatever control sits in
    // [child] — a bare Switch/DropdownButton otherwise announces only its
    // own state ("on", "Aeroplane") with no word saying what it's for,
    // since a sibling Text isn't merged into a control's semantics node
    // by default.
    final row = MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(color: ink.medium),
            ),
            const Spacer(),
            child,
          ],
        ),
      ),
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}
