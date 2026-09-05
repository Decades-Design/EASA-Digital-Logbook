import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/model/aircraft.dart';
import '../../domain/model/countersignature.dart';
import '../../domain/model/flight.dart';
import '../../domain/model/flight_times.dart';
import '../../domain/model/instructor_presence.dart';
import '../../domain/model/pilot_capacity.dart';
import '../../domain/model/utc_instant.dart';
import '../../domain/projection/command_time_divergence.dart';
import '../../domain/projection/jurisdiction_projection.dart';
import '../../domain/projection/projection_result.dart';
import '../../domain/repository/flight_read_repository.dart';
import '../entry/duplicate_flight_action.dart';
import '../entry/flight_edit_state_mapper.dart';
import '../entry/new_flight_screen.dart';
import '../jurisdiction_display.dart';
import '../providers/flight_records_providers.dart';
import '../providers/jurisdiction_projection_providers.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';
import '../widgets/detail_row.dart';
import 'revision_history_screen.dart';

/// #57's remaining gap: tapping a Logbook row opens raw facts and every
/// held jurisdiction's derived figures side by side (CLAUDE.md's
/// multi-jurisdiction UX rule — the flight-level counterpart to the
/// [FlightRowBadge.mismatch] badge the row itself already carries).
///
/// #59: the Edit action reopens [NewFlightScreen]'s wizard, pre-filled from
/// this flight — but only when `flight_edit_state_mapper.dart` can
/// actually represent its crew arrangement; otherwise this shows why not
/// rather than opening a screen that immediately bounces back.
///
/// #60: History opens the full revision chain — committed flights only,
/// never a draft ("drafts show no history section rather than an empty
/// one"), which is why the button lives behind `!isDraft` rather than
/// [RevisionHistoryScreen] itself deciding whether it has anything to show.
class FlightDetailScreen extends ConsumerWidget {
  const FlightDetailScreen({
    super.key,
    required this.record,
    required this.isDraft,
  });

  final FlightRecord record;
  final bool isDraft;

  void _handleEdit(BuildContext context, FlightRecord liveRecord) {
    final resolution = resolveEditFormState(
      liveRecord.flight,
      liveRecord.aircraft,
    );
    if (resolution is EditFormUnsupported) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(resolution.reason.message)));
      return;
    }
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) =>
            NewFlightScreen.edit(record: liveRecord, isDraft: isDraft),
      ),
    );
  }

  void _handleHistory(BuildContext context) {
    Navigator.of(context).push<void>(
      MaterialPageRoute(
        builder: (_) => RevisionHistoryScreen(flightId: record.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // `record` is a snapshot from whenever this screen was navigated to —
    // this screen stays open across an edit made *from* it (Edit pushes
    // NewFlightScreen on top, then pops back here on save), so it needs
    // its own live look-up by id rather than displaying that now-stale
    // snapshot until the pilot backs out to Logbook and reopens it.
    final liveRecord = ref.watch(flightRecordByIdProvider(record.id)) ?? record;
    final flight = liveRecord.flight;
    final projectionsAsync = ref.watch(jurisdictionProjectionsProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TopBar(
              isDraft: isDraft,
              onEdit: () => _handleEdit(context, liveRecord),
              onHistory: isDraft ? null : () => _handleHistory(context),
              onDuplicate: () => showDuplicateFlightMenu(context, liveRecord),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.only(bottom: 32),
                children: [
                  _Hero(record: liveRecord, isDraft: isDraft),
                  _TimesSection(flight: flight),
                  const SizedBox(height: 1),
                  _CrewCapacitySection(capacity: flight.capacity),
                  const SizedBox(height: 1),
                  _CircuitsSection(flight: flight),
                  const SizedBox(height: 1),
                  _InstrumentNavigationSection(flight: flight),
                  const SizedBox(height: 1),
                  _RemarksSection(remarks: flight.remarks),
                  const SizedBox(height: 1),
                  projectionsAsync.when(
                    loading: () => const Padding(
                      padding: EdgeInsets.all(20),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                    error: (error, stackTrace) => const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text('Derived figures could not be loaded.'),
                    ),
                    data: (projections) => _DerivedSection(
                      flight: flight,
                      aircraft: liveRecord.aircraft,
                      projections: projections,
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

class _TopBar extends StatelessWidget {
  const _TopBar({
    required this.isDraft,
    required this.onEdit,
    required this.onHistory,
    required this.onDuplicate,
  });

  final bool isDraft;
  final VoidCallback onEdit;

  /// Null for a draft — see the class dartdoc on why History is hidden
  /// rather than shown disabled.
  final VoidCallback? onHistory;
  final VoidCallback onDuplicate;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final semantic = context.semanticColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back),
            tooltip: 'Back',
            onPressed: () => Navigator.of(context).pop(),
          ),
          Expanded(
            child: Text('Flight detail', style: theme.textTheme.titleMedium),
          ),
          if (isDraft) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: semantic.currencyWarningSurface,
                borderRadius: BorderRadius.circular(5),
              ),
              child: Text(
                'DRAFT',
                style: AppMonoText.tag(
                  semantic.currencyWarning,
                ).copyWith(letterSpacing: 0.7),
              ),
            ),
            const SizedBox(width: 4),
          ],
          if (onHistory != null)
            TextButton(onPressed: onHistory, child: const Text('History')),
          TextButton(onPressed: onDuplicate, child: const Text('Duplicate')),
          TextButton(onPressed: onEdit, child: const Text('Edit')),
        ],
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  const _Hero({required this.record, required this.isDraft});

  final FlightRecord record;
  final bool isDraft;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;
    final flight = record.flight;
    final aircraft = record.aircraft;
    final pending =
        flight.capacity.countersignature?.status ==
        CountersignatureStatus.pending;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _formatUtcDate(flight.offBlocks),
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            flight.route.join(' → '),
            style: AppMonoText.value(
              theme.colorScheme.onSurface,
              size: 20,
              weight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${aircraft.registration}  ·  ${aircraft.manufacturer} '
            '${aircraft.model}',
            style: theme.textTheme.bodyMedium?.copyWith(color: ink.muted),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                flight.blockTime.toHoursMinutes(),
                style: AppMonoText.value(
                  theme.colorScheme.onSurface,
                  size: 30,
                  weight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'BLOCK',
                  style: theme.textTheme.labelSmall?.copyWith(color: ink.faint),
                ),
              ),
            ],
          ),
          if (pending) ...[
            const SizedBox(height: 6),
            Text(
              'Countersignature pending — not yet creditable',
              style: theme.textTheme.bodySmall?.copyWith(
                color: context.semanticColors.currencyWarning,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _TimesSection extends StatelessWidget {
  const _TimesSection({required this.flight});

  final Flight flight;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DetailSectionHeader(label: 'TIMES (UTC)'),
        DetailRow(
          label: 'Off-blocks',
          value: _formatUtcDateTime(flight.offBlocks),
        ),
        if (flight.takeoff != null)
          DetailRow(
            label: 'Takeoff',
            value: _formatUtcDateTime(flight.takeoff!),
            indent: true,
          ),
        if (flight.landing != null)
          DetailRow(
            label: 'Landing',
            value: _formatUtcDateTime(flight.landing!),
            indent: true,
          ),
        DetailRow(
          label: 'On-blocks',
          value: _formatUtcDateTime(flight.onBlocks),
        ),
        DetailRow(
          label: 'Block time',
          value: flight.blockTime.toHoursMinutes(),
          emphasis: true,
        ),
      ],
    );
  }
}

class _CrewCapacitySection extends StatelessWidget {
  const _CrewCapacitySection({required this.capacity});

  final PilotCapacity capacity;

  @override
  Widget build(BuildContext context) {
    final instructor = capacity.instructor;
    final countersignature = capacity.countersignature;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DetailSectionHeader(label: 'CREW & CAPACITY'),
        DetailRow(
          label: 'Command authority',
          value: _yesNo(capacity.commandAuthority),
        ),
        DetailRow(
          label: 'Sole manipulator',
          value: _yesNo(capacity.soleManipulator),
        ),
        DetailRow(label: 'Sole occupant', value: _yesNo(capacity.soleOccupant)),
        DetailRow(
          label: 'Multi-pilot operation',
          value: _yesNo(capacity.multiPilotOperation),
        ),
        if (capacity.manipulationTime != null)
          DetailRow(
            label: 'Manipulation time',
            value: capacity.manipulationTime!.toHoursMinutes(),
            indent: true,
          ),
        DetailRow(
          label: 'Acting as instructor',
          value: _yesNo(capacity.actingAsInstructor),
        ),
        DetailRow(
          label: 'Acting as examiner',
          value: _yesNo(capacity.actingAsExaminer),
        ),
        DetailRow(label: 'PICUS claimed', value: _yesNo(capacity.picusClaimed)),
        if (capacity.picusClaimed)
          DetailRow(
            label: 'PIC intervention not required',
            value: _yesNo(capacity.picInterventionNotRequired),
            indent: true,
          ),
        if (instructor != null) ...[
          DetailRow(
            label: instructor.capacity == InstructorCapacity.flightExaminer
                ? 'Examiner aboard'
                : 'Instructor aboard',
            value: instructor.name ?? '—',
          ),
          DetailRow(
            label: 'Influenced flight (SPIC discriminator)',
            value: _yesNo(instructor.influencedFlight),
            indent: true,
          ),
        ],
        if (capacity.otherPilotRole != null)
          DetailRow(
            label: 'Other pilot role',
            value: _otherPilotRoleLabel(capacity.otherPilotRole!),
          ),
        if (countersignature != null)
          DetailRow(
            label: 'Countersignature',
            value: _countersignatureLabel(countersignature.status),
            valueColor:
                countersignature.status == CountersignatureStatus.pending
                ? context.semanticColors.currencyWarning
                : null,
          ),
      ],
    );
  }
}

class _CircuitsSection extends StatelessWidget {
  const _CircuitsSection({required this.flight});

  final Flight flight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;

    Widget circuitRow(String label, int takeoffs, int landings) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
      child: Row(
        children: [
          Expanded(child: Text(label, style: theme.textTheme.titleSmall)),
          SizedBox(
            width: 46,
            child: Text(
              '$takeoffs',
              textAlign: TextAlign.right,
              style: AppMonoText.value(theme.colorScheme.onSurface, size: 13.5),
            ),
          ),
          SizedBox(
            width: 46,
            child: Text(
              '$landings',
              textAlign: TextAlign.right,
              style: AppMonoText.value(theme.colorScheme.onSurface, size: 13.5),
            ),
          ),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          color: theme.colorScheme.surfaceContainerLowest,
          padding: const EdgeInsets.fromLTRB(20, 9, 20, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'CIRCUITS',
                  style: AppMonoText.tag(
                    ink.muted,
                  ).copyWith(letterSpacing: 1.1),
                ),
              ),
              SizedBox(
                width: 46,
                child: Text(
                  'T/O',
                  textAlign: TextAlign.right,
                  style: AppMonoText.tag(ink.faint),
                ),
              ),
              SizedBox(
                width: 46,
                child: Text(
                  'LDG',
                  textAlign: TextAlign.right,
                  style: AppMonoText.tag(ink.faint),
                ),
              ),
            ],
          ),
        ),
        circuitRow(
          'Day, full stop',
          flight.takeoffs.dayFullStop,
          flight.landings.dayFullStop,
        ),
        circuitRow(
          'Day, touch & go',
          flight.takeoffs.dayTouchAndGo,
          flight.landings.dayTouchAndGo,
        ),
        circuitRow(
          'Night, full stop',
          flight.takeoffs.nightFullStop,
          flight.landings.nightFullStop,
        ),
        circuitRow(
          'Night, touch & go',
          flight.takeoffs.nightTouchAndGo,
          flight.landings.nightTouchAndGo,
        ),
      ],
    );
  }
}

class _InstrumentNavigationSection extends StatelessWidget {
  const _InstrumentNavigationSection({required this.flight});

  final Flight flight;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DetailSectionHeader(label: 'INSTRUMENT & NAVIGATION'),
        DetailRow(
          label: 'IFR flight plan filed',
          value: _yesNo(flight.ifrFlightPlanFiled),
        ),
        DetailRow(
          label: 'Actual instrument',
          value: flight.actualInstrumentTime.toHoursMinutes(),
        ),
        DetailRow(
          label: 'Simulated instrument',
          value: flight.simulatedInstrumentTime.toHoursMinutes(),
        ),
        for (final approach in flight.approaches)
          DetailRow(
            label:
                '${approach.type.name.toUpperCase()} '
                '${approach.aerodromeIcao} ${approach.runway}',
            value: '×${approach.count}',
            indent: true,
          ),
        DetailRow(
          label: 'Holding procedures',
          value: '${flight.holdingProceduresCount}',
        ),
        DetailRow(
          label: 'Tracking performed',
          value: _yesNo(flight.trackingPerformed),
        ),
        DetailRow(
          label: 'Pre-planned navigation',
          value: _yesNo(flight.prePlannedNavigation),
        ),
      ],
    );
  }
}

class _RemarksSection extends StatelessWidget {
  const _RemarksSection({required this.remarks});

  final String remarks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DetailSectionHeader(label: 'REMARKS'),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 11, 20, 14),
          child: Text(
            remarks.isEmpty ? '—' : remarks,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: remarks.isEmpty ? ink.faint : ink.medium,
            ),
          ),
        ),
      ],
    );
  }
}

/// Every held jurisdiction's own derived figures for this one flight, laid
/// out one after another — CLAUDE.md's "side-by-side comparison" read as
/// "both visible on the same screen," not literally two rigid columns,
/// which cramps badly at phone width once labels run past a few
/// characters ("Cross-country", "Actual instrument").
class _DerivedSection extends StatelessWidget {
  const _DerivedSection({
    required this.flight,
    required this.aircraft,
    required this.projections,
  });

  final Flight flight;
  final Aircraft aircraft;
  final Map<String, JurisdictionProjection> projections;

  @override
  Widget build(BuildContext context) {
    final results = [
      for (final projection in projections.values)
        projection.project(flight, aircraft),
    ];
    final diverges = commandTimeDiverges(results);
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const DetailSectionHeader(label: 'DERIVED, PER JURISDICTION'),
        if (diverges)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 11, 20, 0),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: context.semanticColors.divergenceSurface,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'This flight\'s credited command-authority time differs '
                'depending which licence it\'s totalled under — compare the '
                'figures below.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: context.semanticColors.divergence,
                ),
              ),
            ),
          ),
        for (final result in results) _JurisdictionResult(result: result),
      ],
    );
  }
}

class _JurisdictionResult extends StatelessWidget {
  const _JurisdictionResult({required this.result});

  final ProjectionResult result;

  @override
  Widget build(BuildContext context) {
    final jurisdictionId = result.jurisdictionId;
    final functionRows = functionRowsByJurisdiction[jurisdictionId] ?? const [];
    final conditionRows =
        conditionRowsByJurisdiction[jurisdictionId] ?? const [];

    Widget quantityRow((String, String) row) {
      final quantity = result[row.$1];
      if (quantity == null) return const SizedBox.shrink();
      return DetailRow(
        label: row.$2,
        value: quantity.value.toHoursMinutes(),
        indent: true,
        valueColor: quantity.creditable
            ? null
            : context.semanticColors.currencyWarning,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 11, 20, 4),
          child: Text(
            jurisdictionLabels[jurisdictionId] ?? jurisdictionId,
            style: AppMonoText.tag(
              context.inkTiers.muted,
            ).copyWith(letterSpacing: 0.8),
          ),
        ),
        for (final row in functionRows) quantityRow(row),
        for (final row in conditionRows) quantityRow(row),
      ],
    );
  }
}

String _yesNo(bool value) => value ? 'Yes' : 'No';

String _otherPilotRoleLabel(OtherPilotRole role) => switch (role) {
  OtherPilotRole.requiredCrew => 'Required crew',
  OtherPilotRole.notRequiredCrew => 'Not required crew',
  OtherPilotRole.safetyPilot => 'Safety pilot',
};

String _countersignatureLabel(CountersignatureStatus status) =>
    switch (status) {
      CountersignatureStatus.pending => 'Pending',
      CountersignatureStatus.signed => 'Signed',
      CountersignatureStatus.refused => 'Refused',
    };

String _formatUtcDate(UtcInstant instant) {
  final d = instant.asUtcDateTime;
  const months = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

String _formatUtcDateTime(UtcInstant instant) {
  final d = instant.asUtcDateTime;
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  return '$hh:${mm}Z';
}
