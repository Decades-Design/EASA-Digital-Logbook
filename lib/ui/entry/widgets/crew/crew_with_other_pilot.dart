import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../duration_field.dart';
import '../entry_segmented_choice.dart';
import '../entry_toggle_row.dart';

enum _Command { me, other }

enum _Flying { me, other, bothSplit }

enum _OtherPilotRole { requiredCrew, notRequiredCrew, safetyPilot }

const _roleLabels = {
  _OtherPilotRole.requiredCrew: 'Required crew',
  _OtherPilotRole.notRequiredCrew: 'Not required crew',
  _OtherPilotRole.safetyPilot: 'Safety pilot',
};

/// §4C — the richest path, and the one that carries the FAA/EASA
/// divergence most sharply. "Who was in command" and "who was flying" are
/// deliberately two separate questions, not one.
///
/// Not built here: the "safety pilot for my simulated instrument" toggle,
/// which §4C gates on simulated-instrument time being greater than zero —
/// that field lives in §6 Conditions, which this form doesn't have yet, so
/// there's nothing to gate on.
class CrewWithOtherPilot extends StatefulWidget {
  const CrewWithOtherPilot({super.key});

  @override
  State<CrewWithOtherPilot> createState() => _CrewWithOtherPilotState();
}

class _CrewWithOtherPilotState extends State<CrewWithOtherPilot> {
  _Command _command = _Command.me;
  _Flying _flying = _Flying.me;
  final _otherPilotName = TextEditingController();
  final _otherPilotLicence = TextEditingController();
  bool _multiPilot = false;
  final _myManipHours = TextEditingController();
  final _myManipMinutes = TextEditingController();
  _OtherPilotRole? _otherPilotRole;
  bool _claimPicus = false;
  bool _interventionNotRequired = false;
  bool _passengersOnBoard = false;

  @override
  void dispose() {
    _otherPilotName.dispose();
    _otherPilotLicence.dispose();
    _myManipHours.dispose();
    _myManipMinutes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semanticColors;
    final canClaimPicus = _multiPilot && _command == _Command.other;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Who was in command?', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          EntrySegmentedChoice<_Command>(
            options: const [
              (_Command.me, 'Me'),
              (_Command.other, 'Other pilot'),
            ],
            selected: _command,
            onChanged: (v) => setState(() => _command = v),
          ),
          const SizedBox(height: 14),
          Text('Who was flying?', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          EntrySegmentedChoice<_Flying>(
            options: const [
              (_Flying.me, 'Me'),
              (_Flying.other, 'Other pilot'),
              (_Flying.bothSplit, 'Both — split'),
            ],
            selected: _flying,
            onChanged: (v) => setState(() => _flying = v),
          ),
          if (!_multiPilot &&
              _command == _Command.other &&
              _flying == _Flying.other) ...[
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
            controller: _otherPilotName,
            decoration: const InputDecoration(labelText: 'Other pilot name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _otherPilotLicence,
            decoration: const InputDecoration(
              labelText: 'Other pilot licence number',
            ),
          ),
          EntryToggleRow(
            label: 'Multi-pilot operation',
            subtitle: 'Pre-filled from the aircraft record once wired',
            value: _multiPilot,
            onChanged: (v) => setState(() => _multiPilot = v),
          ),
          if (_flying == _Flying.bothSplit) ...[
            const SizedBox(height: 6),
            DurationField(
              label: 'My manipulation time',
              hoursController: _myManipHours,
              minutesController: _myManipMinutes,
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 12),
          DropdownButtonFormField<_OtherPilotRole>(
            initialValue: _otherPilotRole,
            decoration: const InputDecoration(labelText: "Other pilot's role"),
            items: [
              for (final r in _OtherPilotRole.values)
                DropdownMenuItem(value: r, child: Text(_roleLabels[r]!)),
            ],
            onChanged: (v) => setState(() => _otherPilotRole = v),
          ),
          if (canClaimPicus) ...[
            EntryToggleRow(
              label: 'Claim PICUS',
              value: _claimPicus,
              onChanged: (v) => setState(() => _claimPicus = v),
            ),
            if (_claimPicus)
              CheckboxListTile(
                value: _interventionNotRequired,
                onChanged: (v) =>
                    setState(() => _interventionNotRequired = v ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(
                  'PIC intervention was not required',
                  style: theme.textTheme.bodyMedium,
                ),
              ),
          ],
          EntryToggleRow(
            label: 'Passengers on board',
            subtitle: 'Required crew are not passengers',
            value: _passengersOnBoard,
            onChanged: (v) => setState(() => _passengersOnBoard = v),
          ),
        ],
      ),
    );
  }
}
