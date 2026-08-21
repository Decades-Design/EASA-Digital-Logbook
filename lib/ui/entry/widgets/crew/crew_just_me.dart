import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../entry_toggle_row.dart';
import 'crew_form_data.dart';

/// §4A. The simplest path — resolves sole occupancy, sole manipulator and
/// command in one tap. When the pilot's licence profile indicates student
/// status, §61.51(e)(4) needs a §61.87 solo endorsement before PIC can be
/// logged, so those two fields appear; [CrewFormData.isStudent] is a stub
/// (always `false`) until a real pilot-profile source exists.
class CrewJustMe extends StatelessWidget {
  const CrewJustMe({super.key, required this.data});

  final CrewFormData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.check_circle_outline, size: 18, color: ink.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Sole occupant, sole manipulator and command all follow '
                  'from this answer. Nothing further to enter.',
                  style: theme.textTheme.bodyMedium?.copyWith(color: ink.muted),
                ),
              ),
            ],
          ),
          if (data.isStudent) ...[
            const SizedBox(height: 11),
            const Divider(height: 1),
            const SizedBox(height: 11),
            EntryToggleRow(
              label: 'Solo endorsement held',
              value: data.soloEndorsementHeld,
              onChanged: (_) => data.onToggleSoloEndorsement(),
            ),
            const SizedBox(height: 6),
            TextField(
              controller: data.endorsingInstructorController,
              decoration: const InputDecoration(
                labelText: 'Endorsing instructor',
              ),
            ),
          ],
        ],
      ),
    );
  }
}
