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
    required this.legFocusNodes,
    required this.onAddStop,
    required this.onRemoveStop,
  });

  final DateTime date;
  final VoidCallback onTapDate;
  final List<TextEditingController> legControllers;

  /// Parallel to [legControllers], owned and disposed alongside it by the
  /// parent screen. Lets each `_LegField` hand focus to the *next* leg once
  /// its four ICAO characters are typed, instead of leaving the pilot to
  /// tap across every field by hand.
  final List<FocusNode> legFocusNodes;
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
                            focusNode: legFocusNodes[i],
                            nextFocusNode: i + 1 < legFocusNodes.length
                                ? legFocusNodes[i + 1]
                                : null,
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
    required this.focusNode,
    required this.nextFocusNode,
    required this.removable,
    required this.onRemove,
  });

  final TextEditingController controller;
  final FocusNode focusNode;

  /// Null for the last leg — nothing to advance to.
  final FocusNode? nextFocusNode;
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
            focusNode: focusNode,
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
            // A 4-character ICAO code is always complete at 4 characters —
            // advancing there, rather than waiting for the pilot to tap the
            // next field by hand, is the whole point of a fixed-length
            // identifier (docs/entry-form.md never expects a 3-character
            // code to be topped up later).
            onChanged: (value) {
              if (value.length >= 4 && nextFocusNode != null) {
                FocusScope.of(context).requestFocus(nextFocusNode);
              }
            },
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
