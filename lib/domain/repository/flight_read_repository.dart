import 'package:freezed_annotation/freezed_annotation.dart';

import '../model/aircraft.dart';
import '../model/calendar_date.dart';
import '../model/flight.dart';
import '../model/utc_instant.dart';
import '../projection/projection.dart';
import '../projection/projection_result.dart';

part 'flight_read_repository.freezed.dart';

/// A flight's raw facts, resolved from storage: which aircraft it names,
/// and the id it was stored under. No jurisdiction involved — used for
/// drafts, where nothing has been asserted yet (ADR-0003).
@freezed
abstract class FlightRecord with _$FlightRecord {
  const factory FlightRecord({
    required String id,
    required Flight flight,
    required Aircraft aircraft,
  }) = _FlightRecord;
}

/// A [FlightRecord] plus the derived quantities [Projection.project]
/// computed for it, under whichever jurisdiction the caller's [Projection]
/// represents.
@freezed
abstract class ProjectedFlight with _$ProjectedFlight {
  const factory ProjectedFlight({
    required FlightRecord record,
    required ProjectionResult projection,
  }) = _ProjectedFlight;
}

/// Matches against [PilotCapacity]'s own raw boolean discriminators —
/// deliberately not against a derived label like "PIC", since which flights
/// count as PIC is jurisdiction-dependent (rule 1). Every field unset means
/// "don't filter on this"; set fields are ANDed together.
@freezed
abstract class CapacityFilter with _$CapacityFilter {
  const factory CapacityFilter({
    bool? commandAuthority,
    bool? soleManipulator,
    bool? soleOccupant,
    bool? multiPilotOperation,
    bool? actingAsInstructor,
    bool? actingAsExaminer,
    bool? picusClaimed,
  }) = _CapacityFilter;
}

/// Filters for [FlightReadRepository.watchFlights]. Every field unset means
/// "don't filter on this"; set fields are ANDed together. [from]/[to]
/// filter on [Flight.offBlocks]'s UTC calendar date (ADR-0009's "date of
/// departure, in UTC" policy, applied as a range). [aerodromeIdentifier]
/// matches a flight that touched that identifier anywhere — a route leg or
/// an approach.
@freezed
abstract class FlightQuery with _$FlightQuery {
  const factory FlightQuery({
    CalendarDate? from,
    CalendarDate? to,
    String? aircraftId,
    String? aerodromeIdentifier,
    CapacityFilter? capacity,
  }) = _FlightQuery;
}

/// Read access to flights, returning projections rather than raw rows — see
/// `docs/superpowers/specs/2026-08-09-flight-read-repository-design.md`.
/// The read-side counterpart to `FlightRepository` (write side, M2).
abstract class FlightReadRepository {
  /// Committed, active (non-tombstoned) flights matching [query], projected
  /// under [projection]. Re-emits whenever a write touches any flight this
  /// query could match.
  Stream<List<ProjectedFlight>> watchFlights({
    required Projection projection,
    FlightQuery query = const FlightQuery(),
  });

  /// A single committed flight by id — active or tombstoned. Null if
  /// [flightId] names a draft or does not exist.
  Future<ProjectedFlight?> find(
    String flightId, {
    required Projection projection,
  });

  /// Draft flights, raw facts only — no jurisdiction, nothing to project.
  Stream<List<FlightRecord>> watchDrafts();

  /// A single draft by id. Null if [flightId] names a committed flight or
  /// does not exist.
  Future<FlightRecord?> findDraft(String flightId);

  /// The full revision chain for a committed flight (CLAUDE.md rule 4) —
  /// #60. Null if [flightId] names a draft or does not exist: a draft has
  /// never been asserted to an authority, so there is nothing to show a
  /// history section for ("drafts show no history section rather than an
  /// empty one").
  Future<FlightHistory?> revisionHistory(String flightId);
}

/// What kind of event one [FlightRevisionEntry] records. [commit] is
/// synthetic — there is no `flight_revisions` row for the moment a flight
/// was first committed, but the history reads oddly without a starting
/// point, so #60's repository implementation synthesizes one from
/// `committedAt`.
enum FlightRevisionKind { commit, edit, tombstone, restore }

/// One entry in a committed flight's revision chain (#60), already
/// reconstructed into full [Flight] snapshots so a viewer can hand
/// [before]/[after] straight to `diffFlightsForDisplay` rather than
/// re-deriving raw-fact changes itself. [before] is null only for the
/// [FlightRevisionKind.commit] entry — everything else has a prior state to
/// compare against. [reason] is the free text given at the time (edit,
/// tombstone or restore); null for the synthetic commit entry, which never
/// had one to give.
class FlightRevisionEntry {
  const FlightRevisionEntry({
    required this.kind,
    required this.recordedAt,
    required this.after,
    this.before,
    this.reason,
  });

  final FlightRevisionKind kind;
  final UtcInstant recordedAt;
  final Flight after;
  final Flight? before;
  final String? reason;
}

/// The full history for one committed flight (#60). [entries] is newest
/// first and always ends with the synthetic [FlightRevisionKind.commit]
/// entry. [isTombstoned] reflects the flight's *current* state — whether
/// its most recent lifecycle event was a tombstone that hasn't since been
/// restored — so a viewer knows whether to offer a Restore action.
class FlightHistory {
  const FlightHistory({required this.isTombstoned, required this.entries});

  final bool isTombstoned;
  final List<FlightRevisionEntry> entries;
}
