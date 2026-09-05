import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/model/calendar_date.dart';
import '../../domain/repository/flight_read_repository.dart';
import '../aerodromes/aerodrome_picker_screen.dart';
import '../entry/widgets/entry_card.dart';
import '../entry/widgets/entry_section_label.dart';
import '../entry/widgets/entry_top_bar.dart';
import '../providers/aircraft_providers.dart';
import 'logbook_filter.dart';

/// #64: the structured side of Logbook's search/filter — date range,
/// aircraft, aerodrome, capacity dimensions, day/night, IFR. Free text
/// stays on the Logbook screen's own search box, not duplicated here.
///
/// Returns the edited [LogbookFilter] via `Navigator.pop` on Apply, or
/// `null` if cancelled.
class LogbookFiltersScreen extends ConsumerStatefulWidget {
  const LogbookFiltersScreen({super.key, required this.initial});

  final LogbookFilter initial;

  @override
  ConsumerState<LogbookFiltersScreen> createState() =>
      _LogbookFiltersScreenState();
}

class _LogbookFiltersScreenState extends ConsumerState<LogbookFiltersScreen> {
  late LogbookFilter _filter;

  @override
  void initState() {
    super.initState();
    _filter = widget.initial;
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final current = isFrom ? _filter.from : _filter.to;
    final picked = await showDatePicker(
      context: context,
      initialDate: current == null
          ? now
          : DateTime(current.year, current.month, current.day),
      firstDate: DateTime(1944),
      lastDate: DateTime(now.year + 1),
    );
    if (picked == null) return;
    final date = CalendarDate(picked.year, picked.month, picked.day);
    setState(() {
      _filter = isFrom
          ? _filter.copyWith(from: date)
          : _filter.copyWith(to: date);
    });
  }

  Future<void> _pickAircraft() async {
    final recordsAsync = ref.read(aircraftRecordsProvider);
    final records = recordsAsync.value ?? const [];
    final active =
        [
          for (final r in records)
            if (!r.aircraft.archived) r,
        ]..sort(
          (a, b) => a.aircraft.registration.compareTo(b.aircraft.registration),
        );

    final selected = await showModalBottomSheet<String?>(
      context: context,
      builder: (context) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              title: const Text('Any aircraft'),
              onTap: () => Navigator.of(context).pop(''),
            ),
            for (final record in active)
              ListTile(
                title: Text(record.aircraft.registration),
                subtitle: Text(
                  '${record.aircraft.manufacturer} ${record.aircraft.model}',
                ),
                onTap: () => Navigator.of(context).pop(record.id),
              ),
          ],
        ),
      ),
    );
    if (selected == null) return;
    if (selected.isEmpty) {
      setState(() => _filter = _filter.copyWith(clearAircraft: true));
      return;
    }
    final record = active.firstWhere((r) => r.id == selected);
    setState(
      () => _filter = _filter.copyWith(
        aircraftId: record.id,
        aircraftLabel: record.aircraft.registration,
      ),
    );
  }

  Future<void> _pickAerodrome() async {
    final identifier = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const AerodromePickerScreen()),
    );
    if (identifier == null) return;
    setState(() => _filter = _filter.copyWith(aerodromeIdentifier: identifier));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final capacity = _filter.capacity ?? const CapacityFilter();

    void setCapacity(CapacityFilter Function(CapacityFilter) update) {
      setState(() => _filter = _filter.copyWith(capacity: update(capacity)));
    }

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            EntryTopBar(
              title: 'Filters',
              onSaveDraft: () => Navigator.of(context).pop(_filter),
              saveLabel: 'Apply',
            ),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const EntrySectionLabel('Date range'),
                        const SizedBox(height: 8),
                        EntryCard(
                          child: Column(
                            children: [
                              EntryCardRow(
                                label: 'From',
                                onTap: () => _pickDate(isFrom: true),
                                child: Text(
                                  _formatDate(_filter.from),
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                              const EntryCardDivider(),
                              EntryCardRow(
                                label: 'To',
                                onTap: () => _pickDate(isFrom: false),
                                child: Text(
                                  _formatDate(_filter.to),
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const EntrySectionLabel('Aircraft & aerodrome'),
                        const SizedBox(height: 8),
                        EntryCard(
                          child: Column(
                            children: [
                              EntryCardRow(
                                label: 'Aircraft',
                                onTap: _pickAircraft,
                                child: Text(
                                  _filter.aircraftLabel ?? 'Any',
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                              const EntryCardDivider(),
                              EntryCardRow(
                                label: 'Aerodrome',
                                onTap: _pickAerodrome,
                                child: Text(
                                  _filter.aerodromeIdentifier ?? 'Any',
                                  style: theme.textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const EntrySectionLabel('Conditions'),
                        const SizedBox(height: 8),
                        EntryCard(
                          child: Column(
                            children: [
                              _TriStateRow(
                                label: 'Night flying',
                                value: _filter.hasNightFlying,
                                onChanged: (v) => setState(
                                  () => _filter = v == null
                                      ? _filter.copyWith(clearNight: true)
                                      : _filter.copyWith(hasNightFlying: v),
                                ),
                              ),
                              const EntryCardDivider(),
                              _TriStateRow(
                                label: 'IFR flight plan filed',
                                value: _filter.ifrFlightPlanFiled,
                                onChanged: (v) => setState(
                                  () => _filter = v == null
                                      ? _filter.copyWith(clearIfr: true)
                                      : _filter.copyWith(ifrFlightPlanFiled: v),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const EntrySectionLabel('Crew & capacity'),
                        const SizedBox(height: 8),
                        EntryCard(
                          child: Column(
                            children: [
                              _TriStateRow(
                                label: 'Command authority',
                                value: capacity.commandAuthority,
                                onChanged: (v) => setCapacity(
                                  (c) => c.copyWith(commandAuthority: v),
                                ),
                              ),
                              const EntryCardDivider(),
                              _TriStateRow(
                                label: 'Sole manipulator',
                                value: capacity.soleManipulator,
                                onChanged: (v) => setCapacity(
                                  (c) => c.copyWith(soleManipulator: v),
                                ),
                              ),
                              const EntryCardDivider(),
                              _TriStateRow(
                                label: 'Sole occupant',
                                value: capacity.soleOccupant,
                                onChanged: (v) => setCapacity(
                                  (c) => c.copyWith(soleOccupant: v),
                                ),
                              ),
                              const EntryCardDivider(),
                              _TriStateRow(
                                label: 'Multi-pilot operation',
                                value: capacity.multiPilotOperation,
                                onChanged: (v) => setCapacity(
                                  (c) => c.copyWith(multiPilotOperation: v),
                                ),
                              ),
                              const EntryCardDivider(),
                              _TriStateRow(
                                label: 'Acting as instructor',
                                value: capacity.actingAsInstructor,
                                onChanged: (v) => setCapacity(
                                  (c) => c.copyWith(actingAsInstructor: v),
                                ),
                              ),
                              const EntryCardDivider(),
                              _TriStateRow(
                                label: 'Acting as examiner',
                                value: capacity.actingAsExaminer,
                                onChanged: (v) => setCapacity(
                                  (c) => c.copyWith(actingAsExaminer: v),
                                ),
                              ),
                              const EntryCardDivider(),
                              _TriStateRow(
                                label: 'PICUS claimed',
                                value: capacity.picusClaimed,
                                onChanged: (v) => setCapacity(
                                  (c) => c.copyWith(picusClaimed: v),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (!_filter.isEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 22, 16, 0),
                      child: OutlinedButton(
                        onPressed: () => setState(
                          () => _filter = LogbookFilter(
                            searchText: _filter.searchText,
                          ),
                        ),
                        child: const Text('Clear all filters'),
                      ),
                    ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Any / Yes / No — every structured toggle in this screen is this same
/// three-state shape (`null` = don't filter on this dimension at all,
/// never a silently-defaulted "no").
class _TriStateRow extends StatelessWidget {
  const _TriStateRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool? value;
  final ValueChanged<bool?> onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    Widget pill(String text, bool? forValue) {
      final selected = value == forValue;
      return InkWell(
        onTap: () => onChanged(forValue),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? scheme.surface : null,
            borderRadius: BorderRadius.circular(6),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: scheme.onSurface.withValues(alpha: 0.14),
                      blurRadius: 3,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          child: Text(
            text,
            style: theme.textTheme.labelMedium?.copyWith(
              color: scheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                pill('Any', null),
                pill('Yes', true),
                pill('No', false),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

const _months = [
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

String _formatDate(CalendarDate? date) {
  if (date == null) return 'Any';
  return '${date.day} ${_months[date.month - 1]} ${date.year}';
}
