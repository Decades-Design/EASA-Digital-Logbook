import '../model/flight.dart';
import '../model/utc_instant.dart';

/// One flight to create as part of an import batch (#73), already resolved
/// to a stored aircraft id — the same precondition [FlightRepository.createDraft]
/// has for its own `aircraftId`.
typedef ImportBatchFlight = ({Flight flight, String aircraftId});

/// One recorded import batch (#73), independent of whichever of its
/// flights still exist — a batch whose every flight was a draft and has
/// since been undone still has this record, since [FlightRepository.undoImportBatch]
/// deletes flights, never the batch itself.
///
/// [flightCount] reflects the *current* number of flights still tagged
/// with this batch, not the size at import time — a fully-undone
/// all-drafts batch reads 0, a partially-undone batch reads however many
/// tombstoned survivors remain. That's deliberate: after undo, "how many
/// flights does this batch still account for" is the more useful question
/// than "how many did it originally create."
class ImportBatchSummary {
  const ImportBatchSummary({
    required this.id,
    required this.sourceLabel,
    required this.importedAt,
    required this.flightCount,
    this.undoneAt,
  });

  final String id;
  final String sourceLabel;
  final UtcInstant importedAt;
  final int flightCount;
  final UtcInstant? undoneAt;

  bool get isUndone => undoneAt != null;
}

/// What [FlightRepository.undoImportBatch] actually did, split by outcome —
/// #73's own "reporting the split to the user" acceptance criterion.
class ImportUndoResult {
  const ImportUndoResult({
    required this.deletedDraftCount,
    required this.tombstonedCommittedCount,
  });

  final int deletedDraftCount;
  final int tombstonedCommittedCount;
}

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
  /// [importBatchId] tags it as belonging to an import batch (#73); null
  /// for a flight entered by hand, which is every caller but
  /// [applyImportBatch] itself. Returns the new flight's generated id.
  Future<String> createDraft(
    Flight flight, {
    required String aircraftId,
    String? importBatchId,
  });

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

  /// Creates every one of [flights] as a new draft, tagged as one import
  /// batch (#73) — CLAUDE.md's "every import is a transaction ... and must
  /// never partially apply". All-or-nothing: if any row fails, nothing
  /// among [flights] is written and no batch is recorded. Returns the new
  /// batch's id.
  Future<String> applyImportBatch({
    required String sourceLabel,
    required List<ImportBatchFlight> flights,
  });

  /// Every recorded import batch, most recent first.
  Future<List<ImportBatchSummary>> listImportBatches();

  /// Undoes [batchId]: deletes every flight in it still a draft
  /// ([deleteDraft]'s own clean-delete guarantee), tombstones every one
  /// already committed (rule 4: a committed flight is never hard-deleted),
  /// and marks the batch undone. Throws [StateError] if [batchId] is
  /// unknown or already undone.
  Future<ImportUndoResult> undoImportBatch(String batchId, {String? reason});
}
