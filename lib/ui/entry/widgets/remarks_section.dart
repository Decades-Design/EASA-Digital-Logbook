import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../entry_form_types.dart';
import 'countersignature_block.dart';
import 'entry_card.dart';
import 'entry_section_label.dart';

/// §4B/§4C + §7 of docs/entry-form.md: the remarks textarea (AMC1 FCL.050
/// column 12), the mandatory-remarks nudge some purposes-of-flight force,
/// and the countersignature block — shown whenever the flight needs one
/// (receiving instruction, SPIC, or a claimed PICUS), never gated on
/// whether the entry is a draft.
class RemarksSection extends StatelessWidget {
  const RemarksSection({
    super.key,
    required this.controller,
    required this.remarksRequiredNote,
    required this.showCountersignature,
    required this.sign,
    required this.onSignChanged,
    required this.signedAt,
    required this.signatoryName,
  });

  final TextEditingController controller;

  /// Non-empty when the selected purpose of flight requires a remarks entry
  /// and none has been given yet — `null`/empty otherwise.
  final String? remarksRequiredNote;

  final bool showCountersignature;
  final SignChoice sign;
  final ValueChanged<SignChoice> onSignChanged;
  final DateTime? signedAt;
  final String signatoryName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;
    final needsRemarks = (remarksRequiredNote ?? '').isNotEmpty;

    return EntrySection(
      label: 'Remarks and endorsements',
      child: EntryCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: controller,
              maxLines: 3,
              decoration: InputDecoration(
                isDense: true,
                hintText: needsRemarks
                    ? 'Required for this purpose of flight'
                    : 'Optional — column 12 is yours',
                enabledBorder: needsRemarks && controller.text.isEmpty
                    ? OutlineInputBorder(
                        borderRadius: BorderRadius.circular(9),
                        borderSide: BorderSide(
                          color: context.semanticColors.currencyWarning
                              .withValues(alpha: 0.6),
                        ),
                      )
                    : null,
              ),
            ),
            if (needsRemarks && controller.text.isEmpty) ...[
              const SizedBox(height: 6),
              Text(
                remarksRequiredNote!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: context.semanticColors.currencyWarning,
                ),
              ),
            ],
            if (showCountersignature) ...[
              const SizedBox(height: 13),
              CountersignatureBlock(
                sign: sign,
                onSignChanged: onSignChanged,
                signedAt: signedAt,
                signatoryName: signatoryName,
              ),
            ],
            const SizedBox(height: 10),
            Text(
              'Validation annotates fields on blur and never blocks the '
              'save. A flight can always be saved incomplete.',
              style: theme.textTheme.bodySmall?.copyWith(color: ink.faint),
            ),
          ],
        ),
      ),
    );
  }
}
