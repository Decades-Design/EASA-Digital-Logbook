import '../model/flight.dart';

/// Write access to flights, enforcing the draft/committed/tombstoned state
/// machine (ADR-0003, CLAUDE.md rule 4). The only interface allowed to
/// write the `flights` table — see the "Repository" section of
/// `docs/superpowers/specs/2026-08-09-m2-flight-persistence-design.md`.
///
/// Read/query methods (by date range, by aircraft, jurisdiction-projected
/// results) are #35's job, once this exists to build on.
abstract class FlightRepository {
  /// Creates a new draft flight against [aircraftId] (an id returned by
  /// `AircraftRepository.upsert`, not [Flight.aircraftRegistration]).
  /// Returns the new flight's generated id.
  Future<String> createDraft(Flight flight, {required String aircraftId});

  /// Overwrites a draft flight in place. Throws [StateError] if [flightId]
  /// names a committed flight.
  Future<void> updateDraft(String flightId, Flight flight);

  /// Deletes a draft flight outright, along with its route/approach rows.
  /// Throws [StateError] if [flightId] names a committed flight — a
  /// committed flight is tombstoned, never deleted.
  Future<void> deleteDraft(String flightId);

  /// Commits a draft, setting `committedAt` to now. Throws [StateError] if
  /// [flightId] is already committed.
  Future<void> commit(String flightId);

  /// Edits a committed flight: records one `edit` revision capturing the
  /// prior values of whatever changed, then writes [flight]'s new values.
  /// Throws [StateError] if [flightId] is a draft or is tombstoned.
  Future<void> updateCommitted(
    String flightId,
    Flight flight, {
    String? reason,
  });

  /// Soft-deletes a committed flight, recording a `tombstone` revision.
  /// Throws [StateError] if [flightId] is a draft or already tombstoned.
  Future<void> tombstone(String flightId, {String? reason});

  /// Reverses [tombstone], recording a `restore` revision. Throws
  /// [StateError] if [flightId] is not currently tombstoned.
  Future<void> restore(String flightId, {String? reason});
}
