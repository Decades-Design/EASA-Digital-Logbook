import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';

/// §4A. The simplest path — resolves sole occupancy, sole manipulator and
/// command in one tap, no fields in the base case.
///
/// Not built here: the student-pilot solo-endorsement fields §4A adds when
/// the pilot's licence profile indicates student status. That needs a real
/// pilot profile/licence source, which this screen doesn't read yet.
class CrewJustMe extends StatelessWidget {
  const CrewJustMe({super.key});

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
              'Sole occupant. PIC time computed automatically.',
              style: theme.textTheme.bodyMedium?.copyWith(color: ink.muted),
            ),
          ),
        ],
      ),
    );
  }
}
