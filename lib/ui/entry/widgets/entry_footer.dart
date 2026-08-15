import 'package:flutter/material.dart';

import '../../theme/app_typography.dart';

/// §7 + §3 of docs/entry-form.md: the derivation strip sits pinned above
/// the save controls, and "Save draft" is a peer of "Save", never a hidden
/// option — a flight can always be saved incomplete. Styled as the
/// mockups' "THIS ENTRY PRODUCES" card: a dark surface distinct from the
/// page, not another bordered box in the same style as the form above it.
///
/// The card only shows block time for now; the per-jurisdiction breakdown
/// ("EASA: Dual 1:30 · FAA: PIC 1:30") needs the projection engine wired
/// in, which this screen doesn't have yet.
class EntryFooter extends StatelessWidget {
  const EntryFooter({
    super.key,
    required this.blockTime,
    required this.onSaveDraft,
    required this.onSave,
  });

  final Duration? blockTime;
  final VoidCallback onSaveDraft;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF25272C) : const Color(0xFF14161A);
    const onCard = Colors.white;
    final onCardMuted = Colors.white.withValues(alpha: 0.55);

    return DecoratedBox(
      decoration: BoxDecoration(color: theme.scaffoldBackgroundColor),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
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
                    Text(
                      'THIS ENTRY PRODUCES',
                      style: TextStyle(
                        fontFamily: 'IBM Plex Mono',
                        fontSize: 9,
                        letterSpacing: 1.1,
                        color: onCardMuted,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text.rich(
                      TextSpan(
                        children: [
                          TextSpan(
                            text: blockTime != null
                                ? _formatDuration(blockTime!)
                                : '—:—',
                            style: AppMonoText.value(
                              onCard,
                              size: 13,
                              weight: FontWeight.w500,
                            ),
                          ),
                          TextSpan(
                            text:
                                ' block · jurisdiction breakdown appears once crew is entered',
                            style: AppMonoText.value(
                              onCardMuted,
                              size: 13,
                              weight: FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  OutlinedButton(
                    onPressed: onSaveDraft,
                    child: const Text('Draft'),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: onSave,
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

String _formatDuration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60).abs();
  return '$hours:${minutes.toString().padLeft(2, '0')}';
}
