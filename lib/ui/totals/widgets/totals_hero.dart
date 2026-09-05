import 'package:flutter/material.dart';

import '../../../domain/model/flight_duration.dart';
import '../../../domain/totals/totals_summary.dart';
import '../../theme/app_typography.dart';
import '../../widgets/jurisdiction_dropdown.dart';

/// The hero's own fixed dark surface — the same oklch(0.245 0.02 265)
/// swatch `app_colors.dart`'s light-mode ink (`_Palette.inkLight`) is
/// sampled from, reused here as a background rather than text. Fixed
/// regardless of the app's own theme brightness, the same way the NIGHT
/// badge is: frame 3b's hero card is always dark.
const _heroBg = Color(0xFF1C202A);
const _heroMuted = Color(0xFFB9BEC7);
const _heroTrack = Color(0x1FFFFFFF);
const _heroDivider = Color(0x29FFFFFF);
const _heroBarPast = Color(0x42FFFFFF);
const _heroBarCurrent = Color(0xFF6F9BF0);

const _granularities = [Granularity.year, Granularity.month, Granularity.week];
const _granularityLabels = ['Year', 'Month', 'Week'];

/// Frame 3b's collapsing dark hero — title, Map/Export actions, the
/// jurisdiction dropdown (CLAUDE.md: a jurisdiction-dependent figure never
/// renders without it), the headline total, the Year/Month/Week switch and
/// its bar chart. [expanded] drives the chart between its full form (bars,
/// value labels, axis labels, the switch) and a bare sparkline — the
/// scroll-linked collapse lives in `TotalsScreen`, which flips [expanded]
/// and calls [onToggleExpanded] when the chart itself is tapped, mirroring
/// the mockup's `toggleHero`/`onHeroScroll` pair.
///
/// Day is deliberately absent from the granularity switch — the design
/// brief for 3a/3b/3c all drop it in favour of Year/Month/Week only.
class TotalsHero extends StatelessWidget {
  const TotalsHero({
    super.key,
    required this.expanded,
    required this.onToggleExpanded,
    required this.granularity,
    required this.onGranularityChanged,
    required this.buckets,
    required this.totalTime,
    required this.flightCount,
    required this.selectedJurisdictionId,
    required this.jurisdictionOptions,
    required this.onJurisdictionChanged,
    required this.onOpenMap,
    required this.onExport,
  });

  final bool expanded;
  final VoidCallback onToggleExpanded;
  final Granularity granularity;
  final ValueChanged<Granularity> onGranularityChanged;
  final List<TimeBucket> buckets;
  final String totalTime;
  final int flightCount;
  final String selectedJurisdictionId;
  final Map<String, String> jurisdictionOptions;
  final ValueChanged<String> onJurisdictionChanged;
  final VoidCallback onOpenMap;
  final VoidCallback onExport;

  static const _duration = Duration(milliseconds: 320);
  static const _curve = Curves.fastOutSlowIn;

  @override
  Widget build(BuildContext context) {
    final shownTotal = FlightDuration.sum([for (final b in buckets) b.value]);
    return ColoredBox(
      color: _heroBg,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Totals',
                  style: TextStyle(
                    fontFamily: 'Instrument Sans',
                    fontSize: 25,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: -0.3,
                  ),
                ),
                Row(
                  children: [
                    _HeroPillButton(
                      label: 'Map',
                      filled: false,
                      onTap: onOpenMap,
                    ),
                    const SizedBox(width: 7),
                    _HeroPillButton(
                      label: 'Export',
                      filled: true,
                      onTap: onExport,
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 9),
            JurisdictionDropdown<String>(
              value: selectedJurisdictionId,
              label:
                  jurisdictionOptions[selectedJurisdictionId] ??
                  selectedJurisdictionId,
              options: jurisdictionOptions,
              onChanged: onJurisdictionChanged,
              dark: true,
            ),
            const SizedBox(height: 13),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'TOTAL TIME OF FLIGHT',
                      style: AppMonoText.tag(
                        _heroMuted,
                      ).copyWith(letterSpacing: 1.1),
                    ),
                    const SizedBox(height: 4),
                    AnimatedDefaultTextStyle(
                      duration: _duration,
                      curve: _curve,
                      style: AppMonoText.value(
                        Colors.white,
                        size: expanded ? 34 : 22,
                        weight: FontWeight.w700,
                      ),
                      child: Text(totalTime),
                    ),
                  ],
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '$flightCount',
                      style: AppMonoText.value(
                        Colors.white,
                        size: 15,
                        weight: FontWeight.w700,
                      ),
                    ),
                    const Text(
                      'FLIGHTS',
                      style: TextStyle(
                        fontFamily: 'Instrument Sans',
                        fontSize: 9,
                        letterSpacing: 0.5,
                        color: _heroMuted,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            AnimatedSize(
              duration: _duration,
              curve: _curve,
              alignment: Alignment.topCenter,
              child: expanded
                  ? Padding(
                      padding: const EdgeInsets.only(top: 13),
                      child: _GranularitySwitchDark(
                        selected: granularity,
                        onChanged: onGranularityChanged,
                        summary: '${shownTotal.toHoursMinutes()} shown',
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onToggleExpanded,
              child: Padding(
                padding: const EdgeInsets.only(top: 11),
                child: _HeroChart(buckets: buckets, expanded: expanded),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroPillButton extends StatelessWidget {
  const _HeroPillButton({
    required this.label,
    required this.filled,
    required this.onTap,
  });

  final String label;
  final bool filled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        height: 29,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: filled ? Colors.white : _heroTrack,
          borderRadius: BorderRadius.circular(15),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Instrument Sans',
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: filled ? _heroBg : Colors.white,
          ),
        ),
      ),
    );
  }
}

class _GranularitySwitchDark extends StatelessWidget {
  const _GranularitySwitchDark({
    required this.selected,
    required this.onChanged,
    required this.summary,
  });

  final Granularity selected;
  final ValueChanged<Granularity> onChanged;
  final String summary;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: _heroTrack,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [for (final g in _granularities) _segment(g)],
          ),
        ),
        Text(summary, style: AppMonoText.value(_heroMuted, size: 10)),
      ],
    );
  }

  Widget _segment(Granularity g) {
    final isSelected = g == selected;
    return InkWell(
      onTap: () => onChanged(g),
      borderRadius: BorderRadius.circular(5),
      child: Container(
        width: 58,
        height: 20,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: isSelected
              ? Colors.white.withValues(alpha: 0.9)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(5),
        ),
        child: Text(
          _granularityLabels[_granularities.indexOf(g)],
          style: TextStyle(
            fontFamily: 'Instrument Sans',
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            color: isSelected ? _heroBg : Colors.white,
          ),
        ),
      ),
    );
  }
}

/// The chart itself — bars sized relative to the largest bucket in view,
/// the current period picked out in a brighter fill, matching
/// `TotalsBarChart`'s own "past bars muted, current one solid" convention.
/// [expanded] drives it between the full chart (value labels above, axis
/// labels below) and a bare 20px sparkline.
class _HeroChart extends StatelessWidget {
  const _HeroChart({required this.buckets, required this.expanded});

  final List<TimeBucket> buckets;
  final bool expanded;

  static const _duration = Duration(milliseconds: 320);
  static const _curve = Curves.fastOutSlowIn;
  static const _expandedMax = 120.0;
  static const _collapsedMax = 20.0;

  @override
  Widget build(BuildContext context) {
    final maxMinutes = buckets
        .map((b) => b.value.inMinutes)
        .fold(0, (a, b) => a > b ? a : b);
    final barMax = expanded ? _expandedMax : _collapsedMax;

    Widget valueLabel(TimeBucket b) {
      final hours = b.value.inMinutes / 60;
      final text = hours == 0 ? '' : hours.round().toString();
      return Expanded(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: AppMonoText.value(Colors.white, size: 9.5),
        ),
      );
    }

    Widget axisLabel(TimeBucket b) => Expanded(
      child: Text(
        b.label,
        textAlign: TextAlign.center,
        style: AppMonoText.value(_heroMuted, size: 9.5),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AnimatedSize(
          duration: _duration,
          curve: _curve,
          alignment: Alignment.bottomCenter,
          child: expanded
              ? Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    children: [for (final b in buckets) valueLabel(b)],
                  ),
                )
              : const SizedBox(width: double.infinity),
        ),
        AnimatedContainer(
          duration: _duration,
          curve: _curve,
          height: barMax,
          alignment: Alignment.bottomCenter,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (final b in buckets)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 3),
                    child: AnimatedContainer(
                      duration: _duration,
                      curve: _curve,
                      height: maxMinutes == 0
                          ? 2
                          : (b.value.inMinutes / maxMinutes * barMax).clamp(
                              2.0,
                              barMax,
                            ),
                      decoration: BoxDecoration(
                        color: b.isCurrent ? _heroBarCurrent : _heroBarPast,
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(2),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        AnimatedSize(
          duration: _duration,
          curve: _curve,
          alignment: Alignment.topCenter,
          child: expanded
              ? Container(
                  margin: const EdgeInsets.only(top: 5),
                  padding: const EdgeInsets.only(top: 5),
                  decoration: const BoxDecoration(
                    border: Border(top: BorderSide(color: _heroDivider)),
                  ),
                  child: Row(children: [for (final b in buckets) axisLabel(b)]),
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    );
  }
}
