import 'package:flutter/material.dart';

import '../../../../domain/model/pilot_capacity.dart';
import '../../../theme/app_colors.dart';
import '../../entry_form_types.dart';
import '../duration_field.dart';
import '../entry_segmented_choice.dart';
import '../entry_toggle_row.dart';
import 'crew_form_data.dart';

const _roleLabels = {
  OtherPilotRole.requiredCrew: 'Required crew',
  OtherPilotRole.notRequiredCrew: 'Not required crew',
  OtherPilotRole.safetyPilot: 'Safety pilot',
};

/// §4C — the richest path, and the one that carries the FAA/EASA
/// divergence most sharply. "Who was in command" and "who was flying" are
/// deliberately two separate questions, not one.
class CrewWithOtherPilot extends StatelessWidget {
  const CrewWithOtherPilot({super.key, required this.data});

  final CrewFormData data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semanticColors;
    final multiPilot =
        data.multiPilotOperation || data.aircraftRequiresMultiCrew;
    final canClaimPicus =
        multiPilot && data.command == CommandChoice.otherPilot;
    final picus = canClaimPicus && data.picusClaimed;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Who was in command?', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          EntrySegmentedChoice<CommandChoice>(
            options: [for (final c in CommandChoice.values) (c, c.label)],
            selected: data.command,
            onChanged: data.onCommandChanged,
          ),
          const SizedBox(height: 14),
          Text('Who was flying?', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          EntrySegmentedChoice<FlyingChoice>(
            options: [for (final f in FlyingChoice.values) (f, f.label)],
            selected: data.flying,
            onChanged: data.onFlyingChanged,
          ),
          if (!multiPilot &&
              data.command == CommandChoice.otherPilot &&
              data.flying == FlyingChoice.otherPilot) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: semantic.divergenceSurface,
                border: Border.all(
                  color: semantic.divergence.withValues(alpha: 0.4),
                ),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 18,
                    color: semantic.divergence,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Single-pilot aircraft, another pilot in command, you not flying — '
                      'EASA records no time for this flight. Your FAA licence may permit '
                      'logging it.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: semantic.divergence,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          TextField(
            controller: data.otherPilotNameController,
            decoration: const InputDecoration(labelText: 'Other pilot name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: data.otherPilotLicenceController,
            decoration: const InputDecoration(
              labelText: 'Other pilot licence number',
            ),
          ),
          EntryToggleRow(
            label: 'Multi-pilot operation',
            subtitle: data.aircraftRequiresMultiCrew
                ? 'Pre-filled from the aircraft record'
                : null,
            value: multiPilot,
            onChanged: (_) => data.onToggleMultiPilot(),
          ),
          if (data.flying == FlyingChoice.bothSplit) ...[
            const SizedBox(height: 6),
            DurationField(
              label: 'My manipulation time',
              hoursController: data.otherManipHoursController,
              minutesController: data.otherManipMinutesController,
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 12),
          DropdownButtonFormField<OtherPilotRole>(
            initialValue: data.otherPilotRole,
            isExpanded: true,
            decoration: const InputDecoration(labelText: "Other pilot's role"),
            items: [
              for (final r in OtherPilotRole.values)
                DropdownMenuItem(value: r, child: Text(_roleLabels[r]!)),
            ],
            onChanged: data.onOtherPilotRoleChanged,
          ),
          if (canClaimPicus) ...[
            EntryToggleRow(
              label: 'Claim PICUS',
              value: picus,
              onChanged: (_) => data.onTogglePicus(),
            ),
            if (picus)
              Container(
                margin: const EdgeInsets.only(top: 4, bottom: 4),
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  border: Border.all(color: theme.colorScheme.outlineVariant),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: data.picInterventionNotRequired,
                      onChanged: (_) =>
                          data.onTogglePicInterventionNotRequired(),
                    ),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          'PIC intervention was not required at any point in '
                          'the flight.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (data.simulatedInstrumentPresent)
            EntryToggleRow(
              label: 'Safety pilot for my simulated instrument',
              subtitle: 'Records the name per §61.51(b)(1)(v)',
              value: data.otherPilotRole == OtherPilotRole.safetyPilot,
              onChanged: (v) => data.onOtherPilotRoleChanged(
                v ? OtherPilotRole.safetyPilot : null,
              ),
            ),
          EntryToggleRow(
            label: 'Passengers on board',
            subtitle: 'Required crew are not passengers',
            value: data.otherPilotPassengers,
            onChanged: (_) => data.onToggleOtherPilotPassengers(),
          ),
        ],
      ),
    );
  }
}
