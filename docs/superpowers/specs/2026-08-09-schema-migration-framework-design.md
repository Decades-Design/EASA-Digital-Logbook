# Schema migration framework — Design

**Status:** Proposed
**Date:** 2026-08-09
**Covers:** issue #36
**Depends on:** the M2 persistence foundation (merged) and its `AppDatabase` at `schemaVersion 1`.

## Context

The database holds the pilot's legal record. A botched migration is data loss a fresh install
can't recover. #36 asks for the machinery to make schema changes safe: versioned snapshots,
migration tests, a pre-migration safety copy, CI enforcement, and rollback on failure.

`AppDatabase` has never had a schema change — it's still v1, so there is no real v(n-1)→v(n)
transition to build the testing machinery against yet.

## Scope decisions

- **The pre-migration backup is internal-only**, not #37 (backup/restore). No restore UI, no
  retention policy — a private helper that copies the db file before migrating and deletes the
  copy on success. #37 designs its own user-facing thing later, unconstrained by this.
- **The migration mechanism is proven against a test-only fixture schema**, not a real
  `AppDatabase` change. `AppDatabase` stays at v1; the scaffolding (versioning, the backup
  wrapper, the CI check) is wired up and ready for whenever a real v2 change actually happens.

## Architecture

Four pieces:

1. **Schema versioning + committed snapshots.** `drift_dev`'s schema-dump tooling generates a
   versioned JSON snapshot into `drift_schemas/drift_schema_v<N>.json`. Unlike generated
   `.g.dart` files, these are committed — they're the only record of what an old schema actually
   looked like, and can't be regenerated once the code has moved past that version.
2. **Migration steps.** `AppDatabase.migration`'s `MigrationStrategy.onUpgrade` uses Drift's
   `stepByStep()` helper — one function per version transition. Currently zero steps; a valid,
   safe no-op scaffold since `stepByStep()` never fires until `schemaVersion` actually bumps.
3. **File-backup + rollback wrapper.** A new `openAppDatabase(File dbFile)` — the first thing in
   this project that opens a database against a real file rather than `NativeDatabase.memory()`,
   since M2 deliberately left real file-path wiring out of scope. Copies `dbFile` to a temp path
   before opening (which triggers any pending migration), deletes the copy on success, restores
   from the copy and rethrows on any exception. SQLite's own transactional DDL already rolls back
   a migration that throws partway through at the SQL level; this covers what a transaction can't
   — the app being killed mid-write, or a migration that throws no exception but is wrong.
4. **CI enforcement.** `tool/check_schema_snapshot.dart`, matching the existing
   `check_layering.dart`/`check_domain_coverage.dart` pattern: dumps the current schema, diffs it
   against the committed snapshot for the current `schemaVersion`, fails the build if they
   disagree — the signal that a table changed without a version bump and a fresh snapshot.

## Proving the mechanism: a test-only fixture schema

```
test/data/migration_fixture/
  fixture_database.dart       # 2 tables, schemaVersion 1 and 2 both defined
  fixture_database_test.dart  # proves the mechanism works
```

`FixtureDatabase` is a small, throwaway schema with its own `drift_schemas/` snapshots (v1, v2)
and a real `stepByStep(from1To2: ...)` migration — e.g., a `notes` column that's `TextColumn`
required in v1 and nullable in v2, small enough to reason about but real enough to prove data
survives a genuine ALTER. Tests prove, against this fixture:

- Opening a v1-shaped database file, migrating to v2, and asserting the data survived correctly.
- A migration that throws partway through leaves the original file's data intact.
- The pre-migration backup file exists during migration and is gone afterward on success.

## Testing

- The fixture-schema tests above (the core "does the mechanism work" proof).
- `check_schema_snapshot.dart` tests: a schema changed without a matching snapshot → fails; a
  matching snapshot → passes. Same style as the existing `check_*` guard tests.
- `openAppDatabase` tests use a real temp file-backed `NativeDatabase`, not memory — copying a
  file only means something for a file-backed database.

## Non-goals

- User-facing backup/restore UI, retention policy (#37).
- Any real `AppDatabase` schema change (nothing is pending; the next one just follows this
  now-proven pattern).
- Encryption at rest (#38).

## ADR

A new ADR records the two-layer rollback strategy (SQL transaction + file backup) and the
internal-only backup scope decision — a call that's expensive to reverse once real user data
exists on a real device.
