# Crash safety and write durability — Design

**Status:** Proposed
**Date:** 2026-09-20
**Covers:** issue #90
**Depends on:** ADR-0010 (migration safety net, `open_with_backup.dart`), ADR-0011 (backup format,
`database_backup.dart`), #56 (live `AppDatabase` wiring — now closed, meaning the stale "Available
once live data exists" comment on Settings' Backup row can finally be replaced with something
real).

## Context

The database is the pilot's only copy of the legal record (offline-first, ADR-0005). #90's five
acceptance criteria split into two groups: **provable durability** (transactions, WAL, a real
crash test) and **recoverability when durability wasn't enough** (corruption detection, restore).

An audit of every repository's write methods (`lib/data/repositories/*.dart`) found no gap:
`FlightRepository`'s multi-step methods and `AircraftRepository.upsert` are already wrapped in
`_db.transaction()`; single-table repos are one SQL statement each, atomic by construction;
`deleteDraft` looks like two writes but is one `DELETE` relying on FK `ON DELETE CASCADE`. AC1 is
about proving and recording this, and closing the gap between "wrapped in a transaction" (true
everywhere) and "proven atomic under a forced failure" (true in only 2 of ~8 multi-step methods
today).

No journal mode or synchronous PRAGMA is configured anywhere — SQLite's defaults apply
(rollback-journal, `synchronous=FULL` is actually SQLite's *default* outside WAL, but journal mode
itself is unset, and nothing states the intended mode explicitly). AC2 makes the choice explicit
and deliberate rather than accidental.

There is currently no restore UI. Settings' "Backup & encryption" row is an inert stub. Issue #37
(backup/restore) is marked closed on GitHub, but its own acceptance criteria for a restore UI,
share-sheet integration, and a backup reminder don't appear built — #90's AC5 unavoidably picks up
the restore-UI half of that gap, since "a route to restoring from backup" has nowhere to route to
otherwise. This design deliberately builds a *minimal* restore flow to satisfy AC5, not the full
#37 feature (share-sheet export, reminder banner) — those stay #37's to finish.

## Scope decisions

- **WAL + `synchronous=FULL`**, not `NORMAL`. This is a legal record; a lost committed flight
  (possible under NORMAL on a hard power cut, though never corruption) is not acceptable even
  though it costs some write latency. Applied in `AppDatabase.migration.beforeOpen`, which already
  runs on every open (fresh install, upgrade, and post-restore reopen alike).
- **`restoreDatabaseBackup` must also clear stale `-wal`/`-shm` sidecars**, not just `-journal` —
  WAL mode's crash-recovery files, currently unhandled since the code predates this change.
- **Transaction audit is a written record (ADR), not new production code** — the audit found
  nothing to fix. What's added is regression-test coverage for multi-step methods that don't yet
  have an atomicity-under-failure test, and the ADR itself as the artifact recording *why* each
  method is or isn't wrapped (so a future contributor adding a ninth multi-step method has a
  documented pattern to follow, per CLAUDE.md's "comment beside the code it explains").
- **A real subprocess-kill test, not a synthetic torn-write simulation.** A helper script
  (`test/support/crash_kill_helper.dart`) opens a DB at a path given on argv, starts a transaction,
  writes, and signals readiness; the test spawns it, waits for that signal, then
  `Process.kill(ProcessSignal.sigkill)`. Reopening the DB afterwards must show no partial write.
  `applyImportBatch` gets the same treatment for AC4, writing several rows before the kill.
- **A new automatic local safety snapshot, distinct from #37's user-triggered export.** Taken via
  `VACUUM INTO` on each clean app startup (rotating — see Architecture piece 4), kept locally,
  never share-sheeted. This is what gives AC5's "route to restoring from backup" something to
  restore *from* for a pilot who's never manually backed up. It does not replace or extend
  `open_with_backup.dart` (ADR-0010's migration-only net stays exactly as scoped) or #37's format
  (ADR-0011) — it's the same `VACUUM INTO` mechanism, a different trigger and retention story.
- **Not building:** #37's share-sheet export, backup reminder banner, or "back up now" button —
  those stay #37's own follow-up. Any change to `openWithBackup`'s migration-scoped behavior.
  Performance tuning of `integrity_check` at scale (#89's territory once there's a 10k-flight
  benchmark to tune against).

## Architecture

Five pieces.

### 1. Database configuration

```dart
beforeOpen: (details) async {
  await customStatement('PRAGMA foreign_keys = ON');
  await customStatement('PRAGMA journal_mode = WAL');
  await customStatement('PRAGMA synchronous = FULL');
},
```

`journal_mode = WAL` is sticky (persisted in the database file header) but setting it every open is
harmless and keeps behavior explicit rather than relying on whatever a previous version left
behind. `synchronous` is a per-connection setting and must be set every open.

### 2. Transaction audit

`docs/adr/0013-crash-safety.md` (numbering continues from 0012) records: the PRAGMA choices and
why; the full list of multi-step write methods and, for each, either "wrapped in `_db.transaction`"
or the specific reason a transaction isn't needed (single statement, or FK cascade); the rule for
future methods ("a write touching more than one table, or more than one row in a loop, is wrapped
in `_db.transaction`").

New atomicity-under-failure tests, one per multi-step method lacking one: force a throw partway
through (an invalid FK reference, or a second call that violates a constraint — whatever's least
invasive per method) and assert the database is completely unchanged from before the call.

### 3. Crash-kill test harness

`test/support/crash_kill_helper.dart` — a standalone entrypoint (not part of the app), invoked as
a subprocess:

```
dart test/support/crash_kill_helper.dart <db-path> <mode>
```

`mode` selects what it does mid-transaction (`single-write`, `import-batch`) so both AC3 and AC4
reuse one helper. It opens the DB the same way the app does (WAL + synchronous=FULL, so the test
proves the *configured* durability, not a default), starts the write inside `_db.transaction()`,
and prints a `READY` line to stdout once the write has been issued but before the transaction
would naturally complete (a short artificial delay after the write, before returning, gives the
test a reliable window to kill it in).

The test (`test/data/crash_kill_test.dart`):
1. Spawns the helper via `Process.start`, pointed at a temp file.
2. Reads stdout until it sees `READY`.
3. Kills the process (`ProcessSignal.sigkill`; Windows uses `taskkill /F` under the hood via
   `Process.killPid` — handled once in a small platform-check helper).
4. Reopens the DB via the app's real `openAppDatabase`/`AppDatabase` construction path.
5. Asserts: the DB opens without throwing, `PRAGMA quick_check` returns `ok`, and the row(s) the
   helper was mid-write on are absent.

### 4. Automatic local safety snapshot

A new small module, `lib/data/crash_recovery_snapshot.dart`: on `openRealAppDatabase`, *after* a
successful open and integrity check (piece 5), take a `VACUUM INTO` snapshot to a fixed path
(`<app-support>/crash_recovery_backup.sqlite`), overwriting the previous one — one rotating slot,
not a history, since this is a safety net for "something to restore from," not a retention policy
(#37's eventual export is where retention belongs). Cheap and fire-and-forget: failure to snapshot
is logged, never blocks or fails startup.

### 5. Corruption detection and recovery screen

`openRealAppDatabase` (or a thin wrapper around it) runs `PRAGMA quick_check` immediately after
opening. A result other than `ok`, or any exception during open/check, means corruption.
`main()` catches this and, instead of `runApp(App())`, runs a small standalone recovery app:

- Explains what happened in plain language.
- **Restore from automatic snapshot** (piece 4's file), shown only if it exists, with its
  timestamp — one tap.
- **Restore from a file I choose** — opens the platform file picker (reusing `FilePicker`, already
  a dependency per the AMC1 FCL.050 export screen) for a backup the pilot exported via #37.
- Either path calls `restoreDatabaseBackup`, then attempts to reopen normally; on success, proceeds
  into the real app; on failure, stays on the recovery screen with the new error rather than
  silently retrying forever.

## Testing plan

- PRAGMA values: a test opening an `AppDatabase` against a real temp file (not
  `NativeDatabase.memory()` — SQLite silently ignores `journal_mode=WAL` for `:memory:` databases,
  reporting `memory` instead) and querying `PRAGMA journal_mode` / `PRAGMA synchronous`, asserting
  `wal` / `2` (FULL).
- `restoreDatabaseBackup` clears `-wal`/`-shm` siblings: extend the existing "replaces an existing
  live file and its stale journal" test with WAL-sidecar variants.
- New atomicity-under-failure tests per piece 2.
- The two real subprocess-kill tests per piece 3 (AC3, AC4).
- `crash_recovery_snapshot`: a snapshot is taken on open and overwrites the previous one; a
  snapshot failure doesn't prevent the app from opening.
- Corruption detection: a deliberately truncated/garbage `.sqlite` file triggers the recovery path
  instead of a crash; a clean database does not.
- Recovery screen: widget test — snapshot restore path and file-picker restore path each lead back
  into the normal app on success; a bad chosen file keeps the pilot on the recovery screen with an
  error rather than looping silently.

## Open items for the implementation plan

- Exact file/class names for the recovery screen and its providers.
- Whether `Process.kill`'s Windows behavior needs a `taskkill /F` fallback or whether
  `ProcessSignal.sigkill` is sufficient under the `dart:io` implementation this SDK ships —
  confirm during implementation rather than guessing here.
- ADR numbering: confirm `0013` is still free at implementation time (no ADRs merge between now
  and then, but worth a final check).
