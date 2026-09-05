import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';

/// The mockups' lightweight text nav row — Cancel / title / Save draft —
/// rather than a standard elevated [AppBar]. Matches the calm, chrome-light
/// feel of the rest of the entry form instead of introducing a heavier
/// Material app bar just for this one screen.
class EntryTopBar extends StatelessWidget {
  const EntryTopBar({
    super.key,
    required this.title,
    this.onSaveDraft,
    this.saveLabel = 'Save draft',
  });

  final String title;

  /// `null` hides the quick save button entirely — editing a committed
  /// entry (#59) needs the diff/reason flow the footer's own primary
  /// button drives, not a shortcut that skips it.
  final VoidCallback? onSaveDraft;
  final String saveLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ink = context.inkTiers;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 6, 16, 8),
        child: Row(
          children: [
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              style: TextButton.styleFrom(foregroundColor: ink.muted),
              child: const Text('Cancel'),
            ),
            Expanded(
              child: Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleMedium,
              ),
            ),
            if (onSaveDraft != null)
              TextButton(
                onPressed: onSaveDraft,
                style: TextButton.styleFrom(foregroundColor: scheme.primary),
                child: Text(saveLabel),
              )
            else
              const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}
