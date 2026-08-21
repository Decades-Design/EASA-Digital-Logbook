import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';

/// A compact hours/minutes entry, for durations that are typed directly
/// rather than derived — manipulation time (§4B, §4C), and the
/// instrument-time fields in §6. Borderless, matching [EntryValueColumn]'s
/// label-over-value shape, so it reads as part of the surrounding card
/// rather than a boxed field of its own.
class DurationField extends StatelessWidget {
  const DurationField({
    super.key,
    required this.label,
    required this.hoursController,
    required this.minutesController,
    this.blockTimeText,
    this.onFillFromBlock,
  });

  final String label;
  final TextEditingController hoursController;
  final TextEditingController minutesController;

  /// The current block time, formatted as `H:MM` (e.g. `2:15`) — shown in
  /// the fill button's tooltip so the pilot can see what one tap will
  /// enter without having to scroll up to the Times section first.
  final String? blockTimeText;

  /// Fills [hoursController]/[minutesController] with the flight's block
  /// time in one tap. Null hides the button — either the caller doesn't
  /// offer the shortcut for this field (manipulation time is, by
  /// definition, usually *less* than the whole flight), or block time
  /// isn't known yet.
  final VoidCallback? onFillFromBlock;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;

    Widget box(TextEditingController controller, String hint, int maxLen) {
      return IntrinsicWidth(
        child: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(maxLen),
          ],
          style: const TextStyle(
            fontFamily: 'IBM Plex Mono',
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
          decoration: InputDecoration(
            isDense: true,
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            contentPadding: EdgeInsets.zero,
            hintText: hint,
          ),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(color: ink.faint),
        ),
        const SizedBox(height: 2),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            box(hoursController, '0', 2),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Text(
                'h',
                style: theme.textTheme.bodyMedium?.copyWith(color: ink.faint),
              ),
            ),
            box(minutesController, '00', 2),
            Padding(
              padding: const EdgeInsets.only(left: 3),
              child: Text(
                'm',
                style: theme.textTheme.bodyMedium?.copyWith(color: ink.faint),
              ),
            ),
            if (onFillFromBlock != null) ...[
              const SizedBox(width: 4),
              Tooltip(
                message: blockTimeText != null
                    ? 'Fill with block time ($blockTimeText)'
                    : 'Fill with block time',
                child: InkWell(
                  onTap: onFillFromBlock,
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: theme.colorScheme.primary.withValues(alpha: 0.4),
                      ),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'BLOCK',
                      style: TextStyle(
                        fontFamily: 'IBM Plex Mono',
                        fontWeight: FontWeight.w600,
                        fontSize: 9.5,
                        letterSpacing: 0.4,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
