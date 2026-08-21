import 'package:flutter/material.dart';

import '../../../domain/model/flight.dart';
import '../../theme/app_colors.dart';
import 'counter_stepper.dart';

const _approachTypeLabels = {
  ApproachType.ils: 'ILS',
  ApproachType.rnav: 'RNAV',
  ApproachType.gps: 'GPS',
  ApproachType.vor: 'VOR',
  ApproachType.loc: 'LOC',
  ApproachType.ndb: 'NDB',
  ApproachType.backCourse: 'Back course',
  ApproachType.lda: 'LDA',
  ApproachType.sdf: 'SDF',
  ApproachType.tacan: 'TACAN',
  ApproachType.par: 'PAR',
  ApproachType.asr: 'ASR',
  ApproachType.mls: 'MLS',
};

/// One row of the IR Currency and Proficiency group (§6): a distinct
/// instrument approach procedure, and how many times it was flown. One
/// [Approach] per distinct procedure, not per approach flown —
/// `Flight.approaches`'s own dartdoc.
class ApproachRow extends StatelessWidget {
  const ApproachRow({
    super.key,
    required this.approach,
    required this.icaoController,
    required this.runwayController,
    required this.onTypeChanged,
    required this.onIcaoChanged,
    required this.onRunwayChanged,
    required this.onCountChanged,
    required this.onRemove,
  });

  final Approach approach;

  /// Owned and disposed by the parent screen, alongside `_approaches` itself
  /// — mirrors `DateRouteSection`'s leg-controller list, since both are a
  /// dynamic list of rows each carrying its own free-text field.
  final TextEditingController icaoController;
  final TextEditingController runwayController;
  final ValueChanged<ApproachType> onTypeChanged;
  final ValueChanged<String> onIcaoChanged;
  final ValueChanged<String> onRunwayChanged;
  final ValueChanged<int> onCountChanged;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        border: Border.all(color: theme.colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<ApproachType>(
                  initialValue: approach.type,
                  isDense: true,
                  isExpanded: true,
                  // Matches the ICAO/runway fields' own override below —
                  // without it this box uses the theme default (14/12)
                  // instead of their tightened padding, and the two end up
                  // visibly different heights side by side.
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                  ),
                  style: const TextStyle(
                    fontFamily: 'IBM Plex Mono',
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                  items: [
                    for (final t in ApproachType.values)
                      DropdownMenuItem(
                        value: t,
                        child: Text(_approachTypeLabels[t]!),
                      ),
                  ],
                  onChanged: (v) {
                    if (v != null) onTypeChanged(v);
                  },
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                // The app's default InputDecorationTheme pads every field
                // 14px each side for a normal-width field — left as-is,
                // that alone eats more than half of a box this narrow and
                // clips whatever's typed. Both fields override it directly
                // rather than widening indefinitely to outrun the default.
                width: 72,
                child: TextField(
                  controller: icaoController,
                  textAlign: TextAlign.center,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 4,
                  style: const TextStyle(
                    fontFamily: 'IBM Plex Mono',
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    counterText: '',
                    hintText: 'ICAO',
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 10,
                    ),
                  ),
                  onChanged: (v) => onIcaoChanged(v.toUpperCase()),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                width: 60,
                child: TextField(
                  controller: runwayController,
                  textAlign: TextAlign.center,
                  textCapitalization: TextCapitalization.characters,
                  maxLength: 3,
                  style: const TextStyle(
                    fontFamily: 'IBM Plex Mono',
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                  decoration: const InputDecoration(
                    isDense: true,
                    counterText: '',
                    hintText: 'RWY',
                    contentPadding: EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 10,
                    ),
                  ),
                  onChanged: (v) => onRunwayChanged(v.toUpperCase()),
                ),
              ),
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.close, size: 16),
                visualDensity: VisualDensity.compact,
                color: ink.faint,
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Flown',
                style: theme.textTheme.bodySmall?.copyWith(color: ink.muted),
              ),
              CounterStepper(
                width: 120,
                compact: true,
                value: approach.count,
                onIncrement: () => onCountChanged(approach.count + 1),
                onDecrement: approach.count > 1
                    ? () => onCountChanged(approach.count - 1)
                    : null,
              ),
            ],
          ),
        ],
      ),
    );
  }
}
