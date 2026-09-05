import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';
import '../flight_diff.dart';

/// #59: what editing a *committed* entry looks like — a diff of what will
/// change, a statement that the previous version is retained, and an
/// optional free-text reason. Never a mandatory prompt or a preset
/// dropdown — [reason] is exactly the free text the pilot typed, `''` when
/// they left it blank, so an empty string still means "confirmed, no
/// reason given" and stays distinguishable from `null` ("cancelled").
///
/// Returns `null` if the pilot cancels.
Future<String?> showCommittedEditDialog(
  BuildContext context, {
  required List<FlightFieldChange> changes,
  required bool showFirstTimeExplanation,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) => _CommittedEditDialog(
      changes: changes,
      showFirstTimeExplanation: showFirstTimeExplanation,
    ),
  );
}

class _CommittedEditDialog extends StatefulWidget {
  const _CommittedEditDialog({
    required this.changes,
    required this.showFirstTimeExplanation,
  });

  final List<FlightFieldChange> changes;
  final bool showFirstTimeExplanation;

  @override
  State<_CommittedEditDialog> createState() => _CommittedEditDialogState();
}

class _CommittedEditDialogState extends State<_CommittedEditDialog> {
  final _reasonController = TextEditingController();

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;

    return AlertDialog(
      title: const Text('Save changes to this flight?'),
      content: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.showFirstTimeExplanation) ...[
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'This flight has already been exported, so — unlike a '
                  'draft — the previous version is kept rather than '
                  'overwritten: editing it appends a dated revision to its '
                  'history instead.',
                  style: theme.textTheme.bodySmall?.copyWith(color: ink.medium),
                ),
              ),
              const SizedBox(height: 12),
            ],
            Text(
              'The previous version is retained.',
              style: theme.textTheme.bodySmall?.copyWith(color: ink.muted),
            ),
            const SizedBox(height: 12),
            if (widget.changes.isEmpty)
              Text(
                'No fields changed.',
                style: theme.textTheme.bodyMedium?.copyWith(color: ink.muted),
              )
            else
              for (final change in widget.changes) _ChangeRow(change: change),
            const SizedBox(height: 16),
            TextField(
              controller: _reasonController,
              decoration: const InputDecoration(
                labelText: 'Reason (optional)',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              maxLines: 2,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.of(context).pop(_reasonController.text.trim()),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

class _ChangeRow extends StatelessWidget {
  const _ChangeRow({required this.change});

  final FlightFieldChange change;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(change.label, style: theme.textTheme.labelMedium),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: change.before,
                  style: AppMonoText.value(
                    ink.faint,
                    size: 12,
                  ).copyWith(decoration: TextDecoration.lineThrough),
                ),
                TextSpan(
                  text: '  →  ',
                  style: AppMonoText.value(ink.faint, size: 12),
                ),
                TextSpan(
                  text: change.after,
                  style: AppMonoText.value(
                    theme.colorScheme.onSurface,
                    size: 12,
                    weight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
