# Export Sealing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Exporting the AMC1 FCL.050 PDF seals every draft flight it includes to committed
(atomically, recording which export sealed it), offers an unsealed watermarked preview, and
continues running totals across separate export runs from everything committed before the range.

**Architecture:** A `schemaVersion` 10 migration adds `FlightsTable.sealedByExportId` and two
holder-identity fields on `PilotProfileTable`. A new plain-Dart `Amc1Fcl050ExportPlan` (in
`lib/export/`) does all the reading — content rows, opening balance from everything committed
before the range, draft count — shared by preview and the real export. `DriftFlightRepository`
gets one new transactional write method, `sealForExport`. `buildAmc1Fcl050Logbook` gains
`openingBalance` and `isDraftPreview` parameters. A new screen wires it together, mirroring the
existing ForeFlight export screen's date-range/overlap-warning pattern.

**Tech Stack:** Flutter, Riverpod, Drift/SQLite, `package:pdf`.

**Spec:** `docs/superpowers/specs/2026-09-14-export-sealing-design.md`

## Global Constraints

- All stored times UTC; `CalendarDate` for calendar-date comparisons, never a naive `DateTime`.
- Domain code (`lib/domain/`) never imports `package:flutter/*`; enforced by
  `dart run tool/check_layering.dart`.
- Only `FlightRepository`/`DriftFlightRepository` may write `FlightsTable`.
- Conventional commits (`feat:`, `fix:`, `test:`, `docs:`). Run `dart format`, `flutter analyze`,
  `flutter test` clean before every commit.
- `flutter`/`dart` are puro shims — use PowerShell, not Git Bash, for any `flutter`/`dart`
  command.
- No placeholder/guessed values anywhere the design says "never guess a missing discriminator."

---

### Task 1: Schema migration — `sealedByExportId` and holder identity

**Files:**
- Modify: `lib/data/tables/flight_tables.dart` (add one column to `FlightsTable`)
- Modify: `lib/data/tables/pilot_record_tables.dart` (add two columns to `PilotProfileTable`)
- Modify: `lib/data/database.dart` (`schemaVersion` 9 → 10, one new `onUpgrade` step)
- Modify: `lib/data/mappers/pilot_record_mapper.dart` (map the two new `PilotProfile` fields)
- Modify: `lib/domain/pilot_record/pilot_profile.dart` (add the two new fields)
- Create: `drift_schemas/drift_schema_v10.json` (via `drift_dev schema dump`)
- Test: `test/data/database_migration_test.dart` (new test, v9 → v10)

**Interfaces:**
- Produces: `FlightsTable.sealedByExportId` (`TextColumn`, nullable, references
  `ExportRecordsTable.id`) → `FlightRow.sealedByExportId` (`String?`).
- Produces: `PilotProfile.holderName` (`String?`), `PilotProfile.primaryLicenceNumber` (`String?`)
  — both nullable, never defaulted (same convention as `homeBaseIcao`).
- Produces: `PilotProfileTable.holderName`, `PilotProfileTable.primaryLicenceNumber`
  (`TextColumn`, nullable) → `PilotProfileRow.holderName`, `PilotProfileRow.primaryLicenceNumber`.

- [ ] **Step 1: Add the domain model fields**

Edit `lib/domain/pilot_record/pilot_profile.dart`:

```dart
@freezed
abstract class PilotProfile with _$PilotProfile {
  const factory PilotProfile({
    required CalendarDate dateOfBirth,
    required String primaryJurisdictionId,
    String? homeBaseIcao,

    /// The name printed on group 1 of every AMC1 FCL.050 export front
    /// matter page (#83). Nullable and never defaulted — an export screen
    /// with nothing set here must ask, not guess.
    String? holderName,

    /// The licence number printed alongside [holderName]. Nullable, same
    /// reasoning. Deliberately a single field, not a full multi-licence
    /// model (CLAUDE.md's eventual "N licences, each with an issuing
    /// authority") — that stays a separate, larger feature.
    String? primaryLicenceNumber,
  }) = _PilotProfile;
}
```

- [ ] **Step 2: Regenerate the freezed part file**

Run: `flutter pub run build_runner build` (not `dart run` — see Global Constraints; no
`--delete-conflicting-outputs`, it's the default in build_runner 2.15.1+).

Expected: `lib/domain/pilot_record/pilot_profile.freezed.dart` is regenerated with the two new
fields in `_PilotProfile`'s constructor and `==`/`hashCode`/`copyWith`.

- [ ] **Step 3: Add the table columns**

Edit `lib/data/tables/flight_tables.dart`, inside `FlightsTable`, directly below
`tombstonedAt`:

```dart
  /// The export that sealed this flight from draft to committed (#83) —
  /// null for a flight committed some other way (e.g. #58's "log this
  /// flight now"), which is why this is a separate field from
  /// `committedAt` rather than reusing it. Set exactly once, the moment
  /// this flight transitions; committed entries never change lifecycle
  /// fields again.
  TextColumn get sealedByExportId =>
      text().nullable().references(ExportRecordsTable, #id)();
```

Add the import this needs at the top of the file:

```dart
import 'export_record_table.dart';
```

Edit `lib/data/tables/pilot_record_tables.dart`, inside `PilotProfileTable`, directly below
`homeBaseIcao`:

```dart
  /// Mirrors `PilotProfile.holderName` — nullable, never defaulted (#83).
  TextColumn get holderName => text().nullable()();

  /// Mirrors `PilotProfile.primaryLicenceNumber` — nullable, never
  /// defaulted (#83).
  TextColumn get primaryLicenceNumber => text().nullable()();
```

- [ ] **Step 4: Update the pilot-record mapper**

Edit `lib/data/mappers/pilot_record_mapper.dart`:

```dart
PilotProfileRow pilotProfileToRow(
  domain.PilotProfile profile, {
  required String id,
}) {
  return PilotProfileRow(
    id: id,
    dateOfBirth: profile.dateOfBirth.toString(),
    primaryJurisdictionId: profile.primaryJurisdictionId,
    homeBaseIcao: profile.homeBaseIcao,
    holderName: profile.holderName,
    primaryLicenceNumber: profile.primaryLicenceNumber,
  );
}

domain.PilotProfile pilotProfileFromRow(PilotProfileRow row) {
  return domain.PilotProfile(
    dateOfBirth: CalendarDate.parse(row.dateOfBirth),
    primaryJurisdictionId: row.primaryJurisdictionId,
    homeBaseIcao: row.homeBaseIcao,
    holderName: row.holderName,
    primaryLicenceNumber: row.primaryLicenceNumber,
  );
}
```

- [ ] **Step 5: Bump schemaVersion and add the migration step**

Edit `lib/data/database.dart`:

```dart
  @override
  int get schemaVersion => 10;
```

Add, as the last block inside `onUpgrade`, after the existing `if (from < 9)` block:

```dart
      // #83: adds sealedByExportId to flights (which export, if any,
      // sealed this flight to committed — separate from committedAt,
      // since #58's "log this flight now" can commit a flight with no
      // export involved) and holderName/primaryLicenceNumber to
      // pilot_profile (group 1 of the AMC1 FCL.050 front matter — never
      // defaulted, same as homeBaseIcao).
      if (from < 10) {
        await m.addColumn(flightsTable, flightsTable.sealedByExportId);
        await m.addColumn(pilotProfileTable, pilotProfileTable.holderName);
        await m.addColumn(
          pilotProfileTable,
          pilotProfileTable.primaryLicenceNumber,
        );
      }
```

- [ ] **Step 6: Run codegen for the new drift columns**

Run: `flutter pub run build_runner build`

Expected: `lib/data/database.g.dart` regenerates with the new columns and `FlightRow`/
`PilotProfileRow` fields.

- [ ] **Step 7: Regenerate the schema snapshot**

Run: `flutter pub run drift_dev schema dump lib/data/database.dart drift_schemas`

Expected: a new `drift_schemas/drift_schema_v10.json` is created.

- [ ] **Step 8: Write the failing migration test**

Add to `test/data/database_migration_test.dart`, a new seed function (after
`_seedV6Database`) and a new test (after the `#61` test at the end of `main()`):

```dart
/// As [_seedV6Database]'s tables, but including `import_batch_id` on
/// `flights` (#73's v7->v8 step) and unchanged otherwise -- the real v9
/// shape, since no migration step between v8 and v9 touches either table
/// this test's own v9->v10 step alters. `import_batches`/`export_records`/
/// `csv_mapping_profiles` aren't created: nothing in the v9->v10 step
/// references them, and sqlite3.open here never turns foreign_keys on, so
/// the unresolved `REFERENCES` on `import_batch_id`/`sealed_by_export_id`
/// don't need a real target table to exist.
void _seedV9Database(String path) {
  final db = sqlite3.sqlite3.open(path);
  try {
    db.execute('''
      CREATE TABLE pilot_profile (
        id TEXT NOT NULL,
        date_of_birth TEXT NOT NULL,
        primary_jurisdiction_id TEXT NOT NULL DEFAULT 'eu.easa.part-fcl',
        home_base_icao TEXT NULL,
        PRIMARY KEY (id)
      )
    ''');
    db.execute(
      'INSERT INTO pilot_profile (id, date_of_birth, primary_jurisdiction_id) '
      'VALUES (?, ?, ?)',
      ['singleton', '1990-01-01', 'eu.easa.part-fcl'],
    );
    db.execute('''
      CREATE TABLE flights (
        id TEXT NOT NULL,
        aircraft_id TEXT NOT NULL,
        pre_planned_navigation INTEGER NOT NULL,
        off_blocks INTEGER NOT NULL,
        on_blocks INTEGER NOT NULL,
        takeoff INTEGER NULL,
        landing INTEGER NULL,
        other_pilot_name TEXT NULL,
        other_pilot_credential_number TEXT NULL,
        carrying_passengers INTEGER NOT NULL,
        takeoffs_day_full_stop INTEGER NOT NULL,
        takeoffs_day_touch_and_go INTEGER NOT NULL,
        takeoffs_night_full_stop INTEGER NOT NULL,
        takeoffs_night_touch_and_go INTEGER NOT NULL,
        landings_day_full_stop INTEGER NOT NULL,
        landings_day_touch_and_go INTEGER NOT NULL,
        landings_night_full_stop INTEGER NOT NULL,
        landings_night_touch_and_go INTEGER NOT NULL,
        ifr_flight_plan_filed INTEGER NOT NULL,
        actual_instrument_minutes INTEGER NOT NULL,
        simulated_instrument_minutes INTEGER NOT NULL,
        holding_procedures_count INTEGER NOT NULL,
        tracking_performed INTEGER NOT NULL,
        series_group_id TEXT NULL,
        airworthiness_basis TEXT NULL,
        remarks TEXT NOT NULL,
        alternative_compliance_events TEXT NOT NULL DEFAULT '',
        capacity_command_authority INTEGER NOT NULL,
        capacity_sole_manipulator INTEGER NOT NULL,
        capacity_sole_occupant INTEGER NOT NULL,
        capacity_multi_pilot_operation INTEGER NOT NULL,
        capacity_additional_crew_required_by_rule INTEGER NOT NULL,
        capacity_acting_as_instructor INTEGER NOT NULL,
        capacity_acting_as_examiner INTEGER NOT NULL,
        capacity_picus_claimed INTEGER NOT NULL,
        capacity_pic_intervention_not_required INTEGER NOT NULL,
        capacity_manipulation_time_minutes INTEGER NULL,
        capacity_solo_endorsement_held INTEGER NULL,
        capacity_endorsing_instructor_name TEXT NULL,
        capacity_instructor_capacity TEXT NULL,
        capacity_instructor_influenced_flight INTEGER NULL,
        capacity_instructor_name TEXT NULL,
        capacity_instructor_credential_number TEXT NULL,
        capacity_instructor_credential_expiry TEXT NULL,
        capacity_other_pilot_role TEXT NULL,
        capacity_countersignature_status TEXT NULL,
        capacity_countersignature_signatory_name TEXT NULL,
        capacity_countersignature_signatory_credential_number TEXT NULL,
        capacity_countersignature_signatory_credential_expiry TEXT NULL,
        capacity_countersignature_signed_at INTEGER NULL,
        committed_at INTEGER NULL,
        tombstoned_at INTEGER NULL,
        import_batch_id TEXT NULL,
        PRIMARY KEY (id)
      )
    ''');
    db.execute(
      'INSERT INTO flights (id, aircraft_id, pre_planned_navigation, '
      'off_blocks, on_blocks, carrying_passengers, takeoffs_day_full_stop, '
      'takeoffs_day_touch_and_go, takeoffs_night_full_stop, '
      'takeoffs_night_touch_and_go, landings_day_full_stop, '
      'landings_day_touch_and_go, landings_night_full_stop, '
      'landings_night_touch_and_go, ifr_flight_plan_filed, '
      'actual_instrument_minutes, simulated_instrument_minutes, '
      'holding_procedures_count, tracking_performed, remarks, '
      'capacity_command_authority, capacity_sole_manipulator, '
      'capacity_sole_occupant, capacity_multi_pilot_operation, '
      'capacity_additional_crew_required_by_rule, '
      'capacity_acting_as_instructor, capacity_acting_as_examiner, '
      'capacity_picus_claimed, capacity_pic_intervention_not_required, '
      'committed_at) '
      'VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, '
      '?, ?, ?, ?, ?, ?, ?, ?, ?)',
      [
        'flight-1',
        'aircraft-1',
        0,
        1000,
        2000,
        0,
        1,
        0,
        0,
        0,
        1,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        0,
        'a pre-existing committed flight',
        1,
        1,
        1,
        0,
        0,
        0,
        0,
        0,
        5000,
      ],
    );
    db.execute('PRAGMA user_version = 9');
  } finally {
    db.close();
  }
}
```

```dart
  test(
    '#83: migrating a real v9 database to v10 preserves an existing '
    'committed flight and backfills sealedByExportId/holderName/'
    'primaryLicenceNumber to null',
    () async {
      _seedV9Database(dbFile.path);

      final db = await openWithBackup(dbFile, () async {
        final database = AppDatabase(NativeDatabase(dbFile));
        await database.customStatement('SELECT 1');
        return database;
      });
      addTearDown(db.close);

      final flightRows = await db.select(db.flightsTable).get();
      expect(flightRows, hasLength(1));
      expect(flightRows.single.id, 'flight-1');
      expect(flightRows.single.committedAt, 5000);
      expect(flightRows.single.sealedByExportId, isNull);

      final pilotProfiles = PilotProfileRepository(db);
      final profile = await pilotProfiles.find();
      expect(profile?.holderName, isNull);
      expect(profile?.primaryLicenceNumber, isNull);
    },
  );
```

- [ ] **Step 9: Run the migration test to verify it fails**

Run (PowerShell): `flutter test test/data/database_migration_test.dart`
Expected: FAIL — `sealedByExportId`/`holderName`/`primaryLicenceNumber` getters don't exist yet
if steps 3-6 weren't done, or the column doesn't exist on disk if step 5 wasn't done. (If you
did steps 1-7 already per this task's own ordering, skip to Step 10 — the point of this step is
never having claimed the migration works without having watched a real failure first; if you
implemented steps in a different order, go back and confirm each failed correctly in turn.)

- [ ] **Step 10: Run the migration test to verify it passes**

Run (PowerShell): `flutter test test/data/database_migration_test.dart`
Expected: PASS, all tests in the file including the new one.

- [ ] **Step 11: Run the full data-layer suite and the schema snapshot check**

Run (PowerShell):
```
flutter test test/data/
dart run tool/check_schema_snapshot.dart
```
Expected: both clean.

- [ ] **Step 12: Format, analyze, commit**

Run (PowerShell):
```
dart format lib/data/ lib/domain/pilot_record/ test/data/database_migration_test.dart
flutter analyze lib/data/ lib/domain/pilot_record/
```
Expected: clean.

```bash
git add lib/data/tables/flight_tables.dart lib/data/tables/pilot_record_tables.dart \
  lib/data/database.dart lib/data/database.g.dart lib/data/mappers/pilot_record_mapper.dart \
  lib/domain/pilot_record/pilot_profile.dart lib/domain/pilot_record/pilot_profile.freezed.dart \
  drift_schemas/drift_schema_v10.json test/data/database_migration_test.dart
git commit -m "feat: sealedByExportId and holder identity fields (#83)

Schema v9 -> v10: FlightsTable.sealedByExportId (which export, if any,
sealed a flight to committed -- separate from committedAt, since #58's
manual-save commit path involves no export) and
PilotProfile.holderName/primaryLicenceNumber (group 1 of the AMC1
FCL.050 front matter, currently sourced from nowhere).

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 2: `ExportRecordRepository.recordExport` returns the new id

**Files:**
- Modify: `lib/domain/repository/export_record_repository.dart`
- Modify: `lib/data/repositories/export_record_repository_drift.dart`
- Modify: `lib/ui/io/export_screen.dart:112-114` (existing call site — ignore the new return
  value)
- Test: `test/data/repositories/export_record_repository_test.dart` (existing file — its own
  `setUp` already builds `db`/`exports`; add to it)

**Interfaces:**
- Produces: `ExportRecordRepository.recordExport(...)` now returns `Future<String>` (the new
  row's id) instead of `Future<void>`.

- [ ] **Step 1: Write the failing test**

Add to `test/data/repositories/export_record_repository_test.dart`, inside `main()`, using its
existing `exports` variable (a `DriftExportRecordRepository`, built in that file's own `setUp`):

```dart
test('recordExport returns the new row\'s id', () async {
  final id = await exports.recordExport(
    format: 'AMC1 FCL.050',
    from: const CalendarDate(2026, 1, 1),
    to: const CalendarDate(2026, 1, 31),
  );

  expect(id, isNotEmpty);
  final overlapping = await exports.findOverlapping(
    format: 'AMC1 FCL.050',
    from: const CalendarDate(2026, 1, 15),
    to: const CalendarDate(2026, 2, 15),
  );
  expect(overlapping.single.id, id);
});
```

- [ ] **Step 2: Run it to verify it fails**

Run (PowerShell): `flutter test test/data/repositories/export_record_repository_test.dart`
Expected: FAIL — `recordExport`'s return type is `void`, so `id` can't be assigned; a
compilation error naming the mismatch.

- [ ] **Step 3: Change the interface and implementation**

Edit `lib/domain/repository/export_record_repository.dart`:

```dart
  /// Records that an export of [format] covering [from]..[to] just
  /// happened. Returns the new record's id — #83 links sealed flights
  /// back to the export that sealed them via this id.
  Future<String> recordExport({
    required String format,
    required CalendarDate from,
    required CalendarDate to,
  });
```

Edit `lib/data/repositories/export_record_repository_drift.dart`:

```dart
  @override
  Future<String> recordExport({
    required String format,
    required CalendarDate from,
    required CalendarDate to,
  }) async {
    final id = generateUlid();
    await _db
        .into(_db.exportRecordsTable)
        .insert(
          ExportRecordRow(
            id: id,
            format: format,
            rangeFrom: from.toString(),
            rangeTo: to.toString(),
            exportedAt: DateTime.now().toUtc().millisecondsSinceEpoch,
          ),
        );
    return id;
  }
```

- [ ] **Step 4: Fix the existing ForeFlight export screen call site**

Edit `lib/ui/io/export_screen.dart`, the `_export` method — the existing call:

```dart
      await ref
          .read(exportRecordRepositoryProvider)
          .recordExport(format: faaCsvExportFormatLabel, from: from, to: to);
```

needs no change to compile (a discarded `Future<String>` is legal Dart), but update it to make
the discard explicit and keep `flutter analyze` free of an "unused result" style warning if one
fires:

```dart
      unawaited(
        ref
            .read(exportRecordRepositoryProvider)
            .recordExport(format: faaCsvExportFormatLabel, from: from, to: to),
      );
```

Wait — this call is already `await`ed and its result simply unused, which is legal Dart with no
lint by default. **Do not wrap it in `unawaited`** (that would change it from awaited to
fire-and-forget, a real behavior change this task doesn't intend). Leave the existing
`await ref.read(exportRecordRepositoryProvider).recordExport(...)` line exactly as it is — it
still compiles unchanged against the new `Future<String>` return type, simply not using the
returned id. No edit needed to this file at all; this step exists only to confirm that by
running analyze in Step 6.

- [ ] **Step 5: Run the test to verify it passes**

Run (PowerShell): `flutter test test/data/repositories/export_record_repository_test.dart`
Expected: PASS.

- [ ] **Step 6: Analyze the whole repository + UI surface touched**

Run (PowerShell): `flutter analyze lib/domain/repository/export_record_repository.dart lib/data/repositories/export_record_repository_drift.dart lib/ui/io/export_screen.dart`
Expected: clean, no "unused result" or type errors.

- [ ] **Step 7: Run the full test suite**

Run (PowerShell): `flutter test`
Expected: all pass — this confirms no other caller of `recordExport` broke.

- [ ] **Step 8: Commit**

```bash
git add lib/domain/repository/export_record_repository.dart \
  lib/data/repositories/export_record_repository_drift.dart \
  test/data/repositories/export_record_repository_test.dart
git commit -m "feat: recordExport returns the new record's id (#83)

Needed to link a flight sealed by an export back to that export via
FlightsTable.sealedByExportId.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 3: `FlightRepository.sealForExport`

**Files:**
- Modify: `lib/domain/repository/flight_repository.dart`
- Modify: `lib/data/repositories/flight_repository_drift.dart`
- Test: `test/data/repositories/flight_repository_committed_test.dart` (existing file — its own
  top-level `_draft({String remarks = ''})` helper and `setUp` already build `db`/`flights`/
  `aircraftId`; add to it)

**Interfaces:**
- Consumes: `FlightRepository.commit(String flightId)` (existing).
- Produces: `FlightRepository.sealForExport({required List<String> flightIds, required String exportRecordId})` — `Future<void>`. Commits every flight in `flightIds` not already committed
  (throws nothing for one that's already committed — silently leaves it alone, matching
  "re-exporting an already-sealed range changes no state") and sets its `sealedByExportId`. All
  in one transaction.

- [ ] **Step 1: Write the failing test**

Add to `test/data/repositories/flight_repository_committed_test.dart`, inside `main()`, using
its existing `flights`/`aircraftId`/`_draft()`:

```dart
  test('sealForExport commits every draft flight passed and sets '
      'sealedByExportId, leaving an already-committed flight in the list '
      'untouched', () async {
    final draftId = await flights.createDraft(_draft(), aircraftId: aircraftId);
    final alreadyCommittedId = await committedFlight();

    await flights.sealForExport(
      flightIds: [draftId, alreadyCommittedId],
      exportRecordId: 'export-1',
    );

    final draftRow = await (db.select(
      db.flightsTable,
    )..where((t) => t.id.equals(draftId))).getSingle();
    expect(draftRow.committedAt, isNotNull);
    expect(draftRow.sealedByExportId, 'export-1');

    final alreadyCommittedRow = await (db.select(
      db.flightsTable,
    )..where((t) => t.id.equals(alreadyCommittedId))).getSingle();
    expect(
      alreadyCommittedRow.sealedByExportId,
      isNull,
      reason: 'this flight was committed before the export, not by it',
    );
  });

  test(
    'sealForExport is atomic: nothing is sealed if any flight id is unknown',
    () async {
      final draftId = await flights.createDraft(_draft(), aircraftId: aircraftId);

      await expectLater(
        () => flights.sealForExport(
          flightIds: [draftId, 'no-such-flight'],
          exportRecordId: 'export-1',
        ),
        throwsA(anything),
      );

      final draftRow = await (db.select(
        db.flightsTable,
      )..where((t) => t.id.equals(draftId))).getSingle();
      expect(
        draftRow.committedAt,
        isNull,
        reason: 'the whole transaction must roll back, sealing nothing',
      );
    },
  );
```

`committedFlight()` is this file's own existing top-level helper (`createDraft` + `commit`,
returns the id) — visible in the excerpt this plan already quoted from the file.

- [ ] **Step 2: Run it to verify it fails**

Run (PowerShell): `flutter test test/data/repositories/flight_repository_committed_test.dart`
Expected: FAIL — `sealForExport` isn't a method on `DriftFlightRepository`.

- [ ] **Step 3: Add the interface method**

Edit `lib/domain/repository/flight_repository.dart`, add after `undoImportBatch`:

```dart
  /// Seals every one of [flightIds] to committed as part of export
  /// [exportRecordId] (#83): a flight still draft is committed and gets
  /// `sealedByExportId` set to [exportRecordId]; a flight already
  /// committed (by this export's own re-run, or by some other path such
  /// as #58's manual commit) is left completely untouched — that's what
  /// makes re-exporting an already-sealed range a no-op state-wise. All
  /// in one transaction: an unknown flight id throws and nothing among
  /// [flightIds] is sealed.
  Future<void> sealForExport({
    required List<String> flightIds,
    required String exportRecordId,
  });
```

- [ ] **Step 4: Implement it**

Edit `lib/data/repositories/flight_repository_drift.dart`. This file already has a private
`_requireRow(String flightId)` helper (used by `commit`, `updateDraft`, `deleteDraft` — fetches
a `FlightRow` or throws if the id doesn't exist) and `commit`'s own exact update shape to match.
Add, near `commit`:

```dart
  @override
  Future<void> sealForExport({
    required List<String> flightIds,
    required String exportRecordId,
  }) async {
    await _db.transaction(() async {
      for (final flightId in flightIds) {
        final current = await _requireRow(flightId);
        if (current.committedAt != null) continue; // already committed, untouched.
        await (_db.update(
          _db.flightsTable,
        )..where((t) => t.id.equals(flightId))).write(
          FlightsTableCompanion(
            committedAt: Value(DateTime.now().toUtc().millisecondsSinceEpoch),
            sealedByExportId: Value(exportRecordId),
          ),
        );
      }
    });
  }
```

`_requireRow` throws if `flightId` doesn't exist, and that throw propagates out of
`_db.transaction`'s callback — drift rolls the whole transaction back on any thrown exception,
which is exactly Step 1's second test's atomicity requirement. `FlightsTableCompanion` and
`Value` are already used by `commit` immediately above, so no new imports are needed.

- [ ] **Step 5: Run the tests to verify they pass**

Run (PowerShell): `flutter test test/data/repositories/flight_repository_committed_test.dart`
Expected: PASS, both new tests and every pre-existing one in the file.

- [ ] **Step 6: Format, analyze, run full suite**

Run (PowerShell):
```
dart format lib/domain/repository/flight_repository.dart lib/data/repositories/flight_repository_drift.dart
flutter analyze lib/domain/repository/flight_repository.dart lib/data/repositories/flight_repository_drift.dart
flutter test
```
Expected: all clean.

- [ ] **Step 7: Commit**

```bash
git add lib/domain/repository/flight_repository.dart lib/data/repositories/flight_repository_drift.dart \
  test/data/repositories/flight_repository_committed_test.dart
git commit -m "feat: FlightRepository.sealForExport (#83)

Commits every still-draft flight in a list, tagging it with the
export that sealed it; a flight already committed is left untouched
(re-exporting an already-sealed range changes no state). One
transaction -- an unknown flight id rolls back the whole seal.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 4: `buildAmc1Fcl050Logbook` gains `openingBalance`

**Files:**
- Modify: `lib/export/amc1_fcl050_layout.dart`
- Test: `test/export/amc1_fcl050_layout_test.dart`

**Interfaces:**
- Consumes: `Amc1Fcl050Totals` (existing, from `lib/export/amc1_fcl050_totals.dart`).
- Produces: `buildAmc1Fcl050Logbook(..., {Amc1Fcl050Totals openingBalance = Amc1Fcl050Totals.zero})`.
  The first spread's `broughtForward` is `openingBalance`, not always `Amc1Fcl050Totals.zero`.

- [ ] **Step 1: Write the failing test**

Add to `test/export/amc1_fcl050_layout_test.dart`, after the existing "brought-forward on
spread n..." test:

```dart
  test(
    'an opening balance seeds the first spread\'s brought-forward instead '
    'of zero (#83)',
    () async {
      final opening = Amc1Fcl050Totals.fromRows([sampleRow()]);

      final spreads = await amc1Fcl050SpreadTotals(
        [sampleRow()],
        openingBalance: opening,
      );

      expect(spreads, hasLength(1));
      expect(
        amc1Fcl050PageOneTotalsValues(spreads.single.broughtForward),
        amc1Fcl050PageOneTotalsValues(opening),
      );
      // total-to-date = opening balance + this page's own flight.
      final expectedTotal = opening + Amc1Fcl050Totals.fromRows([sampleRow()]);
      expect(
        amc1Fcl050PageOneTotalsValues(spreads.single.totalToDate),
        amc1Fcl050PageOneTotalsValues(expectedTotal),
      );
    },
  );
```

- [ ] **Step 2: Run it to verify it fails**

Run (PowerShell): `flutter test test/export/amc1_fcl050_layout_test.dart`
Expected: FAIL — `amc1Fcl050SpreadTotals` has no `openingBalance` named parameter.

- [ ] **Step 3: Thread the parameter through**

In `lib/export/amc1_fcl050_layout.dart`, find `_spreadTotals` (private, takes
`List<_EntrySpread> spreads`) and change it:

```dart
List<Amc1Fcl050SpreadTotals> _spreadTotals(
  List<_EntrySpread> spreads, {
  Amc1Fcl050Totals openingBalance = Amc1Fcl050Totals.zero,
}) {
  var broughtForward = openingBalance;
  final results = <Amc1Fcl050SpreadTotals>[];
  for (final spread in spreads) {
    final thisPage = Amc1Fcl050Totals.fromRows(spread.rows);
    final totalToDate = broughtForward + thisPage;
    results.add(
      Amc1Fcl050SpreadTotals(
        rows: spread.rows,
        thisPage: thisPage,
        broughtForward: broughtForward,
        totalToDate: totalToDate,
      ),
    );
    broughtForward = totalToDate;
  }
  return results;
}
```

Find the public `amc1Fcl050SpreadTotals` function and add the same parameter, passed through:

```dart
Future<List<Amc1Fcl050SpreadTotals>> amc1Fcl050SpreadTotals(
  List<Amc1Fcl050Row> rows, {
  Amc1Fcl050Totals openingBalance = Amc1Fcl050Totals.zero,
}) async {
  final document = pw.Document();
  final monospaceFont = PdfFont.courier(document.document);
  final remarksColumnWidth = _columnWidths(_pageTwoGroups).last;
  final spreads = _packEntrySpreads(rows, monospaceFont, remarksColumnWidth);
  return _spreadTotals(spreads, openingBalance: openingBalance);
}
```

Find `buildAmc1Fcl050Logbook`'s signature and add the same parameter:

```dart
Future<pw.Document> buildAmc1Fcl050Logbook({
  required String holderName,
  required String holderLicenceNumber,
  required List<Amc1Fcl050Row> rows,
  Amc1Fcl050Totals openingBalance = Amc1Fcl050Totals.zero,
}) async {
```

and inside its body, change the call `final spreadTotals = _spreadTotals(spreads);` to:

```dart
  final spreadTotals = _spreadTotals(spreads, openingBalance: openingBalance);
```

- [ ] **Step 4: Run the test to verify it passes**

Run (PowerShell): `flutter test test/export/amc1_fcl050_layout_test.dart`
Expected: PASS, including every pre-existing test in the file (the default value keeps every
call site that doesn't pass `openingBalance` behaving exactly as before).

- [ ] **Step 5: Format, analyze, full suite**

Run (PowerShell):
```
dart format lib/export/amc1_fcl050_layout.dart test/export/amc1_fcl050_layout_test.dart
flutter analyze lib/export/
flutter test
```
Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add lib/export/amc1_fcl050_layout.dart test/export/amc1_fcl050_layout_test.dart
git commit -m "feat: buildAmc1Fcl050Logbook accepts an opening balance (#83)

Seeds the first spread's brought-forward instead of always starting
at zero -- lets running totals continue across separate export runs.
Defaults to Amc1Fcl050Totals.zero, so every existing call site is
unaffected.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 5: `buildAmc1Fcl050Logbook` gains `isDraftPreview` watermark

**Files:**
- Modify: `lib/export/amc1_fcl050_layout.dart`
- Test: `test/export/amc1_fcl050_layout_test.dart`

**Interfaces:**
- Produces: `buildAmc1Fcl050Logbook(..., {bool isDraftPreview = false})`. When `true`, every
  page (front matter, address, every entry-spread page) renders a watermark.

- [ ] **Step 1: Write the failing test**

This is a rendering change with no new pure-Dart-testable value (the codebase's own established
pattern for this file is to smoke-test full-document generation, never to parse rendered PDF
content back out — see every existing `buildAmc1Fcl050Logbook` test). Add:

```dart
  test(
    'isDraftPreview still generates valid, non-empty PDF bytes (#83)',
    () async {
      final document = await buildAmc1Fcl050Logbook(
        holderName: 'Jane Pilot',
        holderLicenceNumber: 'UK.FCL.123456',
        rows: [sampleRow()],
        isDraftPreview: true,
      );

      final bytes = await document.save();

      expect(bytes, isNotEmpty);
      expect(String.fromCharCodes(bytes.take(5)), '%PDF-');
    },
  );
```

- [ ] **Step 2: Run it to verify it fails**

Run (PowerShell): `flutter test test/export/amc1_fcl050_layout_test.dart`
Expected: FAIL — `isDraftPreview` isn't a recognized named parameter.

- [ ] **Step 3: Add the watermark widget and thread the flag through**

In `lib/export/amc1_fcl050_layout.dart`, add a new private widget builder near
`_pageNumberFooter`:

```dart
/// A large, rotated, semi-transparent "DRAFT — NOT SEALED" overlay for
/// preview mode (#83) — unmistakable on screen or print that this copy
/// hasn't sealed anything and carries no legal weight yet.
pw.Widget _draftWatermark() => pw.Center(
  child: pw.Transform.rotate(
    angle: 0.5,
    child: pw.Opacity(
      opacity: 0.15,
      child: pw.Text(
        'DRAFT — NOT SEALED',
        style: pw.TextStyle(
          fontSize: 60,
          fontWeight: pw.FontWeight.bold,
        ),
      ),
    ),
  ),
);

/// Wraps [content] with [_draftWatermark] when [isDraftPreview] — shared
/// by every one of this file's four page-building functions so the
/// overlay looks identical everywhere rather than four slightly
/// different copies.
pw.Widget _withDraftWatermark(pw.Widget content, {required bool isDraftPreview}) {
  if (!isDraftPreview) return content;
  return pw.Stack(
    children: [
      content,
      pw.Positioned.fill(child: _draftWatermark()),
    ],
  );
}
```

Find each of the four page-building functions — `_buildFrontMatterPage`, `_buildAddressPage`,
`_buildEntryPageOne`, `_buildEntryPageTwo` — and:

1. Add `required bool isDraftPreview,` to each function's parameter record.
2. Wrap each one's `build: (context) => pw.Column(...)` return value with
   `_withDraftWatermark(pw.Column(...), isDraftPreview: isDraftPreview)` — i.e. the existing
   `pw.Column(children: [...])` expression becomes the first argument to
   `_withDraftWatermark(...)` rather than the direct return value of `build:`.

Find `buildAmc1Fcl050Logbook`'s signature and add:

```dart
  bool isDraftPreview = false,
```

and pass `isDraftPreview: isDraftPreview` into each of the four call sites inside its body
(`_buildFrontMatterPage(...)`, `_buildAddressPage(...)`, and both calls inside the `for` loop
over `spreads`).

- [ ] **Step 4: Run the test to verify it passes**

Run (PowerShell): `flutter test test/export/amc1_fcl050_layout_test.dart`
Expected: PASS, including every pre-existing test (default `false` keeps prior behavior).

- [ ] **Step 5: Visually verify the watermark**

There is no automated way to confirm the watermark *looks* right (this codebase's own testing
philosophy for this file avoids parsing rendered PDF content). Follow the pattern used
throughout this project's history for this exact file: write a throwaway test under
`test/export/` that calls `buildAmc1Fcl050Logbook(..., isDraftPreview: true)`, saves the bytes
to a file under `build/`, delete the throwaway test afterward, and visually inspect the output
(render to PNG, or open the PDF) before moving on. Confirm the watermark is visible but doesn't
make the printed figures unreadable.

- [ ] **Step 6: Format, analyze, full suite**

Run (PowerShell):
```
dart format lib/export/amc1_fcl050_layout.dart test/export/amc1_fcl050_layout_test.dart
flutter analyze lib/export/
flutter test
```
Expected: clean.

- [ ] **Step 7: Commit**

```bash
git add lib/export/amc1_fcl050_layout.dart test/export/amc1_fcl050_layout_test.dart
git commit -m "feat: buildAmc1Fcl050Logbook draft-preview watermark (#83)

isDraftPreview overlays a rotated, semi-transparent 'DRAFT - NOT
SEALED' watermark on every page. Defaults to false, so every existing
call site is unaffected.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 6: `easaProjectionProvider`

**Files:**
- Create: `lib/ui/providers/easa_export_providers.dart`
- Test: none required — this mirrors `faaProjectionProvider` exactly, a Riverpod provider
  definition with no independent logic of its own to unit test; it's exercised end-to-end by
  Task 8's screen test.

**Interfaces:**
- Produces: `easaProjectionProvider` — `FutureProvider<JurisdictionProjection>`, always
  resolving `'eu.easa.part-fcl'`.

- [ ] **Step 1: Create the provider**

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/primitives/default_primitives.dart';
import '../../domain/projection/jurisdiction_projection.dart';
import 'aerodrome_providers.dart';
import 'jurisdiction_providers.dart';

/// The EASA projection, unconditionally — mirrors
/// `foreflight_export_providers.dart`'s `faaProjectionProvider` exactly,
/// same reasoning: the AMC1 FCL.050 export is EASA-shaped regardless of
/// which licence the pilot actually holds primarily, and
/// `jurisdictionProjectionsProvider` only builds projections for
/// jurisdictions backed by a held rating, which would leave a pilot with
/// no EASA rating unable to export at all.
final easaProjectionProvider = FutureProvider<JurisdictionProjection>((
  ref,
) async {
  final registry = await ref.watch(jurisdictionRegistryProvider.future);
  final aerodromes = await ref.watch(aerodromeDirectoryProvider.future);
  return JurisdictionProjection(
    registry: registry,
    primitives: defaultPrimitives,
    aerodromes: aerodromes,
    jurisdictionId: 'eu.easa.part-fcl',
  );
});
```

- [ ] **Step 2: Analyze**

Run (PowerShell): `flutter analyze lib/ui/providers/easa_export_providers.dart`
Expected: clean.

- [ ] **Step 3: Commit**

```bash
git add lib/ui/providers/easa_export_providers.dart
git commit -m "feat: easaProjectionProvider (#83)

Mirrors faaProjectionProvider -- the EASA projection, unconditionally,
for the AMC1 FCL.050 export screen.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 7: `Amc1Fcl050ExportPlan` — read-side orchestration

**Files:**
- Create: `lib/export/amc1_fcl050_export_plan.dart`
- Test: `test/export/amc1_fcl050_export_plan_test.dart`

**Interfaces:**
- Consumes: `FlightReadRepository.watchFlights`/`watchDrafts` (existing), `Projection`
  (existing), `buildAmc1Fcl050Row` (existing, from `amc1_fcl050_row_mapper.dart`),
  `Amc1Fcl050Totals` (existing).
- Produces:
  ```dart
  class Amc1Fcl050ExportPlan {
    const Amc1Fcl050ExportPlan({
      required this.contentRows,
      required this.openingBalance,
      required this.draftFlightIds,
    });

    final List<Amc1Fcl050Row> contentRows;
    final Amc1Fcl050Totals openingBalance;
    final List<String> draftFlightIds;

    int get draftCount => draftFlightIds.length;
  }

  Future<Amc1Fcl050ExportPlan> buildAmc1Fcl050ExportPlan({
    required FlightReadRepository flightReadRepository,
    required Projection easaProjection,
    required CalendarDate from,
    required CalendarDate to,
  });
  ```

- [ ] **Step 1: Write the failing test**

Modeled on `test/data/repositories/flight_repository_committed_test.dart`'s own `_draft()`
helper and `AircraftRepository(db).upsert(...)` setup (both confirmed exact patterns from that
file), combined with `test/export/amc1_fcl050_row_mapper_test.dart`'s real-EASA-profile
`JurisdictionProjection` setup:

```dart
import 'package:drift/native.dart';
import 'package:easa_digital_log/data/database.dart';
import 'package:easa_digital_log/data/repositories/aircraft_repository.dart';
import 'package:easa_digital_log/data/repositories/flight_read_repository_drift.dart';
import 'package:easa_digital_log/data/repositories/flight_repository_drift.dart';
import 'package:easa_digital_log/domain/jurisdiction/jurisdiction_profile.dart';
import 'package:easa_digital_log/domain/jurisdiction/jurisdiction_registry.dart';
import 'package:easa_digital_log/domain/model/aerodrome_directory.dart';
import 'package:easa_digital_log/domain/model/aircraft.dart';
import 'package:easa_digital_log/domain/model/calendar_date.dart';
import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:easa_digital_log/domain/primitives/default_primitives.dart';
import 'package:easa_digital_log/domain/projection/jurisdiction_projection.dart';
import 'package:easa_digital_log/export/amc1_fcl050_export_plan.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';

const _capacity = PilotCapacity(
  commandAuthority: true,
  soleManipulator: true,
  soleOccupant: true,
  multiPilotOperation: false,
  additionalCrewRequiredByRule: false,
  actingAsInstructor: false,
  actingAsExaminer: false,
  picusClaimed: false,
  picInterventionNotRequired: false,
);

Flight _flightOn(DateTime offBlocksUtc) => Flight(
  aircraftRegistration: 'G-ABCD',
  route: const ['EGKA', 'EGKB'],
  prePlannedNavigation: false,
  offBlocks: UtcInstant.fromDateTime(offBlocksUtc),
  onBlocks: UtcInstant.fromDateTime(offBlocksUtc.add(const Duration(hours: 1))),
  capacity: _capacity,
  carryingPassengers: false,
  takeoffs: const CircuitCounts(dayFullStop: 1),
  landings: const CircuitCounts(dayFullStop: 1),
  ifrFlightPlanFiled: false,
  actualInstrumentTime: FlightDuration.zero,
  simulatedInstrumentTime: FlightDuration.zero,
  approaches: const [],
  holdingProceduresCount: 0,
  trackingPerformed: false,
  remarks: '',
);

void main() {
  late AppDatabase db;
  late JurisdictionProjection easaProjection;
  late DriftFlightRepository flights;
  late DriftFlightReadRepository flightReads;
  late String aircraftId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    final yaml = File(
      'assets/jurisdictions/eu.easa.part-fcl.yaml',
    ).readAsStringSync();
    easaProjection = JurisdictionProjection(
      registry: JurisdictionRegistry([parseJurisdictionProfileYaml(yaml)]),
      primitives: defaultPrimitives,
      aerodromes: AerodromeDirectory(const []),
      jurisdictionId: 'eu.easa.part-fcl',
    );
    flights = DriftFlightRepository(db);
    flightReads = DriftFlightReadRepository(db);
    aircraftId = await AircraftRepository(db).upsert(
      const Aircraft(
        registration: 'G-ABCD',
        manufacturer: 'Cessna',
        model: '152',
        category: AircraftCategory.aeroplane,
        engineType: EngineType.piston,
        engineCount: 1,
        operatingSurface: OperatingSurface.land,
        requiresMultiCrew: false,
      ),
    );
  });

  tearDown(() => db.close());

  test(
    'opening balance sums committed flights before the range; content '
    'rows are committed+draft flights in range; draft count is only '
    'drafts in range',
    () async {
      final beforeRangeId = await flights.createDraft(
        _flightOn(DateTime.utc(2025, 12, 15, 9)),
        aircraftId: aircraftId,
      );
      await flights.commit(beforeRangeId);
      final inRangeCommittedId = await flights.createDraft(
        _flightOn(DateTime.utc(2026, 1, 10, 9)),
        aircraftId: aircraftId,
      );
      await flights.commit(inRangeCommittedId);
      final inRangeDraftId = await flights.createDraft(
        _flightOn(DateTime.utc(2026, 1, 20, 9)),
        aircraftId: aircraftId,
      );
      final afterRangeId = await flights.createDraft(
        _flightOn(DateTime.utc(2026, 3, 1, 9)),
        aircraftId: aircraftId,
      );
      await flights.commit(afterRangeId);

      final plan = await buildAmc1Fcl050ExportPlan(
        flightReadRepository: flightReads,
        easaProjection: easaProjection,
        from: const CalendarDate(2026, 1, 1),
        to: const CalendarDate(2026, 1, 31),
      );

      expect(plan.draftFlightIds, [inRangeDraftId]);
      expect(plan.contentRows, hasLength(2)); // in-range committed + in-range draft
      // The one before-range flight's block time is exactly the 1-hour
      // offBlocks-to-onBlocks span _flightOn always sets.
      expect(plan.openingBalance.totalTimeOfFlight.inMinutes, 60);
    },
  );
}
```

- [ ] **Step 2: Run it to verify it fails**

Run (PowerShell): `flutter test test/export/amc1_fcl050_export_plan_test.dart`
Expected: FAIL — `amc1_fcl050_export_plan.dart` doesn't exist yet.

- [ ] **Step 3: Write the implementation**

```dart
import '../domain/model/calendar_date.dart';
import '../domain/projection/projection.dart';
import '../domain/repository/flight_read_repository.dart';
import 'amc1_fcl050_row.dart';
import 'amc1_fcl050_row_mapper.dart';
import 'amc1_fcl050_totals.dart';

/// Everything the AMC1 FCL.050 export needs to read before it can render
/// or seal anything (#83) — shared by preview and the real, sealing
/// export, so what a pilot previews is exactly what sealing would
/// produce. Read-only: never writes anything.
class Amc1Fcl050ExportPlan {
  const Amc1Fcl050ExportPlan({
    required this.contentRows,
    required this.openingBalance,
    required this.draftFlightIds,
  });

  /// Every committed-or-about-to-be-committed flight in the requested
  /// range, sorted chronologically by offBlocks — what the PDF prints.
  final List<Amc1Fcl050Row> contentRows;

  /// The sum of every committed, non-tombstoned flight before the range
  /// — seeds [buildAmc1Fcl050Logbook]'s openingBalance so running totals
  /// continue across separate export runs.
  final Amc1Fcl050Totals openingBalance;

  /// Ids of the flights in range still draft — what
  /// [FlightRepository.sealForExport] must be called with to actually
  /// seal this export, and what the confirmation dialog counts.
  final List<String> draftFlightIds;

  int get draftCount => draftFlightIds.length;
}

/// Builds the plan for exporting [from]..[to] under [easaProjection].
/// Fetches every committed flight with no date filter (`FlightReadRepository`
/// has no one-shot "before a date" query — see its own dartdoc on
/// `watchFlights`/`watchDrafts` being streams), then filters client-side
/// by each flight's own offBlocks date, since `FlightQuery.from`/`to`
/// only expresses "in this range", not "before it".
Future<Amc1Fcl050ExportPlan> buildAmc1Fcl050ExportPlan({
  required FlightReadRepository flightReadRepository,
  required Projection easaProjection,
  required CalendarDate from,
  required CalendarDate to,
}) async {
  final allCommitted = await flightReadRepository
      .watchFlights(projection: easaProjection)
      .first;
  final allDrafts = await flightReadRepository.watchDrafts().first;

  final beforeRange = <({String id, Amc1Fcl050Row row, CalendarDate date})>[];
  final inRange = <({String id, Amc1Fcl050Row row, CalendarDate date})>[];

  for (final projected in allCommitted) {
    final flight = projected.record.flight;
    final date = CalendarDate.fromUtcInstant(flight.offBlocks);
    final row = buildAmc1Fcl050Row(
      flight: flight,
      aircraft: projected.record.aircraft,
      easaProjection: easaProjection,
    );
    if (date < from) {
      beforeRange.add((id: projected.record.id, row: row, date: date));
    } else if (date <= to) {
      inRange.add((id: projected.record.id, row: row, date: date));
    }
  }

  final draftFlightIds = <String>[];
  for (final record in allDrafts) {
    final date = CalendarDate.fromUtcInstant(record.flight.offBlocks);
    if (date < from || date > to) continue;
    final row = buildAmc1Fcl050Row(
      flight: record.flight,
      aircraft: record.aircraft,
      easaProjection: easaProjection,
    );
    inRange.add((id: record.id, row: row, date: date));
    draftFlightIds.add(record.id);
  }

  inRange.sort((a, b) => a.date.compareTo(b.date));

  return Amc1Fcl050ExportPlan(
    contentRows: [for (final entry in inRange) entry.row],
    openingBalance: Amc1Fcl050Totals.fromRows([
      for (final entry in beforeRange) entry.row,
    ]),
    draftFlightIds: draftFlightIds,
  );
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run (PowerShell): `flutter test test/export/amc1_fcl050_export_plan_test.dart`
Expected: PASS.

- [ ] **Step 5: Format, analyze, full suite**

Run (PowerShell):
```
dart format lib/export/amc1_fcl050_export_plan.dart test/export/amc1_fcl050_export_plan_test.dart
flutter analyze lib/export/
flutter test
```
Expected: clean.

- [ ] **Step 6: Commit**

```bash
git add lib/export/amc1_fcl050_export_plan.dart test/export/amc1_fcl050_export_plan_test.dart
git commit -m "feat: Amc1Fcl050ExportPlan read-side orchestration (#83)

Computes content rows, opening balance (everything committed before
the range), and the draft-flight-id list a real export must seal --
shared by preview and the real export so both read identically.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 8: The AMC1 FCL.050 export screen

**Files:**
- Create: `lib/ui/io/amc1_fcl050_export_screen.dart`
- Modify: `lib/ui/settings/settings_screen.dart` (add a row that opens it, next to the existing
  `_ExportRow`)
- Test: `test/ui/io/amc1_fcl050_export_screen_test.dart`

**Interfaces:**
- Consumes: `easaProjectionProvider` (Task 6), `buildAmc1Fcl050ExportPlan`/
  `Amc1Fcl050ExportPlan` (Task 7), `buildAmc1Fcl050Logbook` (Task 4/5), `FlightRepository
  .sealForExport` (Task 3), `ExportRecordRepository.recordExport`/`findOverlapping` (Task 2,
  existing), `pilotProfileProvider`/`pilotProfileRepositoryProvider` (existing),
  `flightReadRepositoryProvider`/`flightRepositoryProvider`/`exportRecordRepositoryProvider`
  (existing, from `repository_providers.dart`).

- [ ] **Step 1: Write the screen**

Follow `lib/ui/io/export_screen.dart` closely (re-read it before writing this — the date
pickers, overlap-check `FutureBuilder`, and bottom-button layout should look the same). New
pieces this screen adds: an inline holder-name/licence-number editor (pre-filled from
`pilotProfileProvider`, saved via `pilotProfileRepositoryProvider` when changed), a Preview
button, and an Export & Seal button with a confirmation dialog.

```dart
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/model/calendar_date.dart';
import '../../domain/pilot_record/pilot_profile.dart';
import '../../domain/repository/export_record_repository.dart';
import '../../export/amc1_fcl050_export_plan.dart';
import '../../export/amc1_fcl050_layout.dart';
import '../providers/easa_export_providers.dart';
import '../providers/pilot_profile_providers.dart';
import '../providers/repository_providers.dart';
import '../theme/app_colors.dart';

const _amc1Fcl050ExportFormatLabel = 'AMC1 FCL.050';

/// #83: exports and seals the AMC1 FCL.050 PDF logbook. A date range (same
/// pattern as `ExportScreen`'s ForeFlight CSV flow), an inline
/// holder-identity editor (nothing else in the app can set this yet — see
/// the #83 design spec's "Section 1"), and two actions: Preview (no state
/// change, watermarked) and Export & Seal (commits every still-draft
/// flight in range, atomically, after a confirmation naming how many).
class Amc1Fcl050ExportScreen extends ConsumerStatefulWidget {
  const Amc1Fcl050ExportScreen({super.key});

  @override
  ConsumerState<Amc1Fcl050ExportScreen> createState() =>
      _Amc1Fcl050ExportScreenState();
}

class _Amc1Fcl050ExportScreenState
    extends ConsumerState<Amc1Fcl050ExportScreen> {
  CalendarDate? _from;
  CalendarDate? _to;
  Future<List<ExportRecord>>? _overlapCheck;
  bool _busy = false;
  final _holderNameController = TextEditingController();
  final _licenceNumberController = TextEditingController();
  bool _holderFieldsLoaded = false;

  @override
  void dispose() {
    _holderNameController.dispose();
    _licenceNumberController.dispose();
    super.dispose();
  }

  void _prefillHolderFieldsOnce(PilotProfile? profile) {
    if (_holderFieldsLoaded || profile == null) return;
    _holderFieldsLoaded = true;
    _holderNameController.text = profile.holderName ?? '';
    _licenceNumberController.text = profile.primaryLicenceNumber ?? '';
  }

  Future<void> _saveHolderFieldsIfChanged(PilotProfile? currentProfile) async {
    final name = _holderNameController.text.trim();
    final licenceNumber = _licenceNumberController.text.trim();
    final base =
        currentProfile ??
        const PilotProfile(
          dateOfBirth: CalendarDate(1900, 1, 1),
          primaryJurisdictionId: 'eu.easa.part-fcl',
        );
    if (base.holderName == name && base.primaryLicenceNumber == licenceNumber) {
      return;
    }
    await ref
        .read(pilotProfileRepositoryProvider)
        .save(
          base.copyWith(
            holderName: name.isEmpty ? null : name,
            primaryLicenceNumber: licenceNumber.isEmpty ? null : licenceNumber,
          ),
        );
    ref.invalidate(pilotProfileProvider);
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final initial = (isFrom ? _from : _to) ?? _todayAsCalendarDate();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(initial.year, initial.month, initial.day),
      firstDate: DateTime(1900),
      lastDate: DateTime(2100),
    );
    if (picked == null) return;
    setState(() {
      final date = CalendarDate(picked.year, picked.month, picked.day);
      if (isFrom) {
        _from = date;
      } else {
        _to = date;
      }
      _overlapCheck = null;
      final from = _from;
      final to = _to;
      if (from != null && to != null && from <= to) {
        _overlapCheck = ref
            .read(exportRecordRepositoryProvider)
            .findOverlapping(
              format: _amc1Fcl050ExportFormatLabel,
              from: from,
              to: to,
            );
      }
    });
  }

  CalendarDate _todayAsCalendarDate() {
    final now = DateTime.now();
    return CalendarDate(now.year, now.month, now.day);
  }

  Future<Amc1Fcl050ExportPlan> _buildPlan(CalendarDate from, CalendarDate to) async {
    final easaProjection = await ref.read(easaProjectionProvider.future);
    return buildAmc1Fcl050ExportPlan(
      flightReadRepository: ref.read(flightReadRepositoryProvider),
      easaProjection: easaProjection,
      from: from,
      to: to,
    );
  }

  Future<void> _preview() async {
    final from = _from;
    final to = _to;
    if (from == null || to == null) return;

    setState(() => _busy = true);
    try {
      final plan = await _buildPlan(from, to);
      final document = await buildAmc1Fcl050Logbook(
        holderName: _holderNameController.text.trim(),
        holderLicenceNumber: _licenceNumberController.text.trim(),
        rows: plan.contentRows,
        openingBalance: plan.openingBalance,
        isDraftPreview: true,
      );
      final bytes = await document.save();

      final fileName = 'amc1_fcl050_preview_${from}_to_$to.pdf';
      final savedUri = await FilePicker.saveFile(
        fileName: fileName,
        bytes: Uint8List.fromList(bytes),
        mimeType: 'application/pdf',
        dialogTitle: 'Save preview PDF',
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (savedUri == null) return; // pilot cancelled the save dialog.
      _showMessage('Preview saved to $fileName. Nothing was sealed.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportAndSeal() async {
    final from = _from;
    final to = _to;
    if (from == null || to == null) return;

    setState(() => _busy = true);
    try {
      final plan = await _buildPlan(from, to);
      final currentProfile = await ref.read(pilotProfileProvider.future);
      await _saveHolderFieldsIfChanged(currentProfile);

      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Export & seal'),
          content: Text(
            plan.draftCount == 0
                ? 'No new drafts in this range. This will still generate '
                      'a PDF and record a new export entry, sealing '
                      'nothing further.'
                : 'This will seal ${plan.draftCount} draft flight(s) as '
                      'committed and immutable. This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Export & seal'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;

      final document = await buildAmc1Fcl050Logbook(
        holderName: _holderNameController.text.trim(),
        holderLicenceNumber: _licenceNumberController.text.trim(),
        rows: plan.contentRows,
        openingBalance: plan.openingBalance,
      );
      final bytes = await document.save();
      final fileName = 'amc1_fcl050_${from}_to_$to.pdf';

      final savedUri = await FilePicker.saveFile(
        fileName: fileName,
        bytes: Uint8List.fromList(bytes),
        mimeType: 'application/pdf',
        dialogTitle: 'Save $_amc1Fcl050ExportFormatLabel export',
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (savedUri == null) return; // pilot cancelled -- nothing sealed.

      final exportRecordId = await ref
          .read(exportRecordRepositoryProvider)
          .recordExport(format: _amc1Fcl050ExportFormatLabel, from: from, to: to);
      await ref
          .read(flightRepositoryProvider)
          .sealForExport(
            flightIds: plan.draftFlightIds,
            exportRecordId: exportRecordId,
          );

      _showMessage(
        '${plan.contentRows.length} flight(s) exported to $fileName; '
        '${plan.draftCount} sealed.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;
    final semantic = context.semanticColors;
    final from = _from;
    final to = _to;
    final rangeValid = from != null && to != null && from <= to;
    final profileAsync = ref.watch(pilotProfileProvider);
    profileAsync.whenData(_prefillHolderFieldsOnce);

    return Scaffold(
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 16, 4),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back),
                    tooltip: 'Back',
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                  Expanded(
                    child: Text(
                      'Export to $_amc1Fcl050ExportFormatLabel',
                      style: theme.textTheme.titleMedium,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
                children: [
                  TextField(
                    controller: _holderNameController,
                    decoration: const InputDecoration(labelText: "Holder's name"),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _licenceNumberController,
                    decoration: const InputDecoration(
                      labelText: "Holder's licence number",
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Choose a date range to export.',
                    style: theme.textTheme.bodyMedium?.copyWith(color: ink.muted),
                  ),
                  const SizedBox(height: 16),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('From'),
                    subtitle: Text(from?.toString() ?? 'Not set'),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () => _pickDate(isFrom: true),
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('To'),
                    subtitle: Text(to?.toString() ?? 'Not set'),
                    trailing: const Icon(Icons.calendar_today),
                    onTap: () => _pickDate(isFrom: false),
                  ),
                  if (from != null && to != null && from > to)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        'The "From" date must be on or before "To".',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ),
                  if (_overlapCheck != null)
                    FutureBuilder<List<ExportRecord>>(
                      future: _overlapCheck,
                      builder: (context, snapshot) {
                        final overlapping = snapshot.data ?? const [];
                        if (overlapping.isEmpty) return const SizedBox.shrink();
                        return Container(
                          margin: const EdgeInsets.only(top: 16),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: semantic.currencyWarningSurface,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            'This range overlaps ${overlapping.length} '
                            'previous export(s).',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: semantic.currencyWarning,
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: (rangeValid && !_busy) ? _preview : null,
                  child: const Text('Preview'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: (rangeValid && !_busy) ? _exportAndSeal : null,
                  child: _busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Export & Seal'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

Every provider referenced above (`pilotProfileProvider`, `pilotProfileRepositoryProvider`,
`flightReadRepositoryProvider`, `flightRepositoryProvider`, `exportRecordRepositoryProvider`,
`easaProjectionProvider`) already exists — the last from Task 6, the rest from
`repository_providers.dart`/`pilot_profile_providers.dart` — so no further new providers should
be needed. If `flutter analyze` flags any import as missing, add it from the same provider file
the existing `export_screen.dart` imports it from.

- [ ] **Step 2: Wire it into Settings**

Edit `lib/ui/settings/settings_screen.dart`. Add the import:

```dart
import '../io/amc1_fcl050_export_screen.dart';
```

Add a new row widget after `_ExportRow`:

```dart
class _Amc1Fcl050ExportRow extends StatelessWidget {
  const _Amc1Fcl050ExportRow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ink = context.inkTiers;

    return InkWell(
      onTap: () => Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => const Amc1Fcl050ExportScreen()),
      ),
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Print logbook (AMC1 FCL.050)', style: theme.textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(
                'PDF, range-scoped, seals drafts to committed',
                style: theme.textTheme.labelSmall?.copyWith(color: ink.faint),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
```

Add `const _Divider(),` and `const _Amc1Fcl050ExportRow(),` directly after the existing
`const _ExportRow(),` line in `_SettingsScreenState.build`'s `children` list.

- [ ] **Step 3: Write a smoke test for the screen**

```dart
import 'package:easa_digital_log/ui/io/amc1_fcl050_export_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('renders the date pickers and both export buttons', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(home: Amc1Fcl050ExportScreen()),
      ),
    );
    await tester.pump();

    expect(find.text('From'), findsOneWidget);
    expect(find.text('To'), findsOneWidget);
    expect(find.text('Preview'), findsOneWidget);
    expect(find.text('Export & Seal'), findsOneWidget);
  });
}
```

If this fails to pump because a provider this screen reads needs a real database connection
with no in-memory override, wrap the `ProviderScope` with the same override pattern an existing
widget test in `test/ui/io/` or `test/ui/settings/` already uses for `databaseProvider` — search
for `databaseProvider.overrideWith` in `test/ui/` and copy that pattern exactly rather than
inventing a new one.

- [ ] **Step 4: Run it to verify it fails, then passes**

Run (PowerShell): `flutter test test/ui/io/amc1_fcl050_export_screen_test.dart`
First confirm it fails before Step 1/2 are complete (missing file/class), then confirm PASS once
they are.

- [ ] **Step 5: Format, analyze, full suite**

Run (PowerShell):
```
dart format lib/ui/io/amc1_fcl050_export_screen.dart lib/ui/settings/settings_screen.dart test/ui/io/amc1_fcl050_export_screen_test.dart
flutter analyze lib/ui/ test/ui/io/amc1_fcl050_export_screen_test.dart
flutter test
```
Expected: clean.

- [ ] **Step 6: Manually run the app and exercise the screen**

Per this project's own UI-change convention: start the app, navigate Settings → Print logbook
(AMC1 FCL.050), and exercise the golden path (pick a range, Preview, Export & Seal) plus at
least one edge case (a range with zero drafts already sealed) before considering this task
done. Note in your final report whether this was possible in this environment or whether it had
to be skipped.

- [ ] **Step 7: Commit**

```bash
git add lib/ui/io/amc1_fcl050_export_screen.dart lib/ui/settings/settings_screen.dart \
  test/ui/io/amc1_fcl050_export_screen_test.dart
git commit -m "feat: AMC1 FCL.050 export screen (#83)

Date range -> overlap warning -> Preview (watermarked, no state
change) / Export & Seal (confirmation naming the draft count, then
seals atomically). Reached from Settings, next to the existing
ForeFlight export row. Holder name/licence number are editable inline
and saved back to PilotProfile, since nothing else in the app can set
them yet.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 9: Acceptance-criteria integration tests

**Files:**
- Test: `test/export/amc1_fcl050_export_sealing_test.dart` (new file — the literal acceptance
  criteria from the spec, exercised end-to-end against a real in-memory database, independent
  of the UI screen)

**Interfaces:**
- Consumes: everything from Tasks 3, 4, 6, 7 (`Amc1Fcl050ExportPlan`,
  `FlightRepository.sealForExport`, `ExportRecordRepository.recordExport`).

- [ ] **Step 1: Write the three failing tests**

Reuses Task 7's exact `_flightOn`/`_capacity` helpers and setup — copy that test file's
`import`s, `_capacity`, `_flightOn`, and `setUp`/`tearDown` verbatim into this new file (they're
deliberately identical) rather than re-deriving them, then add:

```dart
  test(
    'export seals exactly the flights in range, not flights outside it',
    () async {
      final inRangeId = await flights.createDraft(
        _flightOn(DateTime.utc(2026, 1, 15, 9)),
        aircraftId: aircraftId,
      );
      final outOfRangeId = await flights.createDraft(
        _flightOn(DateTime.utc(2026, 3, 1, 9)),
        aircraftId: aircraftId,
      );

      final plan = await buildAmc1Fcl050ExportPlan(
        flightReadRepository: flightReads,
        easaProjection: easaProjection,
        from: const CalendarDate(2026, 1, 1),
        to: const CalendarDate(2026, 1, 31),
      );
      expect(plan.draftFlightIds, [inRangeId]);

      await flights.sealForExport(
        flightIds: plan.draftFlightIds,
        exportRecordId: 'export-1',
      );

      final inRangeRow = await (db.select(
        db.flightsTable,
      )..where((t) => t.id.equals(inRangeId))).getSingle();
      expect(inRangeRow.committedAt, isNotNull);
      expect(inRangeRow.sealedByExportId, 'export-1');

      final outOfRangeRow = await (db.select(
        db.flightsTable,
      )..where((t) => t.id.equals(outOfRangeId))).getSingle();
      expect(outOfRangeRow.committedAt, isNull);
      expect(outOfRangeRow.sealedByExportId, isNull);
    },
  );

  test('a failed export seals nothing', () async {
    final draftId = await flights.createDraft(
      _flightOn(DateTime.utc(2026, 1, 15, 9)),
      aircraftId: aircraftId,
    );

    final plan = await buildAmc1Fcl050ExportPlan(
      flightReadRepository: flightReads,
      easaProjection: easaProjection,
      from: const CalendarDate(2026, 1, 1),
      to: const CalendarDate(2026, 1, 31),
    );
    expect(plan.draftFlightIds, [draftId]);

    // A failed export never reaches sealForExport at all -- the real
    // screen (Task 8) only calls it after a successful file write. Model
    // that failure by simply not calling it, and confirm the flight is
    // still draft. sealForExport's own mid-call atomicity (a partially
    // invalid flightIds list rolling back everything) is Task 3's own
    // "unknown flight id" test, not duplicated here.
    final row = await (db.select(
      db.flightsTable,
    )..where((t) => t.id.equals(draftId))).getSingle();
    expect(row.committedAt, isNull);
  });

  test('re-exporting an already-sealed range changes no state', () async {
    final draftId = await flights.createDraft(
      _flightOn(DateTime.utc(2026, 1, 15, 9)),
      aircraftId: aircraftId,
    );

    final firstPlan = await buildAmc1Fcl050ExportPlan(
      flightReadRepository: flightReads,
      easaProjection: easaProjection,
      from: const CalendarDate(2026, 1, 1),
      to: const CalendarDate(2026, 1, 31),
    );
    await flights.sealForExport(
      flightIds: firstPlan.draftFlightIds,
      exportRecordId: 'export-1',
    );
    final afterFirstSeal = await (db.select(
      db.flightsTable,
    )..where((t) => t.id.equals(draftId))).getSingle();

    final secondPlan = await buildAmc1Fcl050ExportPlan(
      flightReadRepository: flightReads,
      easaProjection: easaProjection,
      from: const CalendarDate(2026, 1, 1),
      to: const CalendarDate(2026, 1, 31),
    );
    expect(secondPlan.draftCount, 0);
    await flights.sealForExport(
      flightIds: secondPlan.draftFlightIds,
      exportRecordId: 'export-2',
    );

    final afterSecondSeal = await (db.select(
      db.flightsTable,
    )..where((t) => t.id.equals(draftId))).getSingle();
    expect(afterSecondSeal.committedAt, afterFirstSeal.committedAt);
    expect(afterSecondSeal.sealedByExportId, afterFirstSeal.sealedByExportId);
  });
```

- [ ] **Step 2: Run to verify they fail**

Run (PowerShell): `flutter test test/export/amc1_fcl050_export_sealing_test.dart`
Expected: FAIL initially (file doesn't exist / imports unresolved) until the real test bodies
from Step 1 are written, then each assertion should genuinely exercise real behavior — if any
of the three passes without a real assertion body, it is testing nothing; go back and write the
real body first.

- [ ] **Step 3: Run to verify they pass**

Run (PowerShell): `flutter test test/export/amc1_fcl050_export_sealing_test.dart`
Expected: PASS, all three.

- [ ] **Step 4: Format, analyze, full suite**

Run (PowerShell):
```
dart format test/export/amc1_fcl050_export_sealing_test.dart
flutter analyze test/export/
flutter test
```
Expected: clean, full suite green.

- [ ] **Step 5: Commit**

```bash
git add test/export/amc1_fcl050_export_sealing_test.dart
git commit -m "test: #83's three literal acceptance-criteria scenarios

Export seals exactly the flights in range; a failed export seals
nothing; re-exporting an already-sealed range changes no state.

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

### Task 10: Update the ADR and close out documentation

**Files:**
- Modify: `docs/adr/0003-draft-until-exported.md`

- [ ] **Step 1: Update the ADR's Consequences section**

Open `docs/adr/0003-draft-until-exported.md` and find the line this plan's own spec quoted:
*"Export becomes a state transition with side effects... rather than a pure read of
already-final data."* Add a short note directly after it (match the file's own existing prose
style — read the surrounding paragraph first):

```markdown
**Implemented in #83.** `FlightRepository.sealForExport` performs the transition; a flight
committed some other way (e.g. #58's immediate commit-on-save) is unaffected by an export that
later includes it — `FlightsTable.sealedByExportId`, separate from `committedAt`, distinguishes
"committed" from "committed because of this export."
```

- [ ] **Step 2: Commit**

```bash
git add docs/adr/0003-draft-until-exported.md
git commit -m "docs: note #83's sealedByExportId in ADR-0003

Co-Authored-By: Claude Sonnet 5 <noreply@anthropic.com>"
```

---

## Final verification

- [ ] Run the full suite one more time: `flutter test`
- [ ] Run `flutter analyze` with no path filters (whole project)
- [ ] Run `dart run tool/check_layering.dart` and `dart run tool/check_schema_snapshot.dart`
- [ ] Update GitHub issue #83: check off every acceptance-criteria box actually satisfied, note
  any that weren't (e.g. if Task 8 Step 6's manual run had to be skipped), and leave it open for
  the user to close after their own review — this plan's tasks don't include closing the issue.
