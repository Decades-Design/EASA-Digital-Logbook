import '../../domain/model/calendar_date.dart';
import '../../domain/repository/flight_read_repository.dart';

/// The Logbook screen's combined filter state (#64): every structured
/// dimension the acceptance criteria list (date range, aircraft, aerodrome,
/// capacity, day/night, IFR) plus one free-text field matched against
/// registration, remarks and crew names.
class LogbookFilter {
  const LogbookFilter({
    this.from,
    this.to,
    this.aircraftId,
    this.aircraftLabel,
    this.aerodromeIdentifier,
    this.capacity,
    this.ifrFlightPlanFiled,
    this.hasNightFlying,
    this.searchText = '',
  });

  final CalendarDate? from;
  final CalendarDate? to;
  final String? aircraftId;

  /// Display label for the picked aircraft (its registration) — carried
  /// alongside [aircraftId] purely so the active-filter chip has something
  /// readable to show without a second repository lookup.
  final String? aircraftLabel;
  final String? aerodromeIdentifier;
  final CapacityFilter? capacity;
  final bool? ifrFlightPlanFiled;
  final bool? hasNightFlying;
  final String searchText;

  bool get isEmpty =>
      from == null &&
      to == null &&
      aircraftId == null &&
      aerodromeIdentifier == null &&
      capacity == null &&
      ifrFlightPlanFiled == null &&
      hasNightFlying == null &&
      searchText.trim().isEmpty;

  /// The subset of this filter [FlightReadRepository.watchFlights] can
  /// apply at the SQL layer, narrowing committed flights before they ever
  /// reach Dart — purely a performance narrowing. [matches] remains the
  /// single source of truth for correctness (see its own dartdoc), applied
  /// on top of this regardless of what already ran in SQL.
  FlightQuery toFlightQuery() => FlightQuery(
    from: from,
    to: to,
    aircraftId: aircraftId,
    aerodromeIdentifier: aerodromeIdentifier,
    capacity: capacity,
  );

  LogbookFilter copyWith({
    CalendarDate? from,
    bool clearFrom = false,
    CalendarDate? to,
    bool clearTo = false,
    String? aircraftId,
    String? aircraftLabel,
    bool clearAircraft = false,
    String? aerodromeIdentifier,
    bool clearAerodrome = false,
    CapacityFilter? capacity,
    bool clearCapacity = false,
    bool? ifrFlightPlanFiled,
    bool clearIfr = false,
    bool? hasNightFlying,
    bool clearNight = false,
    String? searchText,
  }) {
    return LogbookFilter(
      from: clearFrom ? null : (from ?? this.from),
      to: clearTo ? null : (to ?? this.to),
      aircraftId: clearAircraft ? null : (aircraftId ?? this.aircraftId),
      aircraftLabel: clearAircraft
          ? null
          : (aircraftLabel ?? this.aircraftLabel),
      aerodromeIdentifier: clearAerodrome
          ? null
          : (aerodromeIdentifier ?? this.aerodromeIdentifier),
      capacity: clearCapacity ? null : (capacity ?? this.capacity),
      ifrFlightPlanFiled: clearIfr
          ? null
          : (ifrFlightPlanFiled ?? this.ifrFlightPlanFiled),
      hasNightFlying: clearNight
          ? null
          : (hasNightFlying ?? this.hasNightFlying),
      searchText: searchText ?? this.searchText,
    );
  }

  /// The single source of truth for whether [record] satisfies this
  /// filter — checked in Dart against every flight, draft and committed
  /// alike, regardless of what [toFlightQuery] already narrowed at the SQL
  /// layer for committed ones (drafts never go through SQL filtering at
  /// all — `FlightReadRepository.watchDrafts` takes no query). Re-checking
  /// a SQL-narrowed field here is a cheap no-op match, not a bug risk: it
  /// means there is exactly one place structured-filter correctness lives,
  /// not two definitions that could quietly drift apart.
  bool matches(FlightRecord record) {
    final flight = record.flight;

    if (from != null || to != null) {
      final date = CalendarDate.fromUtcInstant(flight.offBlocks);
      if (from != null && date < from!) return false;
      if (to != null && date > to!) return false;
    }

    // `FlightRecord.aircraft` carries no id of its own (the mapper strips
    // it — see `aircraft_mapper.dart`), only the resolved `Aircraft` value,
    // so the Dart-side re-check matches by registration (`aircraftLabel`)
    // rather than by [aircraftId], which only means something to
    // `toFlightQuery`'s SQL-level `aircraft_id` column filter.
    if (aircraftLabel != null &&
        record.aircraft.registration != aircraftLabel) {
      return false;
    }

    if (aerodromeIdentifier != null) {
      final identifier = aerodromeIdentifier!.toUpperCase();
      final touchesRoute = flight.route.any(
        (leg) => leg.toUpperCase() == identifier,
      );
      final touchesApproach = flight.approaches.any(
        (a) => a.aerodromeIcao.toUpperCase() == identifier,
      );
      if (!touchesRoute && !touchesApproach) return false;
    }

    final capacityFilter = capacity;
    if (capacityFilter != null) {
      final c = flight.capacity;
      if (capacityFilter.commandAuthority != null &&
          c.commandAuthority != capacityFilter.commandAuthority) {
        return false;
      }
      if (capacityFilter.soleManipulator != null &&
          c.soleManipulator != capacityFilter.soleManipulator) {
        return false;
      }
      if (capacityFilter.soleOccupant != null &&
          c.soleOccupant != capacityFilter.soleOccupant) {
        return false;
      }
      if (capacityFilter.multiPilotOperation != null &&
          c.multiPilotOperation != capacityFilter.multiPilotOperation) {
        return false;
      }
      if (capacityFilter.actingAsInstructor != null &&
          c.actingAsInstructor != capacityFilter.actingAsInstructor) {
        return false;
      }
      if (capacityFilter.actingAsExaminer != null &&
          c.actingAsExaminer != capacityFilter.actingAsExaminer) {
        return false;
      }
      if (capacityFilter.picusClaimed != null &&
          c.picusClaimed != capacityFilter.picusClaimed) {
        return false;
      }
    }

    if (ifrFlightPlanFiled != null &&
        flight.ifrFlightPlanFiled != ifrFlightPlanFiled) {
      return false;
    }

    if (hasNightFlying != null) {
      // Same raw-fact definition `logbook_view_model.dart`'s
      // `FlightRowBadge.night` already uses — a landing recorded as
      // night, not a derived "night time" figure (CLAUDE.md rule 5).
      final nightCircuits =
          flight.landings.nightFullStop + flight.landings.nightTouchAndGo;
      final flightHasNight = nightCircuits > 0;
      if (flightHasNight != hasNightFlying) return false;
    }

    final query = searchText.trim().toLowerCase();
    if (query.isNotEmpty) {
      final haystack = [
        record.aircraft.registration,
        flight.remarks,
        flight.otherPilotName,
        flight.capacity.instructor?.name,
        flight.capacity.endorsingInstructorName,
        flight.capacity.countersignature?.signatoryName,
        ...flight.route,
        for (final approach in flight.approaches) approach.aerodromeIcao,
      ].whereType<String>().join(' ').toLowerCase();
      if (!haystack.contains(query)) return false;
    }

    return true;
  }
}
