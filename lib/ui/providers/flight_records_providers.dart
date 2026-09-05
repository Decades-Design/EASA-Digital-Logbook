import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/projection/jurisdiction_projection.dart';
import '../../domain/repository/flight_read_repository.dart';
import 'jurisdiction_projection_providers.dart';
import 'repository_providers.dart';

/// Draft flights, raw facts only — no jurisdiction involved (ADR-0003), so
/// this needs nothing beyond the repository itself.
final draftFlightRecordsProvider = StreamProvider<List<FlightRecord>>((ref) {
  return ref.watch(flightReadRepositoryProvider).watchDrafts();
});

/// Committed (active, non-tombstoned) flights, projected under [key]'s
/// [JurisdictionProjection] then unwrapped back to plain [FlightRecord]s —
/// a screen that only needs the raw facts (Logbook's chronological list)
/// shouldn't have to know a `Projection` was required to fetch them at
/// all; a screen that also wants the derived figures should read
/// `committedProjectedFlightsProvider` instead of this one.
///
/// [key]'s [FlightQuery] (#64) narrows the SQL query itself — every
/// existing caller that doesn't need filtering passes `FlightQuery()`
/// (its default), which is exactly the unfiltered query this provider
/// always ran before #64 added the second component to the family key.
final committedFlightRecordsProvider =
    StreamProvider.family<
      List<FlightRecord>,
      (JurisdictionProjection, FlightQuery)
    >((ref, key) {
      final (projection, query) = key;
      return ref
          .watch(flightReadRepositoryProvider)
          .watchFlights(projection: projection, query: query)
          .map((projected) => [for (final p in projected) p.record]);
    });

/// The same committed flights, still carrying [ProjectedFlight.projection]
/// — for a screen that needs the derived figures (Totals, Currency) rather
/// than just the raw facts.
final committedProjectedFlightsProvider =
    StreamProvider.family<
      List<ProjectedFlight>,
      (JurisdictionProjection, FlightQuery)
    >((ref, key) {
      final (projection, query) = key;
      return ref
          .watch(flightReadRepositoryProvider)
          .watchFlights(projection: projection, query: query);
    });

/// A committed flight's full revision history (#60) — a one-shot fetch
/// rather than a stream, since the only writers are this app's own
/// edit/tombstone/restore actions, which already know to `ref.invalidate`
/// this afterward rather than needing a live query for something nothing
/// else writes to concurrently.
final flightHistoryProvider = FutureProvider.family<FlightHistory?, String>((
  ref,
  flightId,
) {
  return ref.watch(flightReadRepositoryProvider).revisionHistory(flightId);
});

/// Every flight, draft and committed alike, regardless of jurisdiction —
/// for a caller that just needs to look one up by id
/// ([flightRecordByIdProvider]) or scan every route ([#63]'s aerodrome
/// recency/frequency ranking), rather than the derived figures
/// `committedProjectedFlightsProvider` exists for. Needs *some*
/// [JurisdictionProjection] to satisfy `watchFlights`'s required
/// parameter even though nothing here reads the derived side of it —
/// reuses whichever the pilot's held licences already produced rather
/// than adding a second, projection-free read path to
/// `FlightReadRepository` just for this.
final allFlightRecordsProvider = FutureProvider<List<FlightRecord>>((
  ref,
) async {
  final drafts = await ref.watch(draftFlightRecordsProvider.future);
  final projections = await ref.watch(jurisdictionProjectionsProvider.future);
  if (projections.isEmpty) {
    return drafts;
  }
  final committed = await ref.watch(
    committedFlightRecordsProvider((
      projections.values.first,
      const FlightQuery(),
    )).future,
  );
  return [...drafts, ...committed];
});

/// The current, live state of one flight by id — a screen that was handed
/// a [FlightRecord] at navigation time (Logbook's row tap) but stays open
/// across an edit made *from* it needs this rather than the now-stale
/// snapshot it was constructed with. Returns `null` once the id resolves
/// to nothing (deleted/tombstoned), never throws.
final flightRecordByIdProvider = Provider.family<FlightRecord?, String>((
  ref,
  id,
) {
  final records = ref.watch(allFlightRecordsProvider).value;
  if (records == null) return null;
  for (final record in records) {
    if (record.id == id) return record;
  }
  return null;
});
