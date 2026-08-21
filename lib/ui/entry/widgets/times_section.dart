import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'entry_card.dart';
import 'entry_section_label.dart';
import 'entry_value_column.dart';

/// §2 of docs/entry-form.md. Block time (off blocks → on blocks) is the
/// legal figure under both EASA and FAA — this is not an "air time first"
/// mode dressed up, it's the one time figure every jurisdiction agrees on.
///
/// Entry is Zulu, not local — CLAUDE.md rule 3 ("all stored times are
/// UTC... never persist a naive DateTime") applies just as much to what the
/// pilot types as to what ends up in `Flight`, so there is no separate
/// "local entry, UTC echo" mode to get out of sync with each other. A local
/// reference under each field, computed from the departure/destination
/// ICAO's timezone, was scoped for this pass but deferred: it needs either
/// a bundled lat/lon→IANA-timezone dataset (the one Dart package found for
/// this is a ~150MB geo-boundary database, impractical for a mobile app and
/// a per-keystroke field) or a smaller airport-keyed dataset like
/// OpenFlights' `airports.dat`, neither of which is in this repo yet. Land
/// that as its own pass rather than half-wiring it here.
///
/// The block figure is itself editable: typing a value that differs from
/// the computed one is an override (docs/entry-form.md §2 — "store the
/// override alongside the raw times; never silently rewrite the times to
/// match"). The override is display-only for now: it never rewrites
/// [offBlocks]/[onBlocks], and — since `Flight` has nowhere to persist a
/// block-time override yet — it isn't fed into the draft `Flight` used for
/// the derivation strip either. That's `flight_draft_mapper.dart`'s
/// [DraftFlightInputs] deliberately not taking one.
class TimesSection extends StatefulWidget {
  const TimesSection({
    super.key,
    required this.offBlocks,
    required this.onBlocks,
    required this.onTapOffBlocks,
    required this.onTapOnBlocks,
    required this.blockTime,
    required this.blockOverrideText,
    required this.onBlockOverrideChanged,
    required this.startLabel,
    required this.endLabel,
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

  /// The pilot's raw override text, or `null`/empty when not overridden.
  final String? blockOverrideText;
  final ValueChanged<String> onBlockOverrideChanged;

  /// "Off blocks"/"On blocks" for an aeroplane, "Rotors start"/"Rotors
  /// stop" for a helicopter — read from the resolved aircraft's category.
  final String startLabel;
  final String endLabel;

  final TimeOfDay? takeoff;
  final TimeOfDay? landing;
  final VoidCallback onTapTakeoff;
  final VoidCallback onTapLanding;

  @override
  State<TimesSection> createState() => _TimesSectionState();
}

class _TimesSectionState extends State<TimesSection> {
  bool _airTimeExpanded = false;
  late final TextEditingController _blockController;

  String get _computedText =>
      widget.blockTime != null ? _formatDuration(widget.blockTime!) : '—:—';

  @override
  void initState() {
    super.initState();
    _blockController = TextEditingController(
      text: widget.blockOverrideText?.isNotEmpty == true
          ? widget.blockOverrideText
          : _computedText,
    );
  }

  @override
  void didUpdateWidget(TimesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final overridden = widget.blockOverrideText?.isNotEmpty == true;
    final shown = overridden ? widget.blockOverrideText! : _computedText;
    if (_blockController.text != shown && !overridden) {
      _blockController.text = shown;
    }
  }

  @override
  void dispose() {
    _blockController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ink = context.inkTiers;
    final theme = Theme.of(context);
    final overridden =
        widget.blockOverrideText?.isNotEmpty == true &&
        widget.blockOverrideText != _computedText;

    return EntrySection(
      label: 'Times',
      trailing: Text(
        'ALL TIMES ZULU',
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
                    label: widget.startLabel,
                    value: widget.offBlocks != null
                        ? '${_formatTimeOfDay(widget.offBlocks!)}Z'
                        : '--:--',
                    placeholder: widget.offBlocks == null,
                    onTap: widget.onTapOffBlocks,
                  ),
                ),
                Expanded(
                  child: EntryValueColumn(
                    label: widget.endLabel,
                    value: widget.onBlocks != null
                        ? '${_formatTimeOfDay(widget.onBlocks!)}Z'
                        : '--:--',
                    placeholder: widget.onBlocks == null,
                    onTap: widget.onTapOnBlocks,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.only(left: 12),
                  // Wide enough that a two-digit-hour block time ("15:19")
                  // never gets clipped by the single-line TextField's
                  // internal horizontal scroll — 74px cut the trailing
                  // digit off on a real device (only single-digit hours
                  // happened to fit in testing).
                  width: 96,
                  decoration: BoxDecoration(
                    border: Border(
                      left: BorderSide(
                        color: Theme.of(context).colorScheme.outlineVariant,
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'BLOCK',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: ink.faint,
                        ),
                      ),
                      const SizedBox(height: 2),
                      TextField(
                        controller: _blockController,
                        onChanged: widget.onBlockOverrideChanged,
                        style: TextStyle(
                          fontFamily: 'IBM Plex Mono',
                          fontWeight: FontWeight.w600,
                          fontSize: 19,
                          color: overridden
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurface,
                        ),
                        decoration: const InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.zero,
                        ),
                      ),
                      Text(
                        overridden ? 'override · $_computedText' : 'computed',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 10,
                          color: overridden
                              ? context.semanticColors.currencyWarning
                              : ink.faint,
                        ),
                      ),
                    ],
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
                    Expanded(
                      child: Text(
                        'optional · not logged as total',
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: ink.faint,
                        ),
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
                            ? '${_formatTimeOfDay(widget.takeoff!)}Z'
                            : '--:--',
                        placeholder: widget.takeoff == null,
                        onTap: widget.onTapTakeoff,
                      ),
                    ),
                    Expanded(
                      child: EntryValueColumn(
                        label: 'Landing',
                        value: widget.landing != null
                            ? '${_formatTimeOfDay(widget.landing!)}Z'
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
