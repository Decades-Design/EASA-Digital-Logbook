# Export sealing — Design

**Status:** Proposed
**Date:** 2026-09-14
**Covers:** issue #83
**Depends on:** #76-#80 (AMC1 FCL.050 PDF export, closed), the existing draft/committed
state machine (`FlightsTable.committedAt`), and `DriftExportRecordRepository`
(the export-history ledger from #70/#73).

## Context

`docs/adr/0003-draft-until-exported.md` (Accepted) states the intended design plainly in its
own Consequences section: *"Export becomes a state transition with side effects — it commits
every draft entry included in the export — rather than a pure read of already-final data."*
That transition has never been built. Nothing in the codebase calls `commit()` from an export
path today.

**A pre-existing wrinkle the design has to account for.** `commit()` is already called from one
place: `lib/ui/entry/new_flight_screen.dart`'s "log this flight now" action (#58), which commits
a flight immediately on manual save, with no export involved. So `committedAt != null` does
**not** mean "was exported" — a flight can be committed and never printed. #83's own acceptance
criteria already scope around this correctly ("every **draft** flight included... transitions to
committed" — an already-committed flight is included as read-only content, untouched). The
design needs a marker distinct from `committedAt` for "which export, if any, sealed this flight."

**Also new to this issue** (confirmed with the user during brainstorming, not in the original
issue text): running totals must continue across separate export runs — a July export's brought-
forward must reflect everything committed before July, not restart at zero — computed from *all*
committed flights before the range, regardless of how each became committed. This connects to,
but is broader than, #81 ("opening balance from a prior paper logbook"): #81 is one additional
fixed figure layered on top of what this issue already has to compute from existing data.

## Scope decisions

- **Opening balance = every committed, non-tombstoned flight with date before the range**, not
  only flights previously sealed by a PDF export. A flight committed via #58 and never printed
  still flew, and still counts toward the pilot's real total time to date.
- **No join table.** A flight is sealed by at most one export, ever — committed entries are
  immutable going forward, so `FlightsTable.sealedByExportId` (nullable, set exactly once) is
  sufficient. "Which flights did export X seal" is `WHERE sealedByExportId = X`.
- **Preview and the real seal share one read path.** Both compute the same row selection and
  opening balance; only the DB-writing seal step and the watermark differ. What a pilot previews
  is exactly what sealing would produce.
- **#81 (paper-logbook opening balance) stays out of scope here**, but the interface is built to
  take it later without another redesign — see Architecture, piece 4.
- **Not building:** a UI entry point beyond a minimal new screen (visual polish, the eventual
  "fifth tab" from `app_shell.dart`'s own reserved-slot comment, is a separate concern); any
  change to the ForeFlight/CSV export screen; any change to #58's own commit-on-save behavior,
  which this design treats as a pre-existing, valid, independent path to `committedAt`.

## Architecture

Four pieces, split so the parts that matter most for correctness are plain-Dart testable without
a widget tree — the same shape #77-#80 already used successfully.

### 1. Data model

One migration, `schemaVersion` 9 → 10:

```dart
TextColumn get sealedByExportId =>
    text().nullable().references(ExportRecordsTable, #id)();
```

on `FlightsTable`. Null for every flight today and for any flight committed via #58 without ever
being exported; set exactly once, at the moment a draft is sealed by a specific export. A
`stepByStep()` migration step; regenerate `drift_schemas/drift_schema_v10.json` per
`check_schema_snapshot.dart`'s existing convention.

### 2. Read-side orchestration (plain Dart, no I/O side effects)

A new class, `Amc1Fcl050ExportPlan` (exact name/file TBD at planning time — likely
`lib/export/amc1_fcl050_export_plan.dart`), built from a date range plus the flight
repositories:

1. Query committed, non-tombstoned flights with date `< rangeFrom` → map each through the
   existing `buildAmc1Fcl050Row` → `Amc1Fcl050Totals.fromRows` → **opening balance**.
2. Query committed, non-tombstoned flights with date in `[rangeFrom, rangeTo]` → **content
   rows** (mix of already-committed and about-to-be-sealed), sorted chronologically by
   `offBlocks` — the same field the row mapper already formats into group 1's printed date, and
   the same "date" basis both range queries filter on.
3. Of the content rows, the subset still `draft` → **flights to seal**, and its count is what
   the confirmation dialog names.
4. `buildAmc1Fcl050Logbook` (see piece 4) turns the content rows plus the opening balance into
   PDF bytes, in either preview or sealed-destined form — the plan doesn't know or care which;
   that distinction is the caller's, made in piece 3.

Every one of these is a value the existing test-first pattern already knows how to check without
touching a database for real (an in-memory drift database, as the rest of the data-layer tests
already use).

### 3. Sealing transaction & atomicity

Ordering, to satisfy "either the PDF was produced and everything in it is sealed, or neither":

1. Build the PDF bytes in memory via the plan above (pure — can't leave partial state).
2. Write the file to disk. Throws → abort. Nothing is sealed.
3. Only once the file write succeeds: one `_db.transaction` (the same primitive
   `applyImportBatch`/`undoImportBatch` already use) that:
   - creates the `ExportRecordsTable` row (`recordExport`, extended to return the new id),
   - for every flight in "flights to seal": `commit(flightId)` + sets `sealedByExportId` to the
     new export record's id.

Already-committed flights in range are read for content only — this transaction never touches
them. That is what makes **re-exporting an already-sealed range a no-op state-wise**: zero
flights to seal still runs the transaction (a fresh ledger entry, consistent with the existing
overlap-warning semantics from #70/#73) but seals nothing.

The one gap a filesystem and a database can't share a true transaction across: a file that saves
successfully followed by a DB failure. The user sees an error and can retry (a fresh file,
nothing was sealed) — an accepted, documented limit, not a silent failure.

New repository surface (on `FlightRepository`/`DriftFlightRepository`, the only place allowed to
write `FlightsTable` per its own existing dartdoc convention):

```dart
Future<void> sealForExport({
  required List<String> flightIds,
  required String exportRecordId,
});
```

### 4. Preview / watermark mode

`buildAmc1Fcl050Logbook` gains two new parameters:

```dart
Future<pw.Document> buildAmc1Fcl050Logbook({
  required String holderName,
  required String holderLicenceNumber,
  required List<Amc1Fcl050Row> rows,
  Amc1Fcl050Totals openingBalance = Amc1Fcl050Totals.zero,  // #83; #81 layers on top later
  bool isDraftPreview = false,                               // #83
})
```

`openingBalance` seeds the first spread's brought-forward in `_spreadTotals` instead of always
starting at zero — the only change #77's existing machinery needs. `isDraftPreview: true`
overlays a large, rotated, semi-transparent "DRAFT — NOT SEALED" watermark on every page (front
matter, address page, every entry-spread page) via a `pw.Stack` wrapping the existing page
content. Preview mode calls the same read-side plan (piece 2) and never calls the seal method
(piece 3) — no database writes at all.

### 5. UI

One new screen, following the existing ForeFlight export screen's pattern closely: date-range
pickers → overlap warning (`ExportRecordRepository.findOverlapping`, filtered to the AMC1
FCL.050 format) → two actions:

- **Preview** — always available; generates the watermarked PDF to a file the pilot picks; no
  state change.
- **Export & Seal** — a confirmation dialog first, naming the draft count ("This will seal N
  draft flight(s) as committed and immutable. This cannot be undone."), then proceeds through
  piece 3. Self-explanatory when N is 0 (a pure re-export/re-print).

## Testing plan

- **Migration**: v9→v10 adds the nullable column without disturbing existing data (matches
  `test/data/database_migration_test.dart`'s existing pattern).
- **`sealForExport`**: seals exactly the flights passed; a flight not passed (outside range, or
  already committed) is left completely untouched (`committedAt`, `sealedByExportId` unchanged).
  Wrapped in one transaction.
- **Read-side plan**: opening-balance sum correctness; content-row date-range inclusiveness
  (boundary dates included); draft-count correctness.
- **`openingBalance` threading**: the first spread's brought-forward reflects the passed-in
  value rather than zero — extends #77's existing `amc1Fcl050SpreadTotals` test pattern.
- **The three literal acceptance-criteria tests**: export seals exactly the flights in range,
  not flights outside it; a failed export (simulate the file-write step failing) seals nothing;
  calling seal twice on an already-sealed range changes no additional state.
- **UI**: a basic smoke test for the screen (renders, shows the draft count, confirmation
  dialog appears) — the bulk of correctness lives in the tested layers underneath it.

## Open items for the implementation plan

- Exact file/class names for the new read-side plan and export screen.
- Where in the navigation the new screen is reached from, given `app_shell.dart`'s reserved
  "fifth tab" comment doesn't yet exist as a real tab.
- Whether `recordExport`'s signature change (returning the new id) breaks any existing caller
  (the ForeFlight export screen) — likely just needs its call site updated to ignore the
  return value.
