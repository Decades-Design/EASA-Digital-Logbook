import 'package:flutter/material.dart';

import '../../theme/app_colors.dart';
import 'counter_stepper.dart';
import 'entry_card.dart';
import 'entry_section_label.dart';

/// §5 of docs/entry-form.md: take-offs and landings are four independent
/// counts (day/night × take-off/landing), never one derived from another —
/// a pilot who took over in flight has zero take-offs and one landing.
/// Values start at zero for a new entry; the docs' "pre-filled from the
/// twilight computation" behaviour needs a route/time-driven twilight
/// engine this screen doesn't have yet, so for now the pilot enters them
/// directly — still immediately editable with no confirmation gate, which
/// is the requirement that actually matters here.
class CountersSection extends StatelessWidget {
  const CountersSection({
    super.key,
    required this.takeoffsDay,
    required this.takeoffsNight,
    required this.landingsDay,
    required this.landingsNight,
    required this.onChangeTakeoffsDay,
    required this.onChangeTakeoffsNight,
    required this.onChangeLandingsDay,
    required this.onChangeLandingsNight,
    required this.showFullStop,
    required this.fullStop,
    required this.onChangeFullStop,
  });

  final int takeoffsDay;
  final int takeoffsNight;
  final int landingsDay;
  final int landingsNight;
  final ValueChanged<int> onChangeTakeoffsDay;
  final ValueChanged<int> onChangeTakeoffsNight;
  final ValueChanged<int> onChangeLandingsDay;
  final ValueChanged<int> onChangeLandingsNight;

  /// FAA night currency (§61.57(b)) requires full-stop landings
  /// specifically — shown when an FAA licence is held and night landings
  /// are greater than zero.
  final bool showFullStop;
  final int fullStop;
  final ValueChanged<int> onChangeFullStop;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;

    return EntrySection(
      label: 'Your take-offs and landings',
      child: EntryCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(flex: 3, child: SizedBox()),
                Expanded(
                  flex: 5,
                  child: Text(
                    'DAY',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: ink.faint,
                    ),
                  ),
                ),
                Expanded(
                  flex: 5,
                  child: Text(
                    'NIGHT',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: ink.faint,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _CounterRow(
              label: 'Take-offs',
              dayValue: takeoffsDay,
              nightValue: takeoffsNight,
              onDayChanged: onChangeTakeoffsDay,
              onNightChanged: onChangeTakeoffsNight,
            ),
            const SizedBox(height: 8),
            _CounterRow(
              label: 'Landings',
              dayValue: landingsDay,
              nightValue: landingsNight,
              onDayChanged: onChangeLandingsDay,
              onNightChanged: onChangeLandingsNight,
            ),
            if (showFullStop) ...[
              const SizedBox(height: 10),
              const EntryCardDivider(),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          const TextSpan(text: 'of which full-stop '),
                          TextSpan(
                            text: 'FAA night',
                            style: TextStyle(color: ink.faint),
                          ),
                        ],
                      ),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: ink.medium,
                      ),
                    ),
                  ),
                  CounterStepper(
                    width: 128,
                    value: fullStop,
                    onIncrement: () => onChangeFullStop(fullStop + 1),
                    onDecrement: fullStop > 0
                        ? () => onChangeFullStop(fullStop - 1)
                        : null,
                  ),
                ],
              ),
            ],
            const SizedBox(height: 9),
            Text(
              'Counted as landings you flew, not landings the aircraft '
              'made.',
              style: theme.textTheme.bodySmall?.copyWith(color: ink.faint),
            ),
          ],
        ),
      ),
    );
  }
}

class _CounterRow extends StatelessWidget {
  const _CounterRow({
    required this.label,
    required this.dayValue,
    required this.nightValue,
    required this.onDayChanged,
    required this.onNightChanged,
  });

  final String label;
  final int dayValue;
  final int nightValue;
  final ValueChanged<int> onDayChanged;
  final ValueChanged<int> onNightChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Text(label, style: theme.textTheme.bodyMedium),
        ),
        Expanded(
          flex: 5,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: CounterStepper(
              value: dayValue,
              onIncrement: () => onDayChanged(dayValue + 1),
              onDecrement: dayValue > 0
                  ? () => onDayChanged(dayValue - 1)
                  : null,
            ),
          ),
        ),
        Expanded(
          flex: 5,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: CounterStepper(
              value: nightValue,
              onIncrement: () => onNightChanged(nightValue + 1),
              onDecrement: nightValue > 0
                  ? () => onNightChanged(nightValue - 1)
                  : null,
            ),
          ),
        ),
      ],
    );
  }
}
