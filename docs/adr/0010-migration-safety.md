# ADR-0010: Two-layer migration safety, backup scoped to migration only

**Status:** Accepted
**Date:** 2026-08-09

## Context

The database holds the pilot's legal record. A botched schema migration is data loss a fresh
install cannot recover from — #36's whole premise. Two related decisions needed settling before
building the migration framework: how many layers of protection a migration gets, and whether
the pre-migration backup this needs is the same thing as #37's (not yet designed) backup/restore
feature.

## Decision

Two independent layers protect a migration, not one:

1. SQLite's own transactional DDL — a migration step that throws partway through already rolls
   back at the SQL level, restoring the pre-migration schema and data with no extra code.
2. A file-level backup (`lib/data/open_with_backup.dart`), copied before opening/migrating and
   restored on any exception. This covers what a transaction can't: the app being killed
   mid-write, or a migration that throws no exception but is simply wrong.

The backup is internal-only — no restore UI, no retention policy, not #37. #37 designs its own
user-facing backup/restore feature later, informed by nothing this ADR commits to.

## Alternatives considered

Relying on SQL transactional rollback alone. Rejected: it protects against a migration that
*fails loudly*, not one that fails silently or is interrupted by the process dying — exactly the
failure modes a legal record on a personal device is most exposed to (a phone losing power or an
OS killing the app mid-write).

Building the file backup as a first cut of #37's general backup/restore feature. Rejected: #37
has no design yet, and guessing at its shape now risks building the wrong reusable primitive
before the actual requirements (retention, restore UI, what "a backup" even means to a pilot) are
known. Keeping this one purpose-built and narrow costs nothing and commits to nothing.

## Consequences

`openAppDatabase`/`openWithBackup` is the only sanctioned way to open the real database file —
any other call site that constructs `AppDatabase(NativeDatabase(file))` directly bypasses the
safety net. #37, whenever it happens, is free to design its own thing without being constrained
by this one.

**Record here, from implementation:** the migration mechanism (schema versioning, `onUpgrade`,
the CI snapshot check) is proven against a throwaway fixture schema under `test/`, not a real
`AppDatabase` change — `AppDatabase` had nothing pending to migrate when this was built. Also,
generating the real v1 schema snapshot (`dart run drift_dev schema dump`) required pinning
`drift` to exactly `2.34.0` — `drift_dev` 2.34.0's schema-dump command is incompatible with
`drift` 2.34.3's `drift3_preview` module, and `drift_dev` can't be upgraded past 2.34.0 without
conflicting with the `freezed` 3.2.5 pin from ADR-0006. See the comment on the `drift` dependency
in `pubspec.yaml` for the full chain.
