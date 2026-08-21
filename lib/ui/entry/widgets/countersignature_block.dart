import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../entry_form_types.dart';
import 'entry_segmented_choice.dart';

/// Always present when shown, never required to save (docs/entry-form.md
/// §4B/§4C, §8). Covers both the §4B instructor-received/SPIC case and the
/// §4C PICUS case — `NewFlightScreen` decides when to show it
/// (`crew == instructor || (crew == otherPilot && picus)`) and which name
/// to sign against; this widget only renders the sign-now/defer choice and
/// the resulting state.
///
/// Uncountersigned SPIC/PICUS time is not creditable — see
/// `flight_draft_mapper.dart`'s `_countersignature`, which returns
/// [CountersignatureStatus.pending] rather than silently treating a
/// deferred signature as valid.
class CountersignatureBlock extends StatelessWidget {
  const CountersignatureBlock({
    super.key,
    required this.sign,
    required this.onSignChanged,
    required this.signedAt,
    required this.signatoryName,
  });

  final SignChoice sign;
  final ValueChanged<SignChoice> onSignChanged;
  final DateTime? signedAt;

  /// The name that will appear against the signature — the instructor's or
  /// the other pilot's, whichever path triggered this block.
  final String signatoryName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
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
                child: Text(
                  'Countersignature',
                  style: theme.textTheme.titleSmall,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'never required to save',
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(color: ink.faint),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          EntrySegmentedChoice<SignChoice>(
            options: [for (final s in SignChoice.values) (s, s.label)],
            selected: sign,
            onChanged: onSignChanged,
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Text('Signed at', style: theme.textTheme.bodySmall),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  sign == SignChoice.now && signedAt != null
                      ? _formatSignedAt(signedAt!)
                      : 'not signed',
                  textAlign: TextAlign.right,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'IBM Plex Mono',
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                    color: sign == SignChoice.now ? null : ink.faint,
                  ),
                ),
              ),
            ],
          ),
          if (sign == SignChoice.defer) ...[
            const SizedBox(height: 10),
            Text(
              'Queued under "awaiting countersignature". Uncountersigned '
              'SPIC or PICUS time projects as not creditable, with reason — '
              'never silently as zero.',
              style: theme.textTheme.bodySmall?.copyWith(color: ink.muted),
            ),
          ],
        ],
      ),
    );
  }
}

String _formatSignedAt(DateTime t) {
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final hh = t.hour.toString().padLeft(2, '0');
  final mm = t.minute.toString().padLeft(2, '0');
  return '${t.day} ${months[t.month - 1]} ${t.year} $hh:${mm}Z';
}
