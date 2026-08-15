import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import '../../theme/app_typography.dart';

/// A small muted label over a large bold mono value, with an optional
/// muted sub-caption underneath — the shape used for Off blocks/On
/// blocks/Block in Times, and reused for Take-off/Landing. No border, no
/// fill: several of these side by side read as one connected value strip
/// rather than a row of separate boxes.
class EntryValueColumn extends StatelessWidget {
  const EntryValueColumn({
    super.key,
    required this.label,
    required this.value,
    this.subValue,
    this.accent = false,
    this.onTap,
    this.placeholder = false,
  });

  final String label;
  final String value;
  final String? subValue;
  final bool accent;
  final VoidCallback? onTap;

  /// Dims [value] to signal "not entered yet" rather than a real reading.
  final bool placeholder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final ink = context.inkTiers;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(color: ink.faint),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppMonoText.value(
            placeholder
                ? ink.faint
                : (accent ? scheme.primary : scheme.onSurface),
            size: 22,
            weight: FontWeight.w600,
          ),
        ),
        if (subValue != null)
          Text(
            subValue!,
            style: AppMonoText.value(
              ink.faint,
              size: 10,
              weight: FontWeight.w400,
            ),
          ),
      ],
    );

    if (onTap == null) return content;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: content,
    );
  }
}
