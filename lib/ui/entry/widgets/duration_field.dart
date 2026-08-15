import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../theme/app_colors.dart';

/// A compact hours/minutes entry, for durations that are typed directly
/// rather than derived — manipulation time (§4B, §4C), and later the
/// instrument-time fields in §6. Borderless, matching [EntryValueColumn]'s
/// label-over-value shape, so it reads as part of the surrounding card
/// rather than a boxed field of its own.
class DurationField extends StatelessWidget {
  const DurationField({
    super.key,
    required this.label,
    required this.hoursController,
    required this.minutesController,
  });

  final String label;
  final TextEditingController hoursController;
  final TextEditingController minutesController;

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
          ],
        ),
      ],
    );
  }
}
