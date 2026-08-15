import 'package:flutter/material.dart';

import '../../../theme/app_colors.dart';
import '../duration_field.dart';
import '../entry_segmented_choice.dart';
import '../entry_toggle_row.dart';

enum _Arrangement { receivingInstruction, inCommandObserving }

const _purposes = [
  'Training — general',
  'Skill test',
  'Proficiency check',
  'SEP/TMG revalidation refresher',
  'FAA flight review',
  'FAA IPC',
  'Instrument training',
];

/// §4B. Both arrangements share the same field set; only the arrangement
/// choice itself changes what gets derived (Dual vs SPIC under EASA).
///
/// Not built here: certificate-expiry (FAA-only, needs licence-held
/// detection), and the second arrangement option is shown unconditionally
/// rather than gated to student pilots under a licence profile — both need
/// a real pilot-profile source this screen doesn't have yet.
class CrewWithInstructor extends StatefulWidget {
  const CrewWithInstructor({super.key});

  @override
  State<CrewWithInstructor> createState() => _CrewWithInstructorState();
}

class _CrewWithInstructorState extends State<CrewWithInstructor> {
  _Arrangement _arrangement = _Arrangement.receivingInstruction;
  final _instructorName = TextEditingController();
  final _instructorLicence = TextEditingController();
  String? _purpose;
  bool _soleManipulator = true;
  final _manipHours = TextEditingController();
  final _manipMinutes = TextEditingController();
  bool _passengersOnBoard = false;
  bool _signed = false;
  DateTime? _signedAt;

  @override
  void dispose() {
    _instructorName.dispose();
    _instructorLicence.dispose();
    _manipHours.dispose();
    _manipMinutes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('What was the arrangement?', style: theme.textTheme.bodyMedium),
          const SizedBox(height: 8),
          EntrySegmentedChoice<_Arrangement>(
            options: const [
              (
                _Arrangement.receivingInstruction,
                'I was receiving instruction',
              ),
              (
                _Arrangement.inCommandObserving,
                'I was in command, instructor observing',
              ),
            ],
            selected: _arrangement,
            onChanged: (v) => setState(() => _arrangement = v),
          ),
          const SizedBox(height: 18),
          TextField(
            controller: _instructorName,
            decoration: const InputDecoration(labelText: 'Instructor name'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _instructorLicence,
            decoration: const InputDecoration(
              labelText: 'Instructor licence / certificate number',
            ),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _purpose,
            decoration: const InputDecoration(labelText: 'Purpose of flight'),
            items: [
              for (final p in _purposes)
                DropdownMenuItem(value: p, child: Text(p)),
            ],
            onChanged: (v) => setState(() => _purpose = v),
          ),
          EntryToggleRow(
            label: 'I was sole manipulator',
            value: _soleManipulator,
            onChanged: (v) => setState(() => _soleManipulator = v),
          ),
          if (!_soleManipulator) ...[
            const SizedBox(height: 6),
            DurationField(
              label: 'Manipulation time',
              hoursController: _manipHours,
              minutesController: _manipMinutes,
            ),
          ],
          EntryToggleRow(
            label: 'Passengers on board',
            value: _passengersOnBoard,
            onChanged: (v) => setState(() => _passengersOnBoard = v),
          ),
          const SizedBox(height: 8),
          _CountersignatureBlock(
            signed: _signed,
            signedAt: _signedAt,
            onSign: () => setState(() {
              _signed = true;
              _signedAt = DateTime.now();
            }),
          ),
        ],
      ),
    );
  }
}

/// Always present, never required to save (§4B). Uncountersigned SPIC/PICUS
/// time is not creditable, so this stays visible whether the flight is
/// saved as a draft or not — it just marks the entry as awaiting signature.
class _CountersignatureBlock extends StatelessWidget {
  const _CountersignatureBlock({
    required this.signed,
    required this.signedAt,
    required this.onSign,
  });

  final bool signed;
  final DateTime? signedAt;
  final VoidCallback onSign;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ink = context.inkTiers;
    final semantic = context.semanticColors;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: signed ? scheme.surface : semantic.currencyWarningSurface,
        border: Border.all(
          color: signed
              ? scheme.outlineVariant
              : semantic.currencyWarning.withValues(alpha: 0.4),
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(
            signed ? Icons.check_circle : Icons.schedule,
            size: 18,
            color: signed ? ink.muted : semantic.currencyWarning,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              signed
                  ? 'Countersigned at ${_formatTime(signedAt!)}'
                  : 'Awaiting countersignature',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: signed ? ink.medium : semantic.currencyWarning,
              ),
            ),
          ),
          if (!signed)
            TextButton(onPressed: onSign, child: const Text('Sign now')),
        ],
      ),
    );
  }
}

String _formatTime(DateTime t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
