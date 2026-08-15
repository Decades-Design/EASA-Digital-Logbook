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
    required this.onSaveDraft,
  });

  final String title;
  final VoidCallback onSaveDraft;

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
            TextButton(
              onPressed: onSaveDraft,
              style: TextButton.styleFrom(foregroundColor: scheme.primary),
              child: const Text('Save draft'),
            ),
          ],
        ),
      ),
    );
  }
}
