# ADR-0013: Crash safety — WAL, synchronous=FULL, and the transaction rule

**Status:** Accepted
**Date:** 2026-09-29

## Context

The database is the pilot's only copy of a legal record (ADR-0005, offline-first). #90 required
making three things explicit that were previously either accidental or unaudited: which journal
mode and fsync discipline SQLite runs under, whether every multi-statement write is atomic, and
what a future multi-step write method must do to stay that way.

## Decision

**`journal_mode = WAL`, `synchronous = FULL`**, set in `AppDatabase.migration.beforeOpen`
(`lib/data/database.dart`), alongside the existing `PRAGMA foreign_keys = ON`. WAL over the
rollback-journal default because it survives a killed process the same way and, as a side effect,
lets a reader run concurrently with a writer. `FULL` over WAL's own `NORMAL` default because
`NORMAL` can lose the most-recently-committed transaction on a hard power cut (never corrupt the
database, just lose a write) — acceptable for most apps, not for a flight logbook. The write volume
here (a pilot logging flights by hand) is nowhere near where `FULL`'s extra fsync is felt.

**A write touching more than one table, or more than one row of the same table in a loop, is
wrapped in `_db.transaction()`.** A single `INSERT`/`UPDATE`/`DELETE` statement is already atomic
by construction and needs no wrapper — including a delete that looks like it touches two tables
but is actually one `DELETE` relying on `ON DELETE CASCADE` (`FlightRepository.deleteDraft`, whose
child rows the `flights`→`flight_route_legs`/`flight_approaches` foreign keys cascade away as part
of the same single statement). `_db.transaction()` calls nest cleanly — a transaction opened from
inside another already-open one runs in the outer one rather than starting a second
(`DriftFlightRepository.applyImportBatch` calling `createDraft` in a loop, and
`DriftExportSealingCoordinator` composing two different repositories' transactional methods, both
rely on this).

**Audit result as of this ADR** — every current multi-step write method, and why it's safe:

| Method | Tables/rows touched | Safe because |
|---|---|---|
| `FlightRepository.createDraft` | flight + route legs + approaches | `_db.transaction()` |
| `FlightRepository.updateDraft` | flight + route legs + approaches | `_db.transaction()` |
| `FlightRepository.updateCommitted` | flight + revision + route legs + approaches | `_db.transaction()` |
| `FlightRepository.tombstone` | flight + revision | `_db.transaction()` |
| `FlightRepository.restore` | flight + revision | `_db.transaction()` |
| `FlightRepository.sealForExport` | N flights, loop | `_db.transaction()` |
| `FlightRepository.applyImportBatch` | batch + N flights (nested `createDraft`) | `_db.transaction()`, nested |
| `FlightRepository.undoImportBatch` | batch + N flights (nested `deleteDraft`/`tombstone`) | `_db.transaction()`, nested |
| `DriftExportSealingCoordinator.recordExportAndSeal` | export record + N flights (two repositories) | `_db.transaction()`, nested |
| `AircraftRepository.upsert` | aircraft + qualification jurisdiction/requirement rows | `_db.transaction()` |
| `FlightRepository.deleteDraft` | flight (route legs/approaches cascade) | single statement + FK cascade |
| every other repository's `upsert`/`delete` | one table, one row | single statement |

## Alternatives considered

`synchronous = NORMAL`, SQLite's own recommended default for WAL. Rejected for the reason above:
this database is a legal record, not a cache.

Auditing by adding a generic "every write goes through a `TransactionAudit` wrapper" abstraction
that would refuse to compile an unwrapped multi-statement write. Rejected as premature machinery
for eight call sites in one file's worth of repositories — a written rule plus regression tests
that would fail if one of them regressed is enough; revisit if the repository count grows enough
that a human audit stops being reliable.

## Consequences

A future multi-step write method that skips `_db.transaction()` is a bug this ADR gives a name and
a rule to check against, but nothing enforces it automatically — code review is the guard, same as
the "only `FlightRepository` writes `flights`" convention it sits next to.

WAL adds `-wal`/`-shm` sidecar files next to the database file. `database_backup.dart`'s
`restoreDatabaseBackup` already had to clear a stale `-journal` sidecar before replacing the live
file (a crash-recovery file surviving from before the file it's next to gets replaced would
confuse SQLite into thinking a crash needs recovering against data that was never mid-write); it
now clears `-wal`/`-shm` too, for the same reason under the new journal mode.
