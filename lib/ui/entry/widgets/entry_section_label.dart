import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// The small uppercase mono label above each section of the entry form —
/// "AIRCRAFT", "DATE & ROUTE", "TIMES". Sections are told apart by this
/// label and plain whitespace, not by boxing each one off in its own
/// bordered container — see [EntryCard] for the one enclosing surface a
/// section's actual content sits in, where it needs one at all.
class EntrySectionLabel extends StatelessWidget {
  const EntrySectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final ink = context.inkTiers;
    return Text(
      text.toUpperCase(),
      style: AppMonoText.value(
        ink.faint,
        size: 11.5,
        weight: FontWeight.w600,
      ).copyWith(letterSpacing: 1.2),
    );
  }
}

/// A section of the scrolling entry form: a label, optional trailing note,
/// then its content. Purely spacing — no border, no card of its own, so
/// consecutive sections read as one flowing form rather than a stack of
/// separate boxes.
class EntrySection extends StatelessWidget {
  const EntrySection({
    super.key,
    required this.label,
    required this.child,
    this.trailing,
  });

  final String label;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (trailing == null)
            EntrySectionLabel(label)
          else
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(child: EntrySectionLabel(label)),
                const SizedBox(width: 8),
                trailing!,
              ],
            ),
          const SizedBox(height: 8),
          child,
        ],
      ),
    );
  }
}
