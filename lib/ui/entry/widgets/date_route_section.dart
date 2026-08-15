import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'entry_card.dart';
import 'entry_section_label.dart';

/// §1.2 of docs/entry-form.md. Route is the full stop-by-stop list, never
/// collapsed to a single "is cross-country" figure — see CLAUDE.md rule 2.
/// Legs beyond the first (departure) and last (destination) are optional
/// intermediate stops and can be removed; departure/destination cannot.
class DateRouteSection extends StatelessWidget {
  const DateRouteSection({
    super.key,
    required this.date,
    required this.onTapDate,
    required this.legControllers,
    required this.onAddStop,
    required this.onRemoveStop,
  });

  final DateTime date;
  final VoidCallback onTapDate;
  final List<TextEditingController> legControllers;
  final VoidCallback onAddStop;
  final ValueChanged<int> onRemoveStop;

  static const _months = [
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;

    return EntrySection(
      label: 'Date & route',
      child: EntryCard(
        child: Column(
          children: [
            EntryCardRow(
              label: 'Date',
              onTap: onTapDate,
              child: Text(
                '${date.day} ${_months[date.month - 1]} ${date.year}',
                style: theme.textTheme.titleMedium,
              ),
            ),
            const EntryCardDivider(),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                children: [
                  Text(
                    'Route',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: ink.medium,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Wrap(
                      alignment: WrapAlignment.end,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      spacing: 2,
                      runSpacing: 6,
                      children: [
                        for (var i = 0; i < legControllers.length; i++) ...[
                          if (i > 0)
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                              ),
                              child: Icon(
                                Icons.arrow_forward,
                                size: 14,
                                color: ink.faint,
                              ),
                            ),
                          _LegField(
                            controller: legControllers[i],
                            removable: i != 0 && i != legControllers.length - 1,
                            onRemove: () => onRemoveStop(i),
                          ),
                        ],
                        const SizedBox(width: 2),
                        InkWell(
                          onTap: onAddStop,
                          borderRadius: BorderRadius.circular(20),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.add_circle_outline,
                              size: 18,
                              color: ink.muted,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LegField extends StatelessWidget {
  const _LegField({
    required this.controller,
    required this.removable,
    required this.onRemove,
  });

  final TextEditingController controller;
  final bool removable;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final ink = context.inkTiers;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IntrinsicWidth(
          child: TextField(
            controller: controller,
            textAlign: TextAlign.right,
            textCapitalization: TextCapitalization.characters,
            maxLength: 4,
            style: const TextStyle(
              fontFamily: 'IBM Plex Mono',
              fontWeight: FontWeight.w600,
              fontSize: 15,
              letterSpacing: 0.5,
            ),
            decoration: const InputDecoration(
              border: InputBorder.none,
              enabledBorder: InputBorder.none,
              focusedBorder: InputBorder.none,
              filled: false,
              counterText: '',
              isDense: true,
              contentPadding: EdgeInsets.zero,
              hintText: 'ICAO',
            ),
          ),
        ),
        if (removable)
          InkWell(
            onTap: onRemove,
            borderRadius: BorderRadius.circular(10),
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close, size: 12, color: ink.faint),
            ),
          ),
      ],
    );
  }
}
