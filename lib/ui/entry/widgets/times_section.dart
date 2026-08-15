import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'entry_card.dart';
import 'entry_section_label.dart';
import 'entry_value_column.dart';

/// §2 of docs/entry-form.md. Block time (off blocks → on blocks) is the
/// legal figure under both EASA and FAA — this is not an "air time first"
/// mode dressed up, it's the one time figure every jurisdiction agrees on.
///
/// Local entry with a persistent UTC echo beneath: what's typed is what the
/// pilot thinks in, UTC is what's stored (CLAUDE.md rule 3). The echo here
/// is a stub — real timezone resolution against the departure aerodrome is
/// a data-layer concern (#63), not this widget's.
class TimesSection extends StatefulWidget {
  const TimesSection({
    super.key,
    required this.offBlocks,
    required this.onBlocks,
    required this.onTapOffBlocks,
    required this.onTapOnBlocks,
    required this.blockTime,
    required this.takeoff,
    required this.landing,
    required this.onTapTakeoff,
    required this.onTapLanding,
  });

  final TimeOfDay? offBlocks;
  final TimeOfDay? onBlocks;
  final VoidCallback onTapOffBlocks;
  final VoidCallback onTapOnBlocks;
  final Duration? blockTime;
  final TimeOfDay? takeoff;
  final TimeOfDay? landing;
  final VoidCallback onTapTakeoff;
  final VoidCallback onTapLanding;

  @override
  State<TimesSection> createState() => _TimesSectionState();
}

class _TimesSectionState extends State<TimesSection> {
  bool _airTimeExpanded = false;

  @override
  Widget build(BuildContext context) {
    final ink = context.inkTiers;
    final theme = Theme.of(context);

    return EntrySection(
      label: 'Times',
      trailing: Text(
        'LOCAL · STORED UTC',
        style: theme.textTheme.labelSmall?.copyWith(
          color: ink.faint,
          letterSpacing: 0.6,
        ),
      ),
      child: EntryCard(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 4),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: EntryValueColumn(
                    label: 'Off blocks',
                    value: widget.offBlocks != null
                        ? _formatTimeOfDay(widget.offBlocks!)
                        : '--:--',
                    subValue: widget.offBlocks != null
                        ? '${_formatTimeOfDay(widget.offBlocks!)}Z'
                        : null,
                    placeholder: widget.offBlocks == null,
                    onTap: widget.onTapOffBlocks,
                  ),
                ),
                Expanded(
                  child: EntryValueColumn(
                    label: 'On blocks',
                    value: widget.onBlocks != null
                        ? _formatTimeOfDay(widget.onBlocks!)
                        : '--:--',
                    subValue: widget.onBlocks != null
                        ? '${_formatTimeOfDay(widget.onBlocks!)}Z'
                        : null,
                    placeholder: widget.onBlocks == null,
                    onTap: widget.onTapOnBlocks,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.only(left: 12),
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  child: EntryValueColumn(
                    label: 'Block',
                    value: widget.blockTime != null
                        ? _formatDuration(widget.blockTime!)
                        : '—:—',
                    accent: true,
                    placeholder: widget.blockTime == null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            const EntryCardDivider(),
            InkWell(
              onTap: () => setState(() => _airTimeExpanded = !_airTimeExpanded),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(
                  children: [
                    AnimatedRotation(
                      turns: _airTimeExpanded ? 0.25 : 0,
                      duration: const Duration(milliseconds: 150),
                      child: Icon(
                        Icons.chevron_right,
                        size: 18,
                        color: ink.muted,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Air time',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: ink.medium,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      'optional',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: ink.faint,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_airTimeExpanded)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: EntryValueColumn(
                        label: 'Take-off',
                        value: widget.takeoff != null
                            ? _formatTimeOfDay(widget.takeoff!)
                            : '--:--',
                        placeholder: widget.takeoff == null,
                        onTap: widget.onTapTakeoff,
                      ),
                    ),
                    Expanded(
                      child: EntryValueColumn(
                        label: 'Landing',
                        value: widget.landing != null
                            ? _formatTimeOfDay(widget.landing!)
                            : '--:--',
                        placeholder: widget.landing == null,
                        onTap: widget.onTapLanding,
                      ),
                    ),
                    const Expanded(child: SizedBox()),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _formatTimeOfDay(TimeOfDay t) =>
    '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

String _formatDuration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60).abs();
  return '$hours:${minutes.toString().padLeft(2, '0')}';
}
