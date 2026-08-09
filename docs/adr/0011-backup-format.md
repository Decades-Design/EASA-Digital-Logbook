# ADR-0011: Backup format is the live SQLite file, via `VACUUM INTO`

**Status:** Accepted
**Date:** 2026-08-09

## Context

#37 needs a backup file format that includes every flight, its full revision history, and its
draft/committed/tombstoned state, and that stays restorable as the schema evolves. ADR-0010
deliberately left this undesigned, on the grounds that guessing at it while building the
migration framework risked baking in the wrong shape.

## Decision

A backup is an ordinary SQLite file — the database file itself, produced by SQLite's
`VACUUM INTO`. Not a custom JSON/zip export, not a subset of tables.

This works because the live database already *is* the complete legal record: `flights`,
`flight_revisions`, `committed_at`/`tombstoned_at`, `aircraft`, `custom_aerodromes` — nothing is
summarized or derived on the way in. `VACUUM INTO` produces a transactionally consistent copy
without needing exclusive access to the live connection, unlike a raw file copy taken while a
connection might be mid-write.

Versioning is free, not bolted on: SQLite's `user_version` pragma is drift's `schemaVersion`, so
an old backup restored years from now is opened exactly the way an old on-device database is
opened today — through `openAppDatabase`, running whatever migrations #36's framework has
accumulated by then. There is no second version number to keep in sync with the schema.

Implementation: `lib/data/database_backup.dart`. `exportDatabaseBackup` wraps `VACUUM INTO`.
`restoreDatabaseBackup` replaces the live file (clearing any stale rollback-journal sidecar) and
leaves reopening it — and therefore migrating it — to the caller via `openAppDatabase`.

## Alternatives considered

A custom export format (JSON rows, or a zip of JSON plus a manifest). Rejected: it would
duplicate the schema in a second, hand-maintained shape, and every future migration would need a
second migration path written for the export format alongside the real one. The SQLite file
already has an evolution story; reusing it means #36's migration framework *is* the backup format's
migration framework, with no separate code path to keep correct.

A raw file copy of the live `.sqlite` file instead of `VACUUM INTO`. Rejected: safe only if the
database is guaranteed closed or quiescent at the moment of copy, which a "back up now" action
triggered from a live app cannot guarantee. `VACUUM INTO` is SQLite's own answer to taking a
consistent snapshot without that guarantee, and as a side effect produces a defragmented,
minimum-size file.

## Consequences

A backup's integrity is exactly SQLite's file-format integrity — no redundant encoding, no
second format to validate independently. Restoring an old backup depends on the migration
framework being able to carry it forward, so a migration that only handles the *previous* schema
version rather than *any* older one would silently break restoring a very old backup; #36's
migrations must stay cumulative.

Share-sheet delivery of the backup file and an in-app "back up now"/reminder UI are not part of
this decision — there is no app UI yet (M4). `isBackupOverdue` in `database_backup.dart` is the
pure decision logic for the reminder, written now and left for M4 to call from an actual screen.
