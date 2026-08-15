import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';

/// §4D. No fields — selecting this path is the assertion that passengers
/// were carried and no other pilot was aboard; command is self by
/// definition. Night passenger carriage is derived elsewhere (passengers
/// aboard + night time > 0), never asked here.
class CrewWithPassengers extends StatelessWidget {
  const CrewWithPassengers({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        children: [
          Icon(Icons.check_circle_outline, size: 18, color: ink.muted),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Passengers aboard, no other pilot. Command is you by definition.',
              style: theme.textTheme.bodyMedium?.copyWith(color: ink.muted),
            ),
          ),
        ],
      ),
    );
  }
}
