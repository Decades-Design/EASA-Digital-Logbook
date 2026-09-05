import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../domain/model/aircraft.dart';
import '../../../domain/model/calendar_date.dart';
import '../../../domain/model/utc_instant.dart';
import '../../../domain/pilot_record/qualification_gap.dart';
import '../../aircraft/aircraft_qualification_display.dart';
import '../../providers/pilot_profile_providers.dart';
import '../../theme/app_colors.dart';

/// #58/#105: a non-blocking warning when [aircraft] requires a
/// qualification the pilot has no record of holding under *any* held
/// licence. `qualificationGaps` is scoped to one jurisdiction at a time —
/// per its own dartdoc, the caller must run it once per held licence and
/// never against the primary jurisdiction alone. §8's night-rating example
/// is the reason: a pilot cleared under one held licence but not another
/// is still legal, so this only fires when every held jurisdiction shows a
/// gap. Never blocks the save — the pilot may be flying under a different
/// licence, a permit aircraft, or an exemption the app doesn't model.
class QualificationGapBanner extends ConsumerWidget {
  const QualificationGapBanner({super.key, required this.aircraft});

  final Aircraft? aircraft;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aircraft = this.aircraft;
    if (aircraft == null) return const SizedBox.shrink();

    final ratingsAsync = ref.watch(heldRatingsProvider);
    final qualificationsAsync = ref.watch(heldAircraftQualificationsProvider);
    if (ratingsAsync.isLoading ||
        ratingsAsync.hasError ||
        qualificationsAsync.isLoading ||
        qualificationsAsync.hasError) {
      return const SizedBox.shrink();
    }
    final heldRatings = ratingsAsync.requireValue;
    final heldQualifications = qualificationsAsync.requireValue;

    final heldJurisdictionIds = {for (final r in heldRatings) r.jurisdictionId};
    if (heldJurisdictionIds.isEmpty) return const SizedBox.shrink();

    final today = CalendarDate.fromUtcInstant(
      UtcInstant.fromDateTime(DateTime.now().toUtc()),
    );

    final gapsByJurisdiction = <String, List<QualificationGap>>{};
    for (final jurisdictionId in heldJurisdictionIds) {
      final gaps = qualificationGaps(
        aircraft: aircraft,
        jurisdictionId: jurisdictionId,
        heldAircraftQualifications: heldQualifications,
        heldRatings: heldRatings,
        asOf: today,
      );
      // Cleared under this licence — the pilot can legally fly it on this
      // ticket regardless of what any other held licence requires.
      if (gaps.isEmpty) return const SizedBox.shrink();
      gapsByJurisdiction[jurisdictionId] = gaps;
    }

    final theme = Theme.of(context);
    final semantic = context.semanticColors;
    final lines = [
      for (final entry in gapsByJurisdiction.entries)
        '${qualificationJurisdictionLabels[entry.key] ?? entry.key}: '
            '${entry.value.map(_gapLabel).join(', ')}',
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: semantic.currencyWarningSurface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          'This aircraft needs a qualification you have no record of '
          'holding — ${lines.join('; ')}. Logging it anyway is fine if '
          "you're flying under a different licence, a permit, or an "
          'exemption this app doesn\'t model.',
          style: theme.textTheme.bodySmall?.copyWith(
            color: semantic.currencyWarning,
          ),
        ),
      ),
    );
  }

  String _gapLabel(QualificationGap gap) => switch (gap.kind) {
    QualificationGapKind.aircraftQualification =>
      qualificationInfo[gap.aircraftQualification]!.label,
    QualificationGapKind.typeRating =>
      '${gap.typeRatingDesignator} type rating',
  };
}
