# Flight read repository — Design

**Status:** Proposed
**Date:** 2026-08-09
**Covers:** issue #35
**Depends on:** the M2 persistence foundation (#31, #32, #33, #34) — `flights`,
`flight_route_legs`, `flight_approaches` schema, `FlightRepository` (write side),
`AircraftRepository`, all merged.

## Context

M2 built the write side only: a `FlightRepository` enforcing the draft/committed/tombstoned
state machine, and a one-directional mapper (`flightToRow`) converting a domain `Flight` into
its flattened row shape. Nothing can read a flight back out yet — `flightFromRow` was
deliberately left unbuilt because nothing needed it at the time (M2's own plan documents this
explicitly).

#35 asks for the other half: repositories that expose filtered, jurisdiction-projected,
reactive reads, so the UI never touches a raw Drift row.

> Repositories expose queries by date range, aircraft, aerodrome and capacity. Read methods
> take a jurisdiction and return projected results. The UI never sees a raw row, only a
> projection. Streaming/reactive queries so the UI updates on write. Repository interfaces
> defined in domain, implementations in data, so domain tests need no database.

This slots directly on top of the existing projection engine from M1:
`Projection.project(Flight, Aircraft) -> ProjectionResult`, where a `Projection` instance
(`JurisdictionProjection`) is already bound to one jurisdiction at construction. The read
repository doesn't resolve jurisdictions itself — a caller passes in whichever `Projection` it
already has.

## Scope

One new interface, `FlightReadRepository`, kept separate from the write-side `FlightRepository`
— each interface stays single-purpose, matching the M2 design spec's own note that read methods
are "#35's job, once this exists to build on." `AircraftRepository`/`CustomAerodromeRepository`
are unchanged; `AircraftRepository.find` already exists and is reused as-is to resolve an
aircraft for a flight.

Out of scope (see Non-goals): aggregate/total queries, currency-rule evaluation, the
jurisdiction-comparison/badge UI, pagination.

## Result types

Two small domain types travel with the interface, both in
`lib/domain/repository/flight_read_repository.dart`:

```dart
@freezed
abstract class FlightRecord with _$FlightRecord {
  const factory FlightRecord({
    required String id,
    required Flight flight,
    required Aircraft aircraft,
  }) = _FlightRecord;
}

@freezed
abstract class ProjectedFlight with _$ProjectedFlight {
  const factory ProjectedFlight({
    required FlightRecord record,
    required ProjectionResult projection,
  }) = _ProjectedFlight;
}
```

`FlightRecord` is raw facts only — id, `Flight`, and the `Aircraft` it was flown in. Used for
drafts, where nothing has been asserted yet and there is nothing to project (ADR-0003: a draft
is not yet a record). `ProjectedFlight` wraps a `FlightRecord` with the derived quantities for
whichever jurisdiction the caller's `Projection` represents. Both are freezed, matching every
other multi-field domain model in this codebase.

## Interface

```dart
abstract class FlightReadRepository {
  /// Committed, active (non-tombstoned) flights matching [query], projected
  /// under [projection]. Re-emits whenever a write touches any flight this
  /// query could match.
  Stream<List<ProjectedFlight>> watchFlights({
    required Projection projection,
    FlightQuery query = const FlightQuery(),
  });

  /// A single committed flight by id — active or tombstoned, since #34's
  /// restore flow needs to find a tombstoned one. Null if [flightId] names
  /// a draft or doesn't exist.
  Future<ProjectedFlight?> find(String flightId, {required Projection projection});

  /// Draft flights, raw facts only — no jurisdiction, nothing to project.
  Stream<List<FlightRecord>> watchDrafts();

  /// A single draft by id. Null if [flightId] names a committed flight or
  /// doesn't exist.
  Future<FlightRecord?> findDraft(String flightId);
}
```

`watchFlights`/`watchDrafts` default to excluding drafts and tombstoned flights respectively —
`watchFlights` never returns a draft or a tombstoned flight; `watchDrafts` only ever returns
drafts. This matches ADR-0003: a draft is excluded from every list a total or currency
evaluation could read from. `find` is the one deliberate exception, scoped to committed flights
only (both active and tombstoned) — a lookup-by-id is how the revision-history/restore UI
reaches a specific tombstoned flight, so it cannot apply the same default exclusion a list does.

Single-value lookups (`find`, `findDraft`) are plain `Future`s, not streams — nothing reactive
is needed to open one entry once. Only the list methods stream, via Drift's `.watch()`.

## Filtering — `FlightQuery`

```dart
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
```

Every field is optional; unset means "don't filter on this." All set filters are ANDed
together.

**`from`/`to`** filter on `Flight.offBlocks`, converted to a UTC epoch-millisecond range at the
day boundary — the same "date of departure, in UTC" policy ADR-0009 established for
`logbookDate`, applied as a range instead of a single truncation.

**`aircraftId`** matches `flights.aircraft_id` directly.

**`aerodromeIdentifier`** matches a flight that touched that identifier anywhere: any
`flight_route_legs.identifier`, or any `flight_approaches.aerodrome_icao` — a pilot searching
"flights at EGKB" doesn't distinguish between EGKB as a route stop and EGKB as an approach-only
touch point.

**`capacity`** matches directly against `PilotCapacity`'s own raw boolean discriminators —
deliberately *not* against a derived label like "PIC," since which flights count as PIC is
jurisdiction-dependent (rule 1: never store or query a derived quantity as if it were raw). A
caller wanting "my PIC flights under EASA" combines `CapacityFilter(commandAuthority: true)`
with the EASA `Projection` and reads the projected result off each match — filtering and
projecting stay separate concerns, never conflated into one query.

## Streaming mechanics

`DriftFlightReadRepository` (in `lib/data/repositories/`) builds each query as an ordinary
Drift `SimpleSelectStatement` and calls `.watch()` instead of `.get()`. Drift tracks every table
a statement reads — including subqueries — and automatically re-emits when a write touches any
of them. This means `watchFlights()` updates live when `FlightRepository.commit`/
`updateCommitted`/`tombstone`/`restore` write to `flights`, `flight_route_legs`, or
`flight_approaches` — no manual cache-invalidation logic; it is a built-in Drift behaviour this
plan only has to wire up correctly, not build.

Each raw emission is transformed via `.asyncMap` into `List<ProjectedFlight>`: load each
matching flight's children, map to `Flight` via the new `flightFromRow`, resolve its `Aircraft`,
and call `projection.project(flight, aircraft)`. This redoes the full fetch-and-project work on
every emission rather than diffing incrementally — correct, not fast, matching the posture
`Projection` itself already takes ("no caching or memoisation... correctness first, measure
before optimising"). Flagged here explicitly as a known, deliberate limitation, not something to
silently optimize around in this pass.

**Known gap: an aircraft edit does not trigger a re-emission.** The `Aircraft` for each result
is resolved via `AircraftRepository.find` inside the `.asyncMap` step, not as part of the
watched SQL statement itself — Drift only tracks tables referenced by the statement it is
watching, so editing an aircraft's registration or qualifications will not, on its own, cause an
already-open `watchFlights()` stream to re-emit with the updated aircraft data. This is
acceptable for now (aircraft edits are rare compared to flight writes, and the same "correctness
first" posture applies), but it is a real limitation, not an oversight — worth fixing if it
turns out to matter once the UI exists to notice it.

## Completing the row↔domain mapper

M2 built only `flightToRow` (domain → row); `flightFromRow` was deliberately left unbuilt since
nothing needed it yet. This spec is exactly what needs it now:

```dart
Flight flightFromRow(
  FlightRow row,
  List<FlightRouteLegRow> legs,
  List<FlightApproachRow> approaches, {
  required String aircraftRegistration,
}) 
```

Converting a `FlightRow` back to a `Flight` requires resolving `aircraftId` →
`Flight.aircraftRegistration`, which needs the `Aircraft` object. Every read path here already
fetches that `Aircraft` anyway (to build `FlightRecord` and to call `projection.project`), so the
resolution falls out naturally — the caller passes `aircraft.registration` straight through, no
separate lookup inside the mapper itself.

`flightFromRow` reconstructs every nested structure the flattened row carries: `PilotCapacity`
(including the nullable `InstructorPresence`/`Countersignature` sub-blocks, parsed back from
their flattened columns — `CalendarDate.parse` for the two `*CredentialExpiry` columns),
`CircuitCounts` ×2, and the `route`/`approaches` lists from the child rows, ordered by
`sequence` for route legs.

**Contract for a flight whose `aircraftId` names no row in `aircraft`:** this should not happen
— `flights.aircraft_id` is a foreign key — but the read path must still have an explicit answer
rather than an implicit one. `DriftFlightReadRepository` treats it as a `StateError` naming the
flight and aircraft ids, not a silently-skipped row or a null field: a dangling foreign key is a
data-integrity bug, and hiding it from a list result would be worse than surfacing it loudly.

## Testing

Real in-memory Drift database (`NativeDatabase.memory()`), seeded through the existing write
repositories (`FlightRepository.createDraft`/`commit`, `AircraftRepository.upsert`), then
exercised through `DriftFlightReadRepository` — same posture as M2. At minimum:

- Each `FlightQuery` filter in isolation (date range, aircraft, aerodrome — both a route-leg
  match and an approach-only match, capacity) and two combined in one query.
- `watchFlights` emits an updated list after a write (`commit`, `updateCommitted`, `tombstone`,
  `restore`) — proves the reactivity actually works, not just that the one-shot query result is
  correct.
- Drafts and tombstoned flights are excluded from `watchFlights` by default; `find` still
  returns a tombstoned flight; `watchDrafts`/`findDraft` return only drafts.
- `flightFromRow` round-trips every field `flightToRow` (M2) set — the mirror image of
  `flight_mapper_test.dart`, now checked in both directions on the same fixture flight.
- A flight whose `aircraftId` cannot be resolved throws the documented `StateError`.

## Non-goals

- Aggregate/total queries — that is `Projection.projectAggregate` (M1), called by whichever
  future screen needs a total, over whatever flight set this repository supplies. Not this
  repository's job to aggregate.
- Currency-rule evaluation (M3).
- The jurisdiction-comparison/badge UI (CLAUDE.md's multi-jurisdiction UX section) — a UI-layer
  concern that calls this repository twice, once per jurisdiction, and diffs the two
  `ProjectionResult`s itself.
- Pagination — not asked for, and not needed at this app's data volume yet.
