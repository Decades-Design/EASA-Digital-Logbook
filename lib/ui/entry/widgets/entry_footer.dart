import 'package:flutter/material.dart';

import '../../../domain/projection/derived_quantity.dart';
import '../../../domain/projection/projection_result.dart';
import '../../theme/app_typography.dart';

/// Named-quantity display order + labels per jurisdiction — presentation
/// concerns only (which of a [ProjectionResult]'s named quantities are
/// worth a pilot's attention, and what to call them), never a
/// re-derivation of what value they hold. The values themselves always
/// come from `JurisdictionProjection` via `flight_draft_mapper.dart`.
const Map<String, String> _easaLabels = {
  'pic': 'PIC',
  'dual': 'Dual',
  'spic': 'SPIC',
  'picus': 'PICUS',
  'copilot': 'Co-pilot',
  'instructor': 'Instructor',
  // easa_instrument_time.dart's whole-block-or-nothing 'ifr' quantity —
  // the only visible effect of §6's "IFR flight plan filed" toggle, so
  // without this row the toggle looks like it does nothing.
  'ifr': 'IFR',
};

const Map<String, String> _faaLabels = {
  'actingPic': 'Acting PIC',
  'loggedPic': 'PIC',
  'dualReceived': 'Dual',
  'sic': 'SIC',
  'solo': 'Solo',
  // faa_instrument_time.dart carries §6's actual/simulated instrument
  // fields straight through — same reasoning as 'ifr' above.
  'actualInstrument': 'Actual instrument',
  'simulatedInstrument': 'Simulated instrument',
};

class _Line {
  const _Line(this.label, this.quantity);
  final String label;
  final DerivedQuantity quantity;
}

/// Fixed, theme-invariant accent colours for the two jurisdictions — the
/// footer card itself is always near-black regardless of the app's own
/// light/dark theme, so these are picked for contrast against that one
/// background rather than sourced from `context.semanticColors`, which
/// flips with the ambient theme. Blue for
/// EASA and ochre for FAA deliberately echo the app's own primary/secondary
/// ("night"/"day") accent pairing — CLAUDE.md: "today: EASA primary, FAA
/// secondary" — so the association reads the same way it does everywhere
/// else in the app, not a one-off pair invented for this card.
const Color _easaAccent = Color(0xFF80A3F0);
const Color _faaAccent = Color(0xFFE3B47D);

List<_Line> _nonZeroLines(
  ProjectionResult? result,
  Map<String, String> labels,
) {
  if (result == null) return const [];
  final lines = <_Line>[];
  for (final entry in labels.entries) {
    final q = result[entry.key];
    if (q == null) continue;
    if (q.value.inMinutes == 0 && q.creditable) continue;
    lines.add(_Line(entry.value, q));
  }
  return lines;
}

String _summary(List<_Line> lines) {
  if (lines.isEmpty) return 'no time logged';
  return lines
      .map(
        (l) => l.quantity.creditable
            ? '${l.label} ${l.quantity.value.toHoursMinutes()}'
            : '${l.label} ${l.quantity.value.toHoursMinutes()} (pending)',
      )
      .join(', ');
}

/// §7 + §3 of docs/entry-form.md: the derivation strip sits pinned above
/// the save controls, and "Save draft" is a peer of "Save", never a hidden
/// option. Tapping the strip expands the full per-jurisdiction breakdown,
/// each line traceable to the rule that produced it
/// ([DerivedQuantity.explanation]) — no "Override" affordance yet, since
/// §8's override-with-reason mechanism doesn't exist in this codebase yet;
/// rendering a button that doesn't do anything would be worse than not
/// having one.
class EntryFooter extends StatefulWidget {
  const EntryFooter({
    super.key,
    required this.blockTimeText,
    required this.easaResult,
    required this.faaResult,
    required this.hasFaaLicence,
    required this.onSaveDraft,
    required this.onSave,
  });

  final String blockTimeText;
  final ProjectionResult? easaResult;
  final ProjectionResult? faaResult;
  final bool hasFaaLicence;
  final VoidCallback onSaveDraft;
  final VoidCallback onSave;

  @override
  State<EntryFooter> createState() => _EntryFooterState();
}

class _EntryFooterState extends State<EntryFooter> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF25272C) : const Color(0xFF14161A);
    const onCard = Colors.white;
    final onCardMuted = Colors.white.withValues(alpha: 0.55);

    final easaLines = _nonZeroLines(widget.easaResult, _easaLabels);
    final faaLines = _nonZeroLines(widget.faaResult, _faaLabels);
    final hasBreakdown = widget.easaResult != null;

    // A coarse divergence signal, not a re-derivation: does either side
    // claim command-grade PIC time (creditable and non-zero) while the
    // other side doesn't? That's the case docs/entry-form.md §7 exists to
    // surface before saving, not after.
    final easaPic = widget.easaResult?['pic'];
    final faaLoggedPic = widget.faaResult?['loggedPic'];
    final mismatch =
        widget.hasFaaLicence &&
        easaPic != null &&
        faaLoggedPic != null &&
        (easaPic.creditable && easaPic.value.inMinutes > 0) !=
            (faaLoggedPic.creditable && faaLoggedPic.value.inMinutes > 0);

    return DecoratedBox(
      decoration: BoxDecoration(color: theme.scaffoldBackgroundColor),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InkWell(
                onTap: hasBreakdown
                    ? () => setState(() => _expanded = !_expanded)
                    : null,
                borderRadius: BorderRadius.circular(12),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'THIS ENTRY PRODUCES',
                            style: TextStyle(
                              fontFamily: 'IBM Plex Mono',
                              fontSize: 9,
                              letterSpacing: 1.1,
                              color: onCardMuted,
                            ),
                          ),
                          const Spacer(),
                          if (mismatch) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0x33E3B47D),
                                border: Border.all(
                                  color: const Color(0x88E3B47D),
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: const Text(
                                '⇄ MISMATCH',
                                style: TextStyle(
                                  fontFamily: 'IBM Plex Mono',
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: 0.5,
                                  color: Color(0xFFE3B47D),
                                ),
                              ),
                            ),
                          ],
                          if (hasBreakdown) ...[
                            const SizedBox(width: 6),
                            AnimatedRotation(
                              turns: _expanded ? 0.5 : 0,
                              duration: const Duration(milliseconds: 150),
                              child: Icon(
                                Icons.expand_more,
                                size: 16,
                                color: onCardMuted,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: widget.blockTimeText,
                              style: AppMonoText.value(
                                onCard,
                                size: 13,
                                weight: FontWeight.w500,
                              ),
                            ),
                            // Expanded, the breakdown below already shows
                            // every quantity — repeating the same summary
                            // inline here is redundant, so it's replaced
                            // with a bare "block" until collapsed again.
                            if (!hasBreakdown)
                              TextSpan(
                                text:
                                    ' block · jurisdiction breakdown '
                                    'appears once crew is entered',
                                style: AppMonoText.value(
                                  onCardMuted,
                                  size: 13,
                                  weight: FontWeight.w400,
                                ),
                              )
                            else if (_expanded)
                              TextSpan(
                                text: ' block',
                                style: AppMonoText.value(
                                  onCardMuted,
                                  size: 13,
                                  weight: FontWeight.w400,
                                ),
                              )
                            else ...[
                              TextSpan(
                                text: ' block · ',
                                style: AppMonoText.value(
                                  onCardMuted,
                                  size: 13,
                                  weight: FontWeight.w400,
                                ),
                              ),
                              TextSpan(
                                text: 'EASA: ',
                                style: AppMonoText.value(
                                  _easaAccent,
                                  size: 13,
                                  weight: FontWeight.w600,
                                ),
                              ),
                              TextSpan(
                                text: _summary(easaLines),
                                style: AppMonoText.value(
                                  onCardMuted,
                                  size: 13,
                                  weight: FontWeight.w400,
                                ),
                              ),
                              if (widget.hasFaaLicence) ...[
                                TextSpan(
                                  text: ' · ',
                                  style: AppMonoText.value(
                                    onCardMuted,
                                    size: 13,
                                    weight: FontWeight.w400,
                                  ),
                                ),
                                TextSpan(
                                  text: 'FAA: ',
                                  style: AppMonoText.value(
                                    _faaAccent,
                                    size: 13,
                                    weight: FontWeight.w600,
                                  ),
                                ),
                                TextSpan(
                                  text: _summary(faaLines),
                                  style: AppMonoText.value(
                                    onCardMuted,
                                    size: 13,
                                    weight: FontWeight.w400,
                                  ),
                                ),
                              ],
                            ],
                          ],
                        ),
                      ),
                      if (_expanded && hasBreakdown) ...[
                        const SizedBox(height: 10),
                        _JurisdictionGroup(
                          label: 'EASA',
                          accent: _easaAccent,
                          lines: easaLines,
                          onCard: onCard,
                          onCardMuted: onCardMuted,
                        ),
                        if (widget.hasFaaLicence) ...[
                          const SizedBox(height: 10),
                          _JurisdictionGroup(
                            label: 'FAA',
                            accent: _faaAccent,
                            lines: faaLines,
                            onCard: onCard,
                            onCardMuted: onCardMuted,
                          ),
                        ],
                      ],
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: widget.onSaveDraft,
                    child: const Text('Draft'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: widget.onSave,
                      child: const Text('Save flight'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One jurisdiction's slice of the expanded breakdown — a coloured label
/// plus a left accent bar running the height of its rows, so EASA and FAA
/// read as two visually distinct groups instead of one undifferentiated
/// list (they used to share a single divider and no colour at all).
class _JurisdictionGroup extends StatelessWidget {
  const _JurisdictionGroup({
    required this.label,
    required this.accent,
    required this.lines,
    required this.onCard,
    required this.onCardMuted,
  });

  final String label;
  final Color accent;
  final List<_Line> lines;
  final Color onCard;
  final Color onCardMuted;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 3,
          margin: const EdgeInsets.only(top: 3),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'IBM Plex Mono',
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                  color: accent,
                ),
              ),
              if (lines.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'No time logged',
                    style: TextStyle(
                      fontFamily: 'Instrument Sans',
                      fontSize: 11.5,
                      color: onCardMuted,
                    ),
                  ),
                )
              else
                for (final line in lines)
                  _BreakdownRow(
                    line: line,
                    onCard: onCard,
                    onCardMuted: onCardMuted,
                  ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BreakdownRow extends StatelessWidget {
  const _BreakdownRow({
    required this.line,
    required this.onCard,
    required this.onCardMuted,
  });

  final _Line line;
  final Color onCard;
  final Color onCardMuted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  line.label,
                  style: TextStyle(
                    fontFamily: 'Instrument Sans',
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                    color: line.quantity.creditable
                        ? onCard
                        : const Color(0xFFE3B47D),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  line.quantity.explanation,
                  style: TextStyle(
                    fontFamily: 'Instrument Sans',
                    fontSize: 10.5,
                    height: 1.4,
                    color: onCardMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            line.quantity.value.toHoursMinutes(),
            style: AppMonoText.value(onCard, size: 14, weight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
