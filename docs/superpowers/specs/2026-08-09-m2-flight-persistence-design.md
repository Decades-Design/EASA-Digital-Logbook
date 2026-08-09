# M2 foundation: flight persistence, draft/committed states, and revisions — Design

**Status:** Proposed
**Date:** 2026-08-09
**Covers:** issues #31, #32, #33, #34
**Deferred to later specs:** #35 (read/query repository), #36 (migration framework), #37
(backup/restore), #38 (encryption spike), #39 (dev seed data) — each depends on this foundation
existing first.

## Context

M1 built the domain layer: `Flight`, `Aircraft`, `Aerodrome`/`AerodromeDirectory`, and the
projection engine that derives PIC/night/cross-country/instrument/multi-pilot time per
jurisdiction, all as pure Dart with no persistence. Nothing survives an app restart yet.

M2 gives `Flight` and `Aircraft` a real SQLite-backed home via `drift` (ADR-0006), and implements
the draft-until-exported, then-immutable lifecycle ADR-0003 already decided but never built:

> An entry is freely mutable in place until it is first included in a generated PDF export; at
> that point it is committed, and every subsequent change appends a delta revision retaining the
> prior state. Committed entries are never `UPDATE`d or `DELETE`d in place.

Rule 1 (CLAUDE.md) — raw facts only, never a derived quantity — applies to this schema exactly as
it applies to the domain model it mirrors. Rule 4 is ADR-0003, not the earlier unconditional
append-only statement it superseded.

## Scope

**#31's acceptance criteria ask for more tables than the app currently has domain models for.**
Checked against `lib/domain/model/` as it exists today:

| Asked for | Status | Decision |
|---|---|---|
| Flights | Built (`flight.dart`) | In scope |
| Aircraft | Built (`aircraft.dart`) | In scope |
| Aerodromes | The bundled ~85,000-row OurAirports dataset is a read-only asset loaded into memory at runtime (`AerodromeDirectory.fromOurAirportsCsv`), not user data — it does not belong in this database. What *does* need a table is the other half of #14's own requirement: aerodromes the pilot defines themselves (private strips, unlicensed fields) | In scope, narrowly — a `custom_aerodromes` table only |
| Crew | No domain model exists. `Flight` carries only two free-text fields (`otherPilotName`, `otherPilotCredentialNumber`) for the flight at hand — there is no reusable roster concept | Out of scope. Needs its own domain-model design first |
| Licences | No domain model exists — nothing represents "which licences the pilot holds," referenced only prospectively in CLAUDE.md ("one licence is marked primary") | Out of scope. Needs its own domain-model design first |
| FSTD sessions | `fstd.dart` models the simulator device only; its own doc comment states "the session entry that refers to this" is issue #28, which is on hold | Out of scope until #28 lands |

This spec's schema is therefore: **`flights`, `aircraft`, `custom_aerodromes`**, plus the child
and revision tables the flights schema itself needs.

## Schema

### General rule for nested domain structures

- A **single, always-present-together nested structure** (`PilotCapacity`, `CircuitCounts`,
  `InstructorPresence`, `Countersignature`) is **flattened onto the owning row** as extra
  columns. Each is small, fixed-shape, and never sensibly read apart from its parent — a join
  would buy nothing.
- A **variable-length list** (`Flight.route`, `Flight.approaches`,
  `Aircraft.requiredQualifications`) gets **its own child table**, one row per element, linked by
  a foreign key. This keeps the data queryable (e.g. "every flight that touched EGKA," or the
  FAA `§61.57(c)` approach-count currency rule in M3) rather than locked inside a blob.

### `flights`

One row per flight, current state only — see "Lifecycle" below for how edits to a committed row
work.

| Column | Type | Notes |
|---|---|---|
| `id` | integer, PK, autoincrement | |
| `aircraft_id` | integer, FK → `aircraft.id` | `Flight.aircraftRegistration` becomes a real foreign key here — the domain model's own comment already flags synthetic identity as "M2's concern" |
| `pre_planned_navigation` | bool | |
| `off_blocks` | integer (epoch ms, UTC) | |
| `on_blocks` | integer (epoch ms, UTC) | |
| `takeoff` | integer, nullable | |
| `landing` | integer, nullable | |
| `other_pilot_name` | text, nullable | |
| `other_pilot_credential_number` | text, nullable | |
| `carrying_passengers` | bool | |
| `takeoffs_day_full_stop` / `_day_touch_and_go` / `_night_full_stop` / `_night_touch_and_go` | integer | flattened `CircuitCounts` |
| `landings_day_full_stop` / `_day_touch_and_go` / `_night_full_stop` / `_night_touch_and_go` | integer | flattened `CircuitCounts` |
| `ifr_flight_plan_filed` | bool | |
| `actual_instrument_minutes` | integer | |
| `simulated_instrument_minutes` | integer | |
| `holding_procedures_count` | integer | |
| `tracking_performed` | bool | |
| `series_group_id` | text, nullable | |
| `airworthiness_basis` | text, nullable | enum stored as its name |
| `remarks` | text | |
| `capacity_command_authority` … `capacity_pic_intervention_not_required` | bool ×9 | flattened `PilotCapacity` booleans, one column per field |
| `capacity_manipulation_time_minutes` | integer, nullable | |
| `capacity_solo_endorsement_held` | bool, nullable | |
| `capacity_endorsing_instructor_name` | text, nullable | |
| `capacity_instructor_capacity` / `_influenced_flight` / `_name` / `_credential_number` / `_credential_expiry` | mixed, all nullable | flattened `InstructorPresence?` — null block when no instructor aboard |
| `capacity_other_pilot_role` | text, nullable | |
| `capacity_countersignature_status` / `_signatory_name` / `_signatory_credential_number` / `_signatory_credential_expiry` / `_signed_at` | mixed, all nullable | flattened `Countersignature?` |
| `committed_at` | integer, nullable | **null = draft, non-null = committed**, and records when |
| `tombstoned_at` | integer, nullable | **null = active, non-null = deleted-but-retained** (committed entries only — see "Deletion") |

`*_credential_expiry` columns use the `CalendarDate` type #29 built specifically for this —
no time-of-day component, exactly what a credential expiry is.

### `flight_route_legs`

`id` (PK) · `flight_id` (FK) · `sequence` (integer, order in the route) · `identifier` (text)

### `flight_approaches`

`id` (PK) · `flight_id` (FK) · `type` (text) · `aerodrome_icao` (text) · `runway` (text) ·
`count` (integer)

### `flight_revisions`

One row per **edit event** on a committed flight, not one row per changed field — #32 asks for a
timestamp and an optional reason per revision, and both apply to the whole edit, not to
individual fields.

| Column | Type | Notes |
|---|---|---|
| `id` | integer, PK | |
| `flight_id` | integer, FK | |
| `recorded_at` | integer (epoch ms) | |
| `kind` | text: `edit` \| `tombstone` \| `restore` | so the revision viewer (#34) can distinguish these without inferring from which fields changed |
| `reason` | text, nullable | free text |
| `changed_fields` | text (JSON) | `{"field_name": old_value, ...}` for whichever columns changed — only the old values are stored; current values live in the `flights` row itself |

Reconstructing a flight's state as of some past instant: start from the current `flights` row,
then walk `flight_revisions` for that `flight_id` newer than the target instant, in reverse
order, applying each revision's old values back over the current ones.

### `aircraft`

Plain reference data — no lifecycle, no revisions. `Aircraft`'s own dartdoc already establishes
it as "a current, editable reference record," unlike a flight.

`id` (PK) · `registration` (text, unique) · `manufacturer` · `model` ·
`icao_type_designator` (nullable) · `category` (text) · `engine_type` (text) · `engine_count`
(integer) · `operating_surface` (text) · `requires_multi_crew` (bool) ·
`type_rating_designator` (text, nullable)

### `aircraft_qualification_jurisdictions` and `aircraft_required_qualifications`

`Aircraft.requiredQualifications` is `Map<String, Set<AircraftQualification>>`, and the domain
model deliberately distinguishes **an absent jurisdiction key** ("never set up for this
authority") from **a present, empty set** ("set up, and requires nothing") —
`aircraft_test.dart` has a dedicated test proving this matters. A single child table of
`(aircraft_id, jurisdiction_id, qualification)` triples can't express that distinction on its
own: an aircraft set up with zero requirements would have no rows at all, indistinguishable from
one never set up. Two tables:

- `aircraft_qualification_jurisdictions`: `aircraft_id` (FK) · `jurisdiction_id` (text) — one row
  per jurisdiction this aircraft has been configured for, present even if it requires nothing.
- `aircraft_required_qualifications`: `aircraft_id` (FK) · `jurisdiction_id` (text) ·
  `qualification` (text) — one row per actual requirement.

### `custom_aerodromes`

`id` (PK) · `icao_code` (text, nullable) · `iata_code` (text, nullable) · `name` (text) ·
`latitude` / `longitude` (real) · `elevation_ft` (integer, nullable) · `iso_country` (text,
nullable). Plain reference data, same as `aircraft` — no lifecycle.

## Lifecycle

**Draft.** `committed_at IS NULL`. Freely edited in place via ordinary `UPDATE`; no revision
written. Deleting a draft removes the row (and its `flight_route_legs`/`flight_approaches`
children) outright.

**Committing.** A `commit(flightId)` repository method sets `committed_at` to now. This spec
builds the mechanism only; the *caller* — the future PDF export flow — is M6's concern per
ADR-0003 ("An entry becomes committed when it is first included in a printed or exported PDF").

**Editing a committed flight.** One atomic transaction: (1) read the current row, (2) diff the
incoming change against it, (3) write a `flight_revisions` row of kind `edit` capturing the old
values of whatever changed, (4) `UPDATE` the `flights` row to the new values. All four steps
happen inside the repository; nothing else is allowed to write to `flights`.

**Deleting a committed flight.** Sets `tombstoned_at` to now and writes a `tombstone`-kind
revision. The row and its children are retained, not removed. Every read that feeds a total,
currency evaluation, or a projection filters `WHERE tombstoned_at IS NULL` by default.

**Restoring.** Clears `tombstoned_at` and writes a `restore`-kind revision. Available from the
revision viewer, per #34.

## Repository (write side only)

Per #32's "no raw DAO bypasses the state machine," the generated Drift DAO for `flights` is never
exposed outside a `FlightRepository` (interface in `lib/domain/`, implementation in
`lib/data/` — matching the layering CLAUDE.md's architecture diagram already establishes). This
spec's repository surface:

```dart
Future<int> createDraft(Flight flight, {required int aircraftId});
Future<void> updateDraft(int flightId, Flight flight);
Future<void> deleteDraft(int flightId);

Future<void> commit(int flightId);
Future<void> updateCommitted(int flightId, Flight flight, {String? reason});
Future<void> tombstone(int flightId, {String? reason});
Future<void> restore(int flightId, {String? reason});
```

Read/query methods (by date range, by aircraft, jurisdiction-projected results, streaming
updates) are #35's job, once this exists to build on.

## Testing

Against a real in-memory Drift database (`NativeDatabase.memory()`), not a mock — matching how
the rest of this codebase tests against real behaviour rather than a substitute for it. At
minimum:

- A generated-schema sweep that fails if any column name matches a derived-quantity pattern
  (the same regex family `fixture_loader_test.dart` already uses for fixtures) — the enforcement
  mechanism #31 asks for.
- Draft create/edit/delete writes no revision.
- Committing a draft sets `committed_at` and nothing else changes.
- Editing a committed flight writes exactly one `edit` revision with the correct old values, and
  the `flights` row reflects the new values.
- Tombstoning and restoring a committed flight: revision kind, `tombstoned_at` state, and that a
  tombstoned flight is excluded from a basic "all active flights" query.
- Reconstructing historical state across two or more chained revisions.
- The jurisdiction/qualification absent-vs-empty distinction survives a round trip through
  `aircraft_qualification_jurisdictions`/`aircraft_required_qualifications`.

## Non-goals (this spec)

- Crew, Licences, FSTD sessions — no domain model to persist yet.
- The bundled OurAirports dataset — stays a runtime-loaded asset, not a table.
- Read/query repository methods, jurisdiction-projected reads, reactive/streaming queries (#35).
- Schema migrations — this is v1; nothing exists yet to migrate from (#36).
- Backup/restore, encryption at rest, dev seed data (#37, #38, #39).
