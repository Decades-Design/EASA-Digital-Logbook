import 'package:flutter/material.dart';

import '../../../domain/model/flight.dart';
import '../../theme/app_colors.dart';
import 'approach_row.dart';
import 'counter_stepper.dart';
import 'duration_field.dart';
import 'entry_card.dart';
import 'entry_section_label.dart';
import 'entry_toggle_row.dart';

/// §6 of docs/entry-form.md.
///
/// One deliberate departure from the visual mockup: the mockup's "IFR time"
/// field is a free duration, but `Flight.ifrFlightPlanFiled` — the only
/// domain fact `easaInstrumentTime` reads — is a boolean (AMC1 FCL.050
/// column 9 counts the *whole* block time once a flight plan is filed, not
/// a sub-duration of it; see `easa_instrument_time.dart`). A free-text IFR
/// duration has no computational meaning in this codebase, so this section
/// asks the yes/no operational question the projection engine actually
/// uses instead of inventing an unbacked raw fact (CLAUDE.md rule 1).
///
/// "Night time" has the same problem in reverse: it's genuinely a duration,
/// but it's *entirely derived* (no raw `Flight.nightTime` field exists —
/// see `easa_night_time.dart`/`faa_night_time.dart`), and this app has no
/// override-with-reason mechanism yet (§8) to let a pilot's manual entry
/// coexist with the computed figure. It's kept here as a plain UI value,
/// not fed into the draft `Flight` at all, until #8's override plumbing
/// lands.
class ConditionsSection extends StatelessWidget {
  const ConditionsSection({
    super.key,
    required this.blockTime,
    required this.nightHoursController,
    required this.nightMinutesController,
    required this.hasEasaLicence,
    required this.ifrFlightPlanFiled,
    required this.onToggleIfrFlightPlanFiled,
    required this.hasFaaLicence,
    required this.actualInstHoursController,
    required this.actualInstMinutesController,
    required this.simInstHoursController,
    required this.simInstMinutesController,
    required this.approaches,
    required this.approachIcaoControllers,
    required this.approachRunwayControllers,
    required this.onApproachTypeChanged,
    required this.onApproachIcaoChanged,
    required this.onApproachRunwayChanged,
    required this.onApproachCountChanged,
    required this.onApproachRemoved,
    required this.onApproachAdded,
    required this.holdingProceduresCount,
    required this.onHoldingProceduresChanged,
    required this.trackingPerformed,
    required this.onToggleTracking,
  });

  /// Feeds each field's "fill from block time" shortcut — see
  /// `duration_field.dart`. Null (times not yet entered) simply hides the
  /// shortcut everywhere in this section.
  final Duration? blockTime;

  final TextEditingController nightHoursController;
  final TextEditingController nightMinutesController;

  final bool hasEasaLicence;
  final bool ifrFlightPlanFiled;
  final VoidCallback onToggleIfrFlightPlanFiled;

  final bool hasFaaLicence;
  final TextEditingController actualInstHoursController;
  final TextEditingController actualInstMinutesController;
  final TextEditingController simInstHoursController;
  final TextEditingController simInstMinutesController;

  final List<Approach> approaches;
  final List<TextEditingController> approachIcaoControllers;
  final List<TextEditingController> approachRunwayControllers;
  final void Function(int index, ApproachType type) onApproachTypeChanged;
  final void Function(int index, String icao) onApproachIcaoChanged;
  final void Function(int index, String runway) onApproachRunwayChanged;
  final void Function(int index, int count) onApproachCountChanged;
  final ValueChanged<int> onApproachRemoved;
  final VoidCallback onApproachAdded;

  final int holdingProceduresCount;
  final ValueChanged<int> onHoldingProceduresChanged;
  final bool trackingPerformed;
  final VoidCallback onToggleTracking;

  String? get _blockTimeText {
    final block = blockTime;
    if (block == null) return null;
    final hours = block.inHours;
    final minutes = block.inMinutes.remainder(60).abs();
    return '$hours:${minutes.toString().padLeft(2, '0')}';
  }

  /// Sets both controllers directly rather than routing through a
  /// parent-owned callback — `NewFlightScreen` already attaches a rebuild
  /// listener to every duration controller in this section (see its
  /// `initState`), so writing `.text` here is enough to keep the
  /// derivation strip in sync, the same way a pilot typing into the field
  /// by hand would.
  void _fillFromBlock(
    TextEditingController hours,
    TextEditingController minutes,
  ) {
    final block = blockTime;
    if (block == null) return;
    hours.text = block.inHours.toString();
    minutes.text = block.inMinutes
        .remainder(60)
        .abs()
        .toString()
        .padLeft(2, '0');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      children: [
        EntrySection(
          label: 'Conditions',
          child: EntryCard(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            child: Column(
              children: [
                _ConditionRow(
                  label: 'Night time',
                  hint: 'not yet auto-computed — enter directly',
                  child: DurationField(
                    label: '',
                    hoursController: nightHoursController,
                    minutesController: nightMinutesController,
                    blockTimeText: _blockTimeText,
                    onFillFromBlock: blockTime == null
                        ? null
                        : () => _fillFromBlock(
                            nightHoursController,
                            nightMinutesController,
                          ),
                  ),
                ),
                if (hasEasaLicence) ...[
                  const EntryCardDivider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: EntryToggleRow(
                      label: 'IFR flight plan filed',
                      subtitle:
                          'Operational condition, independent of actual met '
                          'conditions',
                      value: ifrFlightPlanFiled,
                      onChanged: (_) => onToggleIfrFlightPlanFiled(),
                    ),
                  ),
                ],
                if (hasFaaLicence) ...[
                  const EntryCardDivider(),
                  _ConditionRow(
                    label: 'Actual instrument',
                    hint: '§61.51(g)(1) — solely by reference to instruments',
                    child: DurationField(
                      label: '',
                      hoursController: actualInstHoursController,
                      minutesController: actualInstMinutesController,
                      blockTimeText: _blockTimeText,
                      onFillFromBlock: blockTime == null
                          ? null
                          : () => _fillFromBlock(
                              actualInstHoursController,
                              actualInstMinutesController,
                            ),
                    ),
                  ),
                  const EntryCardDivider(),
                  _ConditionRow(
                    label: 'Simulated instrument',
                    hint: 'under a view-limiting device',
                    child: DurationField(
                      label: '',
                      hoursController: simInstHoursController,
                      minutesController: simInstMinutesController,
                      blockTimeText: _blockTimeText,
                      onFillFromBlock: blockTime == null
                          ? null
                          : () => _fillFromBlock(
                              simInstHoursController,
                              simInstMinutesController,
                            ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
        if (hasFaaLicence)
          EntrySection(
            label: 'IR currency and proficiency',
            trailing: Text(
              'FAA §61.57(c)',
              style: theme.textTheme.labelSmall?.copyWith(
                color: context.inkTiers.faint,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < approaches.length; i++) ...[
                  ApproachRow(
                    approach: approaches[i],
                    icaoController: approachIcaoControllers[i],
                    runwayController: approachRunwayControllers[i],
                    onTypeChanged: (t) => onApproachTypeChanged(i, t),
                    onIcaoChanged: (v) => onApproachIcaoChanged(i, v),
                    onRunwayChanged: (v) => onApproachRunwayChanged(i, v),
                    onCountChanged: (c) => onApproachCountChanged(i, c),
                    onRemove: () => onApproachRemoved(i),
                  ),
                  const SizedBox(height: 8),
                ],
                OutlinedButton(
                  onPressed: onApproachAdded,
                  child: const Text('+ Add approach'),
                ),
                const SizedBox(height: 13),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        'Holding procedures',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    CounterStepper(
                      width: 128,
                      value: holdingProceduresCount,
                      onIncrement: () => onHoldingProceduresChanged(
                        holdingProceduresCount + 1,
                      ),
                      onDecrement: holdingProceduresCount > 0
                          ? () => onHoldingProceduresChanged(
                              holdingProceduresCount - 1,
                            )
                          : null,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                EntryToggleRow(
                  label: 'Intercepted and tracked a course',
                  value: trackingPerformed,
                  onChanged: (_) => onToggleTracking(),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _ConditionRow extends StatelessWidget {
  const _ConditionRow({
    required this.label,
    required this.hint,
    required this.child,
  });

  final String label;
  final String hint;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: theme.textTheme.bodyMedium),
                const SizedBox(height: 2),
                Text(
                  hint,
                  style: theme.textTheme.labelSmall?.copyWith(color: ink.faint),
                ),
              ],
            ),
          ),
          child,
        ],
      ),
    );
  }
}
