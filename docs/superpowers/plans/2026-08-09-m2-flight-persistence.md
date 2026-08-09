# M2 Flight Persistence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give `Flight` and `Aircraft` a real SQLite-backed home via `drift`, implementing the
draft/committed/tombstoned lifecycle and revision history from
`docs/superpowers/specs/2026-08-09-m2-flight-persistence-design.md` (issues #31, #32, #33, #34).

**Architecture:** A new `lib/data/` layer: Drift table definitions mirror the domain model
(flattening single nested value objects onto the owning row, child tables for variable-length
lists), mapper functions convert domain objects to rows, and `FlightRepository` (interface in
`lib/domain/repository/`, Drift implementation in `lib/data/`) is the sole write path enforcing
the draft/committed/tombstoned state machine. Plain reference data (`Aircraft`,
`custom_aerodromes`) gets simple upsert repositories with no lifecycle.

**Tech Stack:** `drift` + `sqlite3_flutter_libs` (added this milestone per ADR-0006), `freezed`
(existing), `flutter_test` with `NativeDatabase.memory()` for real-database tests (no mocks).

## Global Constraints

- All primary keys are ULIDs (26-char Crockford base32: 48-bit ms timestamp + 80-bit random),
  `text` columns, generated client-side — never autoincrement integers (spec's "Identifiers"
  section, added for future sync compatibility).
- Every persisted instant (`UtcInstant`) is an `integer` column storing
  `millisecondsSinceEpoch` (UTC). Every persisted calendar date (`CalendarDate`) is a `text`
  column storing `CalendarDate.toString()`'s `YYYY-MM-DD` form, read back via
  `CalendarDate.parse`.
- Every persisted enum is stored as its Dart `.name` string, read back via
  `EnumType.values.byName(...)`.
- `FlightRepository` (interface in `lib/domain/repository/flight_repository.dart`, Drift
  implementation in `lib/data/repositories/flight_repository_drift.dart`) is the **only** path
  allowed to write the `flights` table — no task may call `_db.into(_db.flightsTable))` or
  `_db.update(_db.flightsTable)` outside that one implementation file (#32's "no raw DAO
  bypasses the state machine").
- `lib/domain/repository/flight_repository.dart` is the only new file this plan adds under
  `lib/domain/` — it is plain Dart (no Drift, no Flutter imports) so
  `dart run tool/check_layering.dart` stays clean. Everything else lives under `lib/data/`.
- Tests run against a real in-memory Drift database (`NativeDatabase.memory()`), never a mock —
  matching how the rest of this codebase tests (fixture-based, real behaviour).
- Known, documented limitation carried into this plan: editing a committed flight's `route` or
  `approaches` replaces those child rows but does **not** capture their prior values in
  `flight_revisions.changed_fields` (only the flattened `flights` row's columns are diffed).
  This matches the spec's own Testing section, which only requires the flattened-row diff to be
  correct. If prior route/approach values on a committed flight turn out to matter, that is a
  follow-up issue, not a silent gap — do not attempt to fix it in this plan without checking in
  first.
- Drift's exact method/parameter names (`insertOnConflictUpdate`, `.references(...)`,
  `KeyAction.cascade`, generated table-getter and Companion naming) are written below from
  current documentation. If codegen or `flutter analyze` reports a different exact name for the
  installed version, that is expected minor API drift, not a design problem — adjust the call
  site to match, do not change the schema or the state-machine logic to work around it.

---

## Task 1: Migrate credential-expiry fields to `CalendarDate`

The M2 spec stores `*_credential_expiry` columns using the `CalendarDate` type (#29), but the
domain model still types `InstructorPresence.credentialExpiry` and
`Countersignature.signatoryCredentialExpiry` as `UtcInstant?`, with a dartdoc note saying this is
provisional pending #29. #29 has since landed (`CalendarDate` exists), so this task finishes that
migration before the persistence schema is built on top of it — building the schema against the
wrong domain type would need reworking the whole flight mapper later.

**Files:**
- Modify: `lib/domain/model/calendar_date.dart`
- Modify: `lib/domain/model/instructor_presence.dart`
- Modify: `lib/domain/model/countersignature.dart`
- Modify: `test/fixtures/decoders/pilot_capacity_fixture.dart`
- Modify: `test/fixtures/capacities/sole_manipulator_receiving_instruction.yaml`
- Test: `test/domain/model/calendar_date_test.dart`

**Interfaces:**
- Produces: `CalendarDate.parse(String source)` — throws `FormatException` on malformed input.
  `InstructorPresence.credentialExpiry` and `Countersignature.signatoryCredentialExpiry` are now
  `CalendarDate?`.

- [ ] **Step 1: Write the failing test for `CalendarDate.parse`**

Add to `test/domain/model/calendar_date_test.dart`, inside the existing `group('CalendarDate', ...)`:

```dart
    test('parses YYYY-MM-DD, round-tripping toString', () {
      expect(CalendarDate.parse('2026-01-05'), const CalendarDate(2026, 1, 5));
      expect(
        CalendarDate.parse(const CalendarDate(2027, 12, 31).toString()),
        const CalendarDate(2027, 12, 31),
      );
    });

    test('rejects malformed input', () {
      for (final bad in ['2026-1-5', '2026/01/05', '05-01-2026', '', 'abc']) {
        expect(
          () => CalendarDate.parse(bad),
          throwsFormatException,
          reason: bad,
        );
      }
    });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/model/calendar_date_test.dart`
Expected: FAIL — `CalendarDate.parse` is not defined.

- [ ] **Step 3: Add `CalendarDate.parse`**

In `lib/domain/model/calendar_date.dart`, add above the `compareTo` method:

```dart
  /// Parses a zero-padded `YYYY-MM-DD` string — the exact form [toString]
  /// produces. Throws [FormatException] naming [source] if malformed.
  factory CalendarDate.parse(String source) {
    final match = _pattern.firstMatch(source);
    if (match == null) {
      throw FormatException('Not a valid YYYY-MM-DD calendar date', source);
    }
    return CalendarDate(
      int.parse(match.group(1)!),
      int.parse(match.group(2)!),
      int.parse(match.group(3)!),
    );
  }

  static final RegExp _pattern = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$');
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/domain/model/calendar_date_test.dart`
Expected: PASS

- [ ] **Step 5: Migrate `InstructorPresence.credentialExpiry`**

In `lib/domain/model/instructor_presence.dart`, change the import from
`import 'utc_instant.dart';` to `import 'calendar_date.dart';`, and change the field:

```dart
    /// Certificate expiry. `§61.51(h)(2)(ii)` requires it on an FAA training
    /// endorsement; EASA has no equivalent, so it is routinely null on an
    /// EASA-only flight.
    CalendarDate? credentialExpiry,
```

Remove the now-stale trailing sentence in that same doc comment ("A calendar date held as a
`UtcInstant` until issue #29 adds a calendar-date type — rule 3 forbids a naive local value
meanwhile.") since #29 has landed and the field now uses `CalendarDate` directly.

- [ ] **Step 6: Migrate `Countersignature.signatoryCredentialExpiry`**

In `lib/domain/model/countersignature.dart`, change the import from `import 'utc_instant.dart';`
to `import 'calendar_date.dart';`, and change the field:

```dart
    /// The signatory's certificate expiry. `§61.51(h)(2)(ii)`; normally null
    /// on an EASA-only entry.
    CalendarDate? signatoryCredentialExpiry,
```

`Countersignature.signedAt` stays `UtcInstant?` — it is an instant (signing happens at a moment),
not a calendar date. Only the two `*Expiry` fields change.

- [ ] **Step 7: Regenerate freezed code**

Run: `flutter pub run build_runner build`
Expected: regenerates `instructor_presence.freezed.dart` and `countersignature.freezed.dart`
with no errors.

- [ ] **Step 8: Update the fixture decoder**

In `test/fixtures/decoders/pilot_capacity_fixture.dart`, add this helper near `_instant`
(same file, same style):

```dart
CalendarDate? _date(YamlMap yaml, String key, String fixture) {
  final value = optionalString(yaml, key, fixture);
  if (value == null) {
    return null;
  }
  try {
    return CalendarDate.parse(value);
  } on FormatException {
    throw FixtureFieldException(fixture, key, 'a quoted "YYYY-MM-DD", got "$value"');
  }
}
```

Add `import 'package:easa_digital_log/domain/model/calendar_date.dart';` to the file's imports.

Change the two call sites:
- `credentialExpiry: _instant(yaml, 'credential_expiry', fixture),` →
  `credentialExpiry: _date(yaml, 'credential_expiry', fixture),`
- `signatoryCredentialExpiry: _instant(yaml, 'signatory_credential_expiry', fixture),` →
  `signatoryCredentialExpiry: _date(yaml, 'signatory_credential_expiry', fixture),`

- [ ] **Step 9: Update the fixture YAML**

In `test/fixtures/capacities/sole_manipulator_receiving_instruction.yaml`, change:
- `credential_expiry: "2027-05-31T23:59:59Z"` → `credential_expiry: "2027-05-31"`
- `signatory_credential_expiry: "2027-05-31T23:59:59Z"` → `signatory_credential_expiry: "2027-05-31"`

- [ ] **Step 10: Run the full domain test suite and static checks**

Run, in order:
```powershell
dart format --set-exit-if-changed .
flutter analyze --fatal-infos
dart run tool/check_layering.dart
dart run tool/check_domain_types.dart
flutter test
```
Expected: all clean, all green — `pilot_capacity_test.dart` and the capacity fixture tests must
still pass unchanged, since they read `credentialExpiry` through an `Object? Function` closure
that doesn't care about the concrete type.

- [ ] **Step 11: Commit**

```bash
git add lib/domain/model/calendar_date.dart lib/domain/model/instructor_presence.dart lib/domain/model/countersignature.dart lib/domain/model/instructor_presence.freezed.dart lib/domain/model/countersignature.freezed.dart test/domain/model/calendar_date_test.dart test/fixtures/decoders/pilot_capacity_fixture.dart test/fixtures/capacities/sole_manipulator_receiving_instruction.yaml
git commit -m "feat: store credential expiry as CalendarDate, not UtcInstant (#29 follow-up)"
```

---

## Task 2: Add Drift dependencies and a ULID generator

**Files:**
- Modify: `pubspec.yaml`
- Create: `lib/data/ulid.dart`
- Test: `test/data/ulid_test.dart`

**Interfaces:**
- Produces: `String generateUlid({DateTime? now, Random? random})` — a 26-character Crockford
  base32 ULID. Every later task's mappers and repositories call this with no arguments in
  production code; the optional parameters exist for deterministic tests.

- [ ] **Step 1: Add the dependencies**

Run:
```powershell
flutter pub add drift sqlite3_flutter_libs
flutter pub add -d drift_dev
```
This resolves current compatible versions automatically, consistent with ADR-0006 ("drift and
sqlite3_flutter_libs are deferred to M2" — this is that milestone). Do not hand-pick version
numbers.

- [ ] **Step 2: Write the failing test**

Create `test/data/ulid_test.dart`:

```dart
import 'dart:math';

import 'package:easa_digital_log/data/ulid.dart';
import 'package:flutter_test/flutter_test.dart';

final RegExp _ulidPattern = RegExp(r'^[0-9A-HJKMNP-TV-Z]{26}$');

void main() {
  group('generateUlid', () {
    test('produces a 26-character Crockford base32 string', () {
      final ulid = generateUlid();
      expect(ulid, matches(_ulidPattern));
    });

    test('is unique across a burst of same-millisecond generation', () {
      final fixedNow = DateTime.utc(2026, 8, 9, 12, 0, 0);
      final ulids = List.generate(
        1000,
        (_) => generateUlid(now: fixedNow, random: Random.secure()),
      );
      expect(ulids.toSet(), hasLength(1000));
    });

    test('the timestamp portion is chronologically sortable', () {
      final earlier = generateUlid(now: DateTime.utc(2026, 1, 1));
      final later = generateUlid(now: DateTime.utc(2026, 6, 1));
      expect(earlier.substring(0, 10).compareTo(later.substring(0, 10)) < 0, isTrue);
    });
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/data/ulid_test.dart`
Expected: FAIL — `package:easa_digital_log/data/ulid.dart` does not exist.

- [ ] **Step 4: Implement the ULID generator**

Create `lib/data/ulid.dart`:

```dart
import 'dart:math';

/// Generates a [ULID](https://github.com/ulid/spec): a 26-character
/// Crockford base32 string encoding a 48-bit millisecond UTC timestamp
/// followed by 80 bits of randomness.
///
/// Used as the primary key for every table in `lib/data/` instead of an
/// autoincrement integer — see the "Identifiers" section of
/// `docs/superpowers/specs/2026-08-09-m2-flight-persistence-design.md`.
/// Two offline devices can each mint an id with no coordination and no
/// collision, which an autoincrement integer cannot offer once multi-device
/// sync exists (ADR-0005: sync is an additive layer, not being built yet,
/// but the ID scheme has to be right from the first row ever written).
///
/// [now] and [random] are injectable for deterministic tests only —
/// production call sites pass neither.
String generateUlid({DateTime? now, Random? random}) {
  final millis = (now ?? DateTime.now().toUtc()).millisecondsSinceEpoch;
  final rand = random ?? Random.secure();

  final chars = List<String>.filled(26, '0');
  var time = millis;
  for (var i = 9; i >= 0; i--) {
    chars[i] = _crockford[time & 0x1F];
    time >>= 5;
  }
  for (var i = 10; i < 26; i++) {
    chars[i] = _crockford[rand.nextInt(32)];
  }

  return chars.join();
}

/// Crockford's base32 alphabet: excludes I, L, O, U to avoid visual
/// confusion with 1, 1, 0, V.
const String _crockford = '0123456789ABCDEFGHJKMNPQRSTVWXYZ';
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/data/ulid_test.dart`
Expected: PASS

- [ ] **Step 6: Confirm layering is unaffected**

Run: `dart run tool/check_layering.dart`
Expected: clean — `lib/data/ulid.dart` is outside `lib/domain/`, so this guard doesn't scan it at
all; this step just confirms nothing else broke.

- [ ] **Step 7: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/data/ulid.dart test/data/ulid_test.dart
git commit -m "feat: add drift dependency and a ULID id generator (#31)"
```

---

## Task 3: Drift schema — all eight tables, `AppDatabase`, and the derived-quantity sweep

**Files:**
- Create: `lib/data/tables/aircraft_tables.dart`
- Create: `lib/data/tables/custom_aerodrome_table.dart`
- Create: `lib/data/tables/flight_tables.dart`
- Create: `lib/data/database.dart`
- Test: `test/data/schema_derived_quantity_test.dart`
- Test: `test/data/database_test.dart`

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces: `AppDatabase(QueryExecutor executor)`, with generated table getters
  `_db.aircraftsTable`, `_db.aircraftQualificationJurisdictionsTable`,
  `_db.aircraftRequiredQualificationsTable`, `_db.customAerodromesTable`, `_db.flightsTable`,
  `_db.flightRouteLegsTable`, `_db.flightApproachesTable`, `_db.flightRevisionsTable`, and
  generated row classes `AircraftRow`, `AircraftQualificationJurisdictionRow`,
  `AircraftRequiredQualificationRow`, `CustomAerodromeRow`, `FlightRow`, `FlightRouteLegRow`,
  `FlightApproachRow`, `FlightRevisionRow`. Later tasks depend on these exact names.

Wiring a real on-device database file (choosing the platform documents directory, opening a
`NativeDatabase` against it) is UI/app-wiring work with no consumer yet — out of scope here.
`AppDatabase` takes a `QueryExecutor` in its constructor so tests pass `NativeDatabase.memory()`
and a future app-startup task passes a real file-backed one.

- [ ] **Step 1: Aircraft tables**

Create `lib/data/tables/aircraft_tables.dart`:

```dart
import 'package:drift/drift.dart';

/// Mirrors `Aircraft` (#12) — "a current, editable reference record," no
/// draft/committed lifecycle, unlike `flights`.
@DataClassName('AircraftRow')
class AircraftsTable extends Table {
  @override
  String get tableName => 'aircraft';

  TextColumn get id => text()();
  TextColumn get registration => text().unique()();
  TextColumn get manufacturer => text()();
  TextColumn get model => text()();
  TextColumn get icaoTypeDesignator => text().nullable()();
  TextColumn get category => text()();
  TextColumn get engineType => text()();
  IntColumn get engineCount => integer()();
  TextColumn get operatingSurface => text()();
  BoolColumn get requiresMultiCrew => boolean()();
  TextColumn get typeRatingDesignator => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// One row per jurisdiction an aircraft has been configured for, present
/// even when [AircraftRequiredQualificationsTable] holds no rows for it —
/// the absent-vs-empty distinction `aircraft_test.dart` guards. See the M2
/// design spec's "aircraft_qualification_jurisdictions" section.
@DataClassName('AircraftQualificationJurisdictionRow')
class AircraftQualificationJurisdictionsTable extends Table {
  @override
  String get tableName => 'aircraft_qualification_jurisdictions';

  TextColumn get aircraftId =>
      text().references(AircraftsTable, #id, onDelete: KeyAction.cascade)();
  TextColumn get jurisdictionId => text()();

  @override
  Set<Column> get primaryKey => {aircraftId, jurisdictionId};
}

@DataClassName('AircraftRequiredQualificationRow')
class AircraftRequiredQualificationsTable extends Table {
  @override
  String get tableName => 'aircraft_required_qualifications';

  TextColumn get aircraftId =>
      text().references(AircraftsTable, #id, onDelete: KeyAction.cascade)();
  TextColumn get jurisdictionId => text()();
  TextColumn get qualification => text()();

  @override
  Set<Column> get primaryKey => {aircraftId, jurisdictionId, qualification};
}
```

- [ ] **Step 2: Custom aerodrome table**

Create `lib/data/tables/custom_aerodrome_table.dart`:

```dart
import 'package:drift/drift.dart';

/// Pilot-defined aerodromes (private strips, unlicensed fields) — the
/// bundled ~85,000-row OurAirports dataset stays a runtime-loaded asset and
/// is never written here. Plain reference data, no lifecycle.
@DataClassName('CustomAerodromeRow')
class CustomAerodromesTable extends Table {
  @override
  String get tableName => 'custom_aerodromes';

  TextColumn get id => text()();
  TextColumn get icaoCode => text().nullable()();
  TextColumn get iataCode => text().nullable()();
  TextColumn get name => text()();
  RealColumn get latitude => real()();
  RealColumn get longitude => real()();
  IntColumn get elevationFt => integer().nullable()();
  TextColumn get isoCountry => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
```

- [ ] **Step 3: Flight tables**

Create `lib/data/tables/flight_tables.dart`:

```dart
import 'package:drift/drift.dart';

import 'aircraft_tables.dart';

/// One row per flight, current state only. `committedAt`/`tombstonedAt`
/// double as both the state flag and the instant of that state change — see
/// the M2 design spec's "Lifecycle" section. Only
/// `FlightRepository`/`DriftFlightRepository` may write this table.
@DataClassName('FlightRow')
class FlightsTable extends Table {
  @override
  String get tableName => 'flights';

  TextColumn get id => text()();
  TextColumn get aircraftId => text().references(AircraftsTable, #id)();
  BoolColumn get prePlannedNavigation => boolean()();
  IntColumn get offBlocks => integer()();
  IntColumn get onBlocks => integer()();
  IntColumn get takeoff => integer().nullable()();
  IntColumn get landing => integer().nullable()();
  TextColumn get otherPilotName => text().nullable()();
  TextColumn get otherPilotCredentialNumber => text().nullable()();
  BoolColumn get carryingPassengers => boolean()();

  // Flattened CircuitCounts, ×2 (takeoffs, landings).
  IntColumn get takeoffsDayFullStop => integer()();
  IntColumn get takeoffsDayTouchAndGo => integer()();
  IntColumn get takeoffsNightFullStop => integer()();
  IntColumn get takeoffsNightTouchAndGo => integer()();
  IntColumn get landingsDayFullStop => integer()();
  IntColumn get landingsDayTouchAndGo => integer()();
  IntColumn get landingsNightFullStop => integer()();
  IntColumn get landingsNightTouchAndGo => integer()();

  BoolColumn get ifrFlightPlanFiled => boolean()();
  IntColumn get actualInstrumentMinutes => integer()();
  IntColumn get simulatedInstrumentMinutes => integer()();
  IntColumn get holdingProceduresCount => integer()();
  BoolColumn get trackingPerformed => boolean()();

  TextColumn get seriesGroupId => text().nullable()();
  TextColumn get airworthinessBasis => text().nullable()();
  TextColumn get remarks => text()();

  // Flattened PilotCapacity.
  BoolColumn get capacityCommandAuthority => boolean()();
  BoolColumn get capacitySoleManipulator => boolean()();
  BoolColumn get capacitySoleOccupant => boolean()();
  BoolColumn get capacityMultiPilotOperation => boolean()();
  BoolColumn get capacityAdditionalCrewRequiredByRule => boolean()();
  BoolColumn get capacityActingAsInstructor => boolean()();
  BoolColumn get capacityActingAsExaminer => boolean()();
  BoolColumn get capacityPicusClaimed => boolean()();
  BoolColumn get capacityPicInterventionNotRequired => boolean()();
  IntColumn get capacityManipulationTimeMinutes => integer().nullable()();
  BoolColumn get capacitySoloEndorsementHeld => boolean().nullable()();
  TextColumn get capacityEndorsingInstructorName => text().nullable()();

  // Flattened PilotCapacity.instructor (InstructorPresence?).
  TextColumn get capacityInstructorCapacity => text().nullable()();
  BoolColumn get capacityInstructorInfluencedFlight => boolean().nullable()();
  TextColumn get capacityInstructorName => text().nullable()();
  TextColumn get capacityInstructorCredentialNumber => text().nullable()();
  TextColumn get capacityInstructorCredentialExpiry => text().nullable()();

  TextColumn get capacityOtherPilotRole => text().nullable()();

  // Flattened PilotCapacity.countersignature (Countersignature?).
  TextColumn get capacityCountersignatureStatus => text().nullable()();
  TextColumn get capacityCountersignatureSignatoryName => text().nullable()();
  TextColumn get capacityCountersignatureSignatoryCredentialNumber =>
      text().nullable()();
  TextColumn get capacityCountersignatureSignatoryCredentialExpiry =>
      text().nullable()();
  IntColumn get capacityCountersignatureSignedAt => integer().nullable()();

  IntColumn get committedAt => integer().nullable()();
  IntColumn get tombstonedAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('FlightRouteLegRow')
class FlightRouteLegsTable extends Table {
  @override
  String get tableName => 'flight_route_legs';

  TextColumn get id => text()();
  TextColumn get flightId =>
      text().references(FlightsTable, #id, onDelete: KeyAction.cascade)();
  IntColumn get sequence => integer()();
  TextColumn get identifier => text()();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('FlightApproachRow')
class FlightApproachesTable extends Table {
  @override
  String get tableName => 'flight_approaches';

  TextColumn get id => text()();
  TextColumn get flightId =>
      text().references(FlightsTable, #id, onDelete: KeyAction.cascade)();
  TextColumn get type => text()();
  TextColumn get aerodromeIcao => text()();
  TextColumn get runway => text()();
  IntColumn get count => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// One row per edit event on a committed flight — not per changed field, so
/// a revision's `reason` and `recordedAt` apply to the whole edit. Never
/// cascades on flight deletion: a committed flight is never hard-deleted
/// (see "Deleting a committed flight" in the design spec), so its revisions
/// always outlive it.
@DataClassName('FlightRevisionRow')
class FlightRevisionsTable extends Table {
  @override
  String get tableName => 'flight_revisions';

  TextColumn get id => text()();
  TextColumn get flightId => text().references(FlightsTable, #id)();
  IntColumn get recordedAt => integer()();
  TextColumn get kind => text()();
  TextColumn get reason => text().nullable()();
  TextColumn get changedFields => text()();

  @override
  Set<Column> get primaryKey => {id};
}
```

- [ ] **Step 4: `AppDatabase`**

Create `lib/data/database.dart`:

```dart
import 'package:drift/drift.dart';

import 'tables/aircraft_tables.dart';
import 'tables/custom_aerodrome_table.dart';
import 'tables/flight_tables.dart';

part 'database.g.dart';

@DriftDatabase(
  tables: [
    AircraftsTable,
    AircraftQualificationJurisdictionsTable,
    AircraftRequiredQualificationsTable,
    CustomAerodromesTable,
    FlightsTable,
    FlightRouteLegsTable,
    FlightApproachesTable,
    FlightRevisionsTable,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.executor);

  @override
  int get schemaVersion => 1;
}
```

- [ ] **Step 5: Generate Drift code**

Run: `flutter pub run build_runner build`
Expected: generates `lib/data/database.g.dart` with no errors. If it reports an unresolved
`KeyAction` or `.references` signature, check the installed `drift` version's migration guide —
adjust the call, not the schema.

- [ ] **Step 6: Write and run the schema smoke test**

Create `test/data/database_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:easa_digital_log/data/database.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('opens an in-memory database with all eight tables', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);

    expect(db.allTables, hasLength(8));
  });
}
```

Run: `flutter test test/data/database_test.dart`
Expected: PASS. If it fails to load the native SQLite library, see the note at the end of this
task.

- [ ] **Step 7: Write and run the derived-quantity sweep**

Create `test/data/schema_derived_quantity_test.dart`:

```dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Mirrors the list `flight_test.dart` guards on `Flight` itself — a
/// derived quantity must never become a stored column either, per
/// ADR-0001. This is the schema-level half of #31's "the model exposes no
/// field whose name matches a derived-quantity pattern" acceptance
/// criterion.
const List<String> _derivedQuantityNames = <String>[
  'picTime',
  'dualTime',
  'nightTime',
  'crossCountryTime',
  'totalTime',
  'picusTime',
  'spicTime',
];

const List<String> _tableFiles = <String>[
  'lib/data/tables/aircraft_tables.dart',
  'lib/data/tables/custom_aerodrome_table.dart',
  'lib/data/tables/flight_tables.dart',
];

void main() {
  test('no Drift table column name matches a derived-quantity pattern', () {
    for (final path in _tableFiles) {
      final source = File(path).readAsStringSync();
      for (final name in _derivedQuantityNames) {
        expect(
          RegExp('\\b$name\\b', caseSensitive: false).hasMatch(source),
          isFalse,
          reason: '$path stores a column matching "$name" — see ADR-0001',
        );
      }
    }
  });
}
```

Run: `flutter test test/data/schema_derived_quantity_test.dart`
Expected: PASS.

**If `NativeDatabase.memory()` fails to load the native SQLite library:** this project's CI runs
on `ubuntu-latest`, which ships a system `libsqlite3` that `package:sqlite3`'s FFI binding finds
automatically — CI should just work. Locally on Windows, `flutter test` runs as a plain Dart VM
process outside the Flutter engine's asset system, so `sqlite3_flutter_libs`'s bundled DLL may
not be found. If you hit an `Invalid argument(s): Failed to load dynamic library` or similar on
Windows: this is a known ecosystem gap, not a schema bug. Check in with the user before spending
time on it rather than guessing at a fix — it may just mean running tests via CI/WSL locally
instead of native Windows `flutter test` for this test file.

- [ ] **Step 8: Full local verification**

```powershell
dart format --set-exit-if-changed .
flutter analyze --fatal-infos
dart run tool/check_layering.dart
dart run tool/check_domain_types.dart
flutter test
```
Expected: all clean.

- [ ] **Step 9: Commit**

```bash
git add lib/data/ test/data/
git commit -m "feat: Drift schema for flights, aircraft and custom aerodromes (#31)"
```

---

## Task 4: Aircraft persistence — mapper and repository

**Files:**
- Create: `lib/data/mappers/aircraft_mapper.dart`
- Create: `lib/data/repositories/aircraft_repository.dart`
- Test: `test/data/repositories/aircraft_repository_test.dart`

**Interfaces:**
- Consumes: `AppDatabase`, `AircraftRow`, `generateUlid()` (Task 2/3).
- Produces: `AircraftRow aircraftToRow(domain.Aircraft aircraft, {required String id})`,
  `domain.Aircraft aircraftFromRow(AircraftRow row, Map<String, Set<domain.AircraftQualification>> requiredQualifications)`,
  `class AircraftRepository` with `Future<String> upsert(domain.Aircraft aircraft, {String? id})`,
  `Future<domain.Aircraft?> find(String id)`, `Future<void> delete(String id)`. `Task 6/7`'s
  `createDraft`/`updateCommitted` take an `aircraftId` as a plain `String` and never call this
  repository directly — it exists for whatever eventually manages the aircraft list (#12 UI,
  not part of this plan), and for this task's own tests to set up an aircraft row a flight can
  reference.

- [ ] **Step 1: Write the failing test**

Create `test/data/repositories/aircraft_repository_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:easa_digital_log/data/database.dart';
import 'package:easa_digital_log/data/repositories/aircraft_repository.dart';
import 'package:easa_digital_log/domain/model/aircraft.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late AircraftRepository repository;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = AircraftRepository(db);
  });

  tearDown(() => db.close());

  const c152 = Aircraft(
    registration: 'G-ABCD',
    manufacturer: 'Cessna',
    model: '152',
    category: AircraftCategory.aeroplane,
    engineType: EngineType.piston,
    engineCount: 1,
    operatingSurface: OperatingSurface.land,
    requiresMultiCrew: false,
    requiredQualifications: {
      'eu.easa.part-fcl': {},
      'us.faa.part61': {AircraftQualification.faaHighPerformance},
    },
  );

  test('round-trips through upsert and find, including the absent-vs-empty '
      'jurisdiction distinction', () async {
    final id = await repository.upsert(c152);
    final found = await repository.find(id);

    expect(found, c152);
    expect(
      found!.requiredQualifications.containsKey('eu.easa.part-fcl'),
      isTrue,
      reason: 'present-but-empty must survive the round trip',
    );
    expect(found.requiredQualifications['eu.easa.part-fcl'], isEmpty);
    expect(
      found.requiredQualifications.containsKey('uk.caa.part-fcl'),
      isFalse,
      reason: 'never-configured must stay absent, not an empty set',
    );
  });

  test('upsert with an existing id replaces the row and its qualifications', () async {
    final id = await repository.upsert(c152);
    final updated = c152.copyWith(
      requiredQualifications: {'eu.easa.part-fcl': {AircraftQualification.easaTailwheel}},
    );

    await repository.upsert(updated, id: id);
    final found = await repository.find(id);

    expect(found!.requiredQualifications, updated.requiredQualifications);
  });

  test('delete removes the aircraft and its qualification rows', () async {
    final id = await repository.upsert(c152);
    await repository.delete(id);

    expect(await repository.find(id), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/repositories/aircraft_repository_test.dart`
Expected: FAIL — `aircraft_mapper.dart` and `aircraft_repository.dart` don't exist yet.

- [ ] **Step 3: Implement the mapper**

Create `lib/data/mappers/aircraft_mapper.dart`:

```dart
import '../../domain/model/aircraft.dart' as domain;
import '../tables/aircraft_tables.dart';

AircraftRow aircraftToRow(domain.Aircraft aircraft, {required String id}) {
  return AircraftRow(
    id: id,
    registration: aircraft.registration,
    manufacturer: aircraft.manufacturer,
    model: aircraft.model,
    icaoTypeDesignator: aircraft.icaoTypeDesignator,
    category: aircraft.category.name,
    engineType: aircraft.engineType.name,
    engineCount: aircraft.engineCount,
    operatingSurface: aircraft.operatingSurface.name,
    requiresMultiCrew: aircraft.requiresMultiCrew,
    typeRatingDesignator: aircraft.typeRatingDesignator,
  );
}

domain.Aircraft aircraftFromRow(
  AircraftRow row,
  Map<String, Set<domain.AircraftQualification>> requiredQualifications,
) {
  return domain.Aircraft(
    registration: row.registration,
    manufacturer: row.manufacturer,
    model: row.model,
    icaoTypeDesignator: row.icaoTypeDesignator,
    category: domain.AircraftCategory.values.byName(row.category),
    engineType: domain.EngineType.values.byName(row.engineType),
    engineCount: row.engineCount,
    operatingSurface: domain.OperatingSurface.values.byName(row.operatingSurface),
    requiresMultiCrew: row.requiresMultiCrew,
    typeRatingDesignator: row.typeRatingDesignator,
    requiredQualifications: requiredQualifications,
  );
}
```

- [ ] **Step 4: Implement the repository**

Create `lib/data/repositories/aircraft_repository.dart`:

```dart
import 'package:drift/drift.dart';

import '../../domain/model/aircraft.dart' as domain;
import '../database.dart';
import '../mappers/aircraft_mapper.dart';
import '../tables/aircraft_tables.dart';
import '../ulid.dart';

/// Write access to aircraft reference data. No draft/committed lifecycle —
/// `Aircraft` is "a current, editable reference record," unlike `Flight`.
class AircraftRepository {
  AircraftRepository(this._db);

  final AppDatabase _db;

  /// Inserts a new aircraft (returning its generated id), or replaces the
  /// row and its qualification rows when [id] names one already stored.
  Future<String> upsert(domain.Aircraft aircraft, {String? id}) {
    final resolvedId = id ?? generateUlid();

    return _db.transaction(() async {
      await _db
          .into(_db.aircraftsTable)
          .insertOnConflictUpdate(aircraftToRow(aircraft, id: resolvedId));

      await (_db.delete(_db.aircraftQualificationJurisdictionsTable)
            ..where((t) => t.aircraftId.equals(resolvedId)))
          .go();
      await (_db.delete(_db.aircraftRequiredQualificationsTable)
            ..where((t) => t.aircraftId.equals(resolvedId)))
          .go();

      for (final entry in aircraft.requiredQualifications.entries) {
        await _db.into(_db.aircraftQualificationJurisdictionsTable).insert(
          AircraftQualificationJurisdictionRow(
            aircraftId: resolvedId,
            jurisdictionId: entry.key,
          ),
        );
        for (final qualification in entry.value) {
          await _db.into(_db.aircraftRequiredQualificationsTable).insert(
            AircraftRequiredQualificationRow(
              aircraftId: resolvedId,
              jurisdictionId: entry.key,
              qualification: qualification.name,
            ),
          );
        }
      }

      return resolvedId;
    });
  }

  Future<domain.Aircraft?> find(String id) async {
    final row = await (_db.select(_db.aircraftsTable)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) {
      return null;
    }

    final jurisdictionRows = await (_db.select(_db.aircraftQualificationJurisdictionsTable)
          ..where((t) => t.aircraftId.equals(id)))
        .get();
    final qualificationRows = await (_db.select(_db.aircraftRequiredQualificationsTable)
          ..where((t) => t.aircraftId.equals(id)))
        .get();

    final requiredQualifications = <String, Set<domain.AircraftQualification>>{
      for (final j in jurisdictionRows) j.jurisdictionId: <domain.AircraftQualification>{},
    };
    for (final q in qualificationRows) {
      requiredQualifications[q.jurisdictionId]!.add(
        domain.AircraftQualification.values.byName(q.qualification),
      );
    }

    return aircraftFromRow(row, requiredQualifications);
  }

  Future<void> delete(String id) =>
      (_db.delete(_db.aircraftsTable)..where((t) => t.id.equals(id))).go();
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/data/repositories/aircraft_repository_test.dart`
Expected: PASS

- [ ] **Step 6: Full local verification**

```powershell
dart format --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test
```

- [ ] **Step 7: Commit**

```bash
git add lib/data/mappers/aircraft_mapper.dart lib/data/repositories/aircraft_repository.dart test/data/repositories/aircraft_repository_test.dart
git commit -m "feat: aircraft persistence with the absent-vs-empty qualification split (#31)"
```

---

## Task 5: Custom aerodrome persistence — mapper and repository

**Files:**
- Create: `lib/data/mappers/custom_aerodrome_mapper.dart`
- Create: `lib/data/repositories/custom_aerodrome_repository.dart`
- Test: `test/data/repositories/custom_aerodrome_repository_test.dart`

**Interfaces:**
- Consumes: `AppDatabase`, `CustomAerodromeRow`, `generateUlid()`.
- Produces: `CustomAerodromeRow customAerodromeToRow(domain.Aerodrome aerodrome, {required String id})`,
  `domain.Aerodrome customAerodromeFromRow(CustomAerodromeRow row)`,
  `class CustomAerodromeRepository` with `Future<String> upsert(domain.Aerodrome aerodrome, {String? id})`,
  `Future<domain.Aerodrome?> find(String id)`, `Future<void> delete(String id)`.

- [ ] **Step 1: Write the failing test**

Create `test/data/repositories/custom_aerodrome_repository_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:easa_digital_log/data/database.dart';
import 'package:easa_digital_log/data/repositories/custom_aerodrome_repository.dart';
import 'package:easa_digital_log/domain/model/aerodrome.dart';
import 'package:easa_digital_log/domain/model/geo_coordinate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppDatabase db;
  late CustomAerodromeRepository repository;

  setUp(() {
    db = AppDatabase(NativeDatabase.memory());
    repository = CustomAerodromeRepository(db);
  });

  tearDown(() => db.close());

  final strip = Aerodrome(
    name: "Wicker's Field",
    position: GeoCoordinate(latitude: 51.2, longitude: -0.9),
    elevationFt: 210,
  );

  test('round-trips through upsert and find', () async {
    final id = await repository.upsert(strip);
    expect(await repository.find(id), strip);
  });

  test('find returns null for an unknown id', () async {
    expect(await repository.find('nonexistent'), isNull);
  });

  test('delete removes the row', () async {
    final id = await repository.upsert(strip);
    await repository.delete(id);
    expect(await repository.find(id), isNull);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/repositories/custom_aerodrome_repository_test.dart`
Expected: FAIL — files don't exist yet.

- [ ] **Step 3: Implement the mapper**

Create `lib/data/mappers/custom_aerodrome_mapper.dart`:

```dart
import '../../domain/model/aerodrome.dart' as domain;
import '../../domain/model/geo_coordinate.dart';
import '../tables/custom_aerodrome_table.dart';

CustomAerodromeRow customAerodromeToRow(
  domain.Aerodrome aerodrome, {
  required String id,
}) {
  return CustomAerodromeRow(
    id: id,
    icaoCode: aerodrome.icaoCode,
    iataCode: aerodrome.iataCode,
    name: aerodrome.name,
    latitude: aerodrome.position.latitude,
    longitude: aerodrome.position.longitude,
    elevationFt: aerodrome.elevationFt,
    isoCountry: aerodrome.isoCountry,
  );
}

domain.Aerodrome customAerodromeFromRow(CustomAerodromeRow row) {
  return domain.Aerodrome(
    icaoCode: row.icaoCode,
    iataCode: row.iataCode,
    name: row.name,
    position: GeoCoordinate(latitude: row.latitude, longitude: row.longitude),
    elevationFt: row.elevationFt,
    isoCountry: row.isoCountry,
  );
}
```

- [ ] **Step 4: Implement the repository**

Create `lib/data/repositories/custom_aerodrome_repository.dart`:

```dart
import '../../domain/model/aerodrome.dart' as domain;
import '../database.dart';
import '../mappers/custom_aerodrome_mapper.dart';
import '../ulid.dart';

/// Write access to pilot-defined aerodromes. Plain reference data, no
/// lifecycle — same shape as [AircraftRepository].
class CustomAerodromeRepository {
  CustomAerodromeRepository(this._db);

  final AppDatabase _db;

  Future<String> upsert(domain.Aerodrome aerodrome, {String? id}) async {
    final resolvedId = id ?? generateUlid();
    await _db
        .into(_db.customAerodromesTable)
        .insertOnConflictUpdate(customAerodromeToRow(aerodrome, id: resolvedId));
    return resolvedId;
  }

  Future<domain.Aerodrome?> find(String id) async {
    final row = await (_db.select(_db.customAerodromesTable)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    return row == null ? null : customAerodromeFromRow(row);
  }

  Future<void> delete(String id) =>
      (_db.delete(_db.customAerodromesTable)..where((t) => t.id.equals(id))).go();
}
```

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/data/repositories/custom_aerodrome_repository_test.dart`
Expected: PASS

- [ ] **Step 6: Full local verification and commit**

```powershell
dart format --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test
```

```bash
git add lib/data/mappers/custom_aerodrome_mapper.dart lib/data/repositories/custom_aerodrome_repository.dart test/data/repositories/custom_aerodrome_repository_test.dart
git commit -m "feat: custom aerodrome persistence (#31)"
```

---

## Task 6: Flight mapper

Converts a domain `Flight` (plus the ids the caller supplies) into row shapes. Deliberately
one-directional (`Flight` → rows only) — reconstructing a `Flight` back out of stored rows needs
`Flight.aircraftRegistration`, which requires resolving the row's `aircraftId` back to a
registration via a join against `aircraft`. That's a read/query concern, explicitly deferred to
#35; this spec's repository never needs to hand a `Flight` back to a caller (see Task 7/8 — every
method either writes or returns an id).

**Files:**
- Create: `lib/data/mappers/flight_mapper.dart`
- Test: `test/data/mappers/flight_mapper_test.dart`

**Interfaces:**
- Consumes: `FlightRow`, `FlightRouteLegRow`, `FlightApproachRow` (Task 3);
  `domain.Flight`, `domain.PilotCapacity`, `domain.CalendarDate` (Task 1).
- Produces: `FlightRow flightToRow(domain.Flight flight, {required String id, required String aircraftId, int? committedAt, int? tombstonedAt})`,
  `List<FlightRouteLegRow> flightRouteLegRows(String flightId, domain.Flight flight)`,
  `List<FlightApproachRow> flightApproachRows(String flightId, domain.Flight flight)`. Tasks 7
  and 8 call all three.

- [ ] **Step 1: Write the failing test**

Create `test/data/mappers/flight_mapper_test.dart`. This uses one flight fixture built directly
in Dart (not YAML) since the mapper is a pure function of a `Flight`, not a fixture-format
concern:

```dart
import 'package:easa_digital_log/data/mappers/flight_mapper.dart';
import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:flutter_test/flutter_test.dart';

Flight _sampleFlight() {
  return Flight(
    aircraftRegistration: 'G-ABCD',
    route: ['EGKA', 'EGKB'],
    prePlannedNavigation: true,
    offBlocks: UtcInstant.utc(2026, 6, 1, 10, 0),
    onBlocks: UtcInstant.utc(2026, 6, 1, 11, 30),
    takeoff: UtcInstant.utc(2026, 6, 1, 10, 5),
    landing: UtcInstant.utc(2026, 6, 1, 11, 25),
    capacity: const PilotCapacity(
      commandAuthority: true,
      soleManipulator: true,
      soleOccupant: true,
      multiPilotOperation: false,
      additionalCrewRequiredByRule: false,
      actingAsInstructor: false,
      actingAsExaminer: false,
      picusClaimed: false,
      picInterventionNotRequired: false,
    ),
    carryingPassengers: false,
    takeoffs: const CircuitCounts(dayFullStop: 1),
    landings: const CircuitCounts(dayFullStop: 1),
    ifrFlightPlanFiled: false,
    actualInstrumentTime: FlightDuration.zero,
    simulatedInstrumentTime: FlightDuration.zero,
    approaches: const [
      Approach(type: ApproachType.ils, aerodromeIcao: 'EGKB', runway: '20', count: 2),
    ],
    holdingProceduresCount: 0,
    trackingPerformed: false,
    remarks: '',
  );
}

void main() {
  group('flightToRow', () {
    test('flattens capacity, times and counts onto the row', () {
      final row = flightToRow(_sampleFlight(), id: 'f1', aircraftId: 'a1');

      expect(row.id, 'f1');
      expect(row.aircraftId, 'a1');
      expect(row.offBlocks, UtcInstant.utc(2026, 6, 1, 10, 0).millisecondsSinceEpoch);
      expect(row.takeoffsDayFullStop, 1);
      expect(row.capacityCommandAuthority, isTrue);
      expect(row.capacityInstructorCapacity, isNull);
      expect(row.committedAt, isNull);
      expect(row.tombstonedAt, isNull);
    });

    test('carries committedAt/tombstonedAt through when supplied', () {
      final row = flightToRow(
        _sampleFlight(),
        id: 'f1',
        aircraftId: 'a1',
        committedAt: 1000,
        tombstonedAt: 2000,
      );

      expect(row.committedAt, 1000);
      expect(row.tombstonedAt, 2000);
    });
  });

  group('flightRouteLegRows', () {
    test('one row per route entry, in order', () {
      final rows = flightRouteLegRows('f1', _sampleFlight());

      expect(rows, hasLength(2));
      expect(rows[0].sequence, 0);
      expect(rows[0].identifier, 'EGKA');
      expect(rows[1].sequence, 1);
      expect(rows[1].identifier, 'EGKB');
      expect(rows.every((r) => r.flightId == 'f1'), isTrue);
    });
  });

  group('flightApproachRows', () {
    test('one row per approach', () {
      final rows = flightApproachRows('f1', _sampleFlight());

      expect(rows, hasLength(1));
      expect(rows.single.type, 'ils');
      expect(rows.single.count, 2);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/mappers/flight_mapper_test.dart`
Expected: FAIL — `flight_mapper.dart` doesn't exist yet.

- [ ] **Step 3: Implement the mapper**

Create `lib/data/mappers/flight_mapper.dart`:

```dart
import '../../domain/model/flight.dart' as domain;
import '../../domain/model/utc_instant.dart';
import '../tables/flight_tables.dart';
import '../ulid.dart';

int _epoch(UtcInstant instant) => instant.millisecondsSinceEpoch;

FlightRow flightToRow(
  domain.Flight flight, {
  required String id,
  required String aircraftId,
  int? committedAt,
  int? tombstonedAt,
}) {
  final capacity = flight.capacity;
  final instructor = capacity.instructor;
  final countersignature = capacity.countersignature;

  return FlightRow(
    id: id,
    aircraftId: aircraftId,
    prePlannedNavigation: flight.prePlannedNavigation,
    offBlocks: _epoch(flight.offBlocks),
    onBlocks: _epoch(flight.onBlocks),
    takeoff: flight.takeoff == null ? null : _epoch(flight.takeoff!),
    landing: flight.landing == null ? null : _epoch(flight.landing!),
    otherPilotName: flight.otherPilotName,
    otherPilotCredentialNumber: flight.otherPilotCredentialNumber,
    carryingPassengers: flight.carryingPassengers,
    takeoffsDayFullStop: flight.takeoffs.dayFullStop,
    takeoffsDayTouchAndGo: flight.takeoffs.dayTouchAndGo,
    takeoffsNightFullStop: flight.takeoffs.nightFullStop,
    takeoffsNightTouchAndGo: flight.takeoffs.nightTouchAndGo,
    landingsDayFullStop: flight.landings.dayFullStop,
    landingsDayTouchAndGo: flight.landings.dayTouchAndGo,
    landingsNightFullStop: flight.landings.nightFullStop,
    landingsNightTouchAndGo: flight.landings.nightTouchAndGo,
    ifrFlightPlanFiled: flight.ifrFlightPlanFiled,
    actualInstrumentMinutes: flight.actualInstrumentTime.inMinutes,
    simulatedInstrumentMinutes: flight.simulatedInstrumentTime.inMinutes,
    holdingProceduresCount: flight.holdingProceduresCount,
    trackingPerformed: flight.trackingPerformed,
    seriesGroupId: flight.seriesGroupId,
    airworthinessBasis: flight.airworthinessBasis?.name,
    remarks: flight.remarks,
    capacityCommandAuthority: capacity.commandAuthority,
    capacitySoleManipulator: capacity.soleManipulator,
    capacitySoleOccupant: capacity.soleOccupant,
    capacityMultiPilotOperation: capacity.multiPilotOperation,
    capacityAdditionalCrewRequiredByRule: capacity.additionalCrewRequiredByRule,
    capacityActingAsInstructor: capacity.actingAsInstructor,
    capacityActingAsExaminer: capacity.actingAsExaminer,
    capacityPicusClaimed: capacity.picusClaimed,
    capacityPicInterventionNotRequired: capacity.picInterventionNotRequired,
    capacityManipulationTimeMinutes: capacity.manipulationTime?.inMinutes,
    capacitySoloEndorsementHeld: capacity.soloEndorsementHeld,
    capacityEndorsingInstructorName: capacity.endorsingInstructorName,
    capacityInstructorCapacity: instructor?.capacity.name,
    capacityInstructorInfluencedFlight: instructor?.influencedFlight,
    capacityInstructorName: instructor?.name,
    capacityInstructorCredentialNumber: instructor?.credentialNumber,
    capacityInstructorCredentialExpiry: instructor?.credentialExpiry?.toString(),
    capacityOtherPilotRole: capacity.otherPilotRole?.name,
    capacityCountersignatureStatus: countersignature?.status.name,
    capacityCountersignatureSignatoryName: countersignature?.signatoryName,
    capacityCountersignatureSignatoryCredentialNumber:
        countersignature?.signatoryCredentialNumber,
    capacityCountersignatureSignatoryCredentialExpiry:
        countersignature?.signatoryCredentialExpiry?.toString(),
    capacityCountersignatureSignedAt: countersignature?.signedAt == null
        ? null
        : _epoch(countersignature!.signedAt!),
    committedAt: committedAt,
    tombstonedAt: tombstonedAt,
  );
}

List<FlightRouteLegRow> flightRouteLegRows(String flightId, domain.Flight flight) {
  return [
    for (var i = 0; i < flight.route.length; i++)
      FlightRouteLegRow(
        id: generateUlid(),
        flightId: flightId,
        sequence: i,
        identifier: flight.route[i],
      ),
  ];
}

List<FlightApproachRow> flightApproachRows(String flightId, domain.Flight flight) {
  return [
    for (final approach in flight.approaches)
      FlightApproachRow(
        id: generateUlid(),
        flightId: flightId,
        type: approach.type.name,
        aerodromeIcao: approach.aerodromeIcao,
        runway: approach.runway,
        count: approach.count,
      ),
  ];
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/mappers/flight_mapper_test.dart`
Expected: PASS

- [ ] **Step 5: Full local verification and commit**

```powershell
dart format --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test
```

```bash
git add lib/data/mappers/flight_mapper.dart test/data/mappers/flight_mapper_test.dart
git commit -m "feat: map Flight onto the flattened flights row shape (#31)"
```

---

## Task 7: `FlightRepository` — draft lifecycle

**Files:**
- Create: `lib/domain/repository/flight_repository.dart`
- Create: `lib/data/repositories/flight_repository_drift.dart`
- Test: `test/data/repositories/flight_repository_draft_test.dart`

**Interfaces:**
- Consumes: everything from Tasks 2, 3, 6, plus `AircraftRepository` (Task 4) in the test only,
  to create the aircraft row a flight's `aircraftId` references.
- Produces: `abstract class FlightRepository` with `createDraft`/`updateDraft`/`deleteDraft`
  (this task) and `commit`/`updateCommitted`/`tombstone`/`restore` (Task 8, same file/class —
  Task 8 extends this same interface and implementation). `class DriftFlightRepository
  implements FlightRepository`.

- [ ] **Step 1: Define the domain interface**

Create `lib/domain/repository/flight_repository.dart`:

```dart
import '../model/flight.dart';

/// Write access to flights, enforcing the draft/committed/tombstoned state
/// machine (ADR-0003, CLAUDE.md rule 4). The only interface allowed to
/// write the `flights` table — see the "Repository" section of
/// `docs/superpowers/specs/2026-08-09-m2-flight-persistence-design.md`.
///
/// Read/query methods (by date range, by aircraft, jurisdiction-projected
/// results) are #35's job, once this exists to build on.
abstract class FlightRepository {
  /// Creates a new draft flight against [aircraftId] (an id returned by
  /// `AircraftRepository.upsert`, not [Flight.aircraftRegistration]).
  /// Returns the new flight's generated id.
  Future<String> createDraft(Flight flight, {required String aircraftId});

  /// Overwrites a draft flight in place. Throws [StateError] if [flightId]
  /// names a committed flight.
  Future<void> updateDraft(String flightId, Flight flight);

  /// Deletes a draft flight outright, along with its route/approach rows.
  /// Throws [StateError] if [flightId] names a committed flight — a
  /// committed flight is tombstoned, never deleted.
  Future<void> deleteDraft(String flightId);

  /// Commits a draft, setting `committedAt` to now. Throws [StateError] if
  /// [flightId] is already committed.
  Future<void> commit(String flightId);

  /// Edits a committed flight: records one `edit` revision capturing the
  /// prior values of whatever changed, then writes [flight]'s new values.
  /// Throws [StateError] if [flightId] is a draft or is tombstoned.
  Future<void> updateCommitted(String flightId, Flight flight, {String? reason});

  /// Soft-deletes a committed flight, recording a `tombstone` revision.
  /// Throws [StateError] if [flightId] is a draft or already tombstoned.
  Future<void> tombstone(String flightId, {String? reason});

  /// Reverses [tombstone], recording a `restore` revision. Throws
  /// [StateError] if [flightId] is not currently tombstoned.
  Future<void> restore(String flightId, {String? reason});
}
```

- [ ] **Step 2: Write the failing test for the draft lifecycle**

Create `test/data/repositories/flight_repository_draft_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:easa_digital_log/data/database.dart';
import 'package:easa_digital_log/data/repositories/aircraft_repository.dart';
import 'package:easa_digital_log/data/repositories/flight_repository_drift.dart';
import 'package:easa_digital_log/domain/model/aircraft.dart';
import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:flutter_test/flutter_test.dart';

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

Flight _draft({List<String> route = const ['EGKA', 'EGKB']}) {
  return Flight(
    aircraftRegistration: 'G-ABCD',
    route: route,
    prePlannedNavigation: false,
    offBlocks: UtcInstant.utc(2026, 6, 1, 10),
    onBlocks: UtcInstant.utc(2026, 6, 1, 11),
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
}

void main() {
  late AppDatabase db;
  late DriftFlightRepository flights;
  late String aircraftId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    flights = DriftFlightRepository(db);
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

  test('createDraft writes the flight and its route legs, uncommitted', () async {
    final id = await flights.createDraft(_draft(), aircraftId: aircraftId);

    final row = await (db.select(db.flightsTable)..where((t) => t.id.equals(id)))
        .getSingle();
    expect(row.committedAt, isNull);
    expect(row.tombstonedAt, isNull);

    final legs = await (db.select(db.flightRouteLegsTable)
          ..where((t) => t.flightId.equals(id)))
        .get();
    expect(legs.map((l) => l.identifier), ['EGKA', 'EGKB']);
  });

  test('updateDraft overwrites the row and replaces route legs', () async {
    final id = await flights.createDraft(_draft(), aircraftId: aircraftId);

    await flights.updateDraft(id, _draft(route: ['EGKB']));

    final legs = await (db.select(db.flightRouteLegsTable)
          ..where((t) => t.flightId.equals(id)))
        .get();
    expect(legs.map((l) => l.identifier), ['EGKB']);
  });

  test('updateDraft throws on a committed flight', () async {
    final id = await flights.createDraft(_draft(), aircraftId: aircraftId);
    await flights.commit(id);

    expect(() => flights.updateDraft(id, _draft()), throwsStateError);
  });

  test('deleteDraft removes the row and its children', () async {
    final id = await flights.createDraft(_draft(), aircraftId: aircraftId);

    await flights.deleteDraft(id);

    expect(
      await (db.select(db.flightsTable)..where((t) => t.id.equals(id))).getSingleOrNull(),
      isNull,
    );
    expect(
      await (db.select(db.flightRouteLegsTable)..where((t) => t.flightId.equals(id))).get(),
      isEmpty,
    );
  });

  test('deleteDraft throws on a committed flight', () async {
    final id = await flights.createDraft(_draft(), aircraftId: aircraftId);
    await flights.commit(id);

    expect(() => flights.deleteDraft(id), throwsStateError);
  });

  test('draft create/edit/delete writes no revision', () async {
    final id = await flights.createDraft(_draft(), aircraftId: aircraftId);
    await flights.updateDraft(id, _draft(route: ['EGKB']));

    final revisions = await (db.select(db.flightRevisionsTable)
          ..where((t) => t.flightId.equals(id)))
        .get();
    expect(revisions, isEmpty);
  });
}
```

- [ ] **Step 3: Run test to verify it fails**

Run: `flutter test test/data/repositories/flight_repository_draft_test.dart`
Expected: FAIL — `flight_repository_drift.dart` doesn't exist yet.

- [ ] **Step 4: Implement the draft-lifecycle half of `DriftFlightRepository`**

Create `lib/data/repositories/flight_repository_drift.dart`. This task implements
`createDraft`/`updateDraft`/`deleteDraft` plus the shared helpers; Task 8 adds the remaining
four interface methods to the same class in the same file — do not create a second file or a
partial class:

```dart
import '../../domain/model/flight.dart';
import '../../domain/repository/flight_repository.dart';
import '../database.dart';
import '../mappers/flight_mapper.dart';
import '../tables/flight_tables.dart';
import '../ulid.dart';

class DriftFlightRepository implements FlightRepository {
  DriftFlightRepository(this._db);

  final AppDatabase _db;

  @override
  Future<String> createDraft(Flight flight, {required String aircraftId}) {
    final id = generateUlid();
    return _db.transaction(() async {
      await _db.into(_db.flightsTable).insert(
        flightToRow(flight, id: id, aircraftId: aircraftId),
      );
      await _writeChildren(id, flight);
      return id;
    });
  }

  @override
  Future<void> updateDraft(String flightId, Flight flight) {
    return _db.transaction(() async {
      final current = await _requireRow(flightId);
      if (current.committedAt != null) {
        throw StateError(
          'updateDraft called on committed flight $flightId — use '
          'updateCommitted instead',
        );
      }

      await (_db.update(_db.flightsTable)..where((t) => t.id.equals(flightId))).write(
        flightToRow(flight, id: flightId, aircraftId: current.aircraftId),
      );
      await _replaceChildren(flightId, flight);
    });
  }

  @override
  Future<void> deleteDraft(String flightId) async {
    final current = await _requireRow(flightId);
    if (current.committedAt != null) {
      throw StateError(
        'deleteDraft called on committed flight $flightId — committed '
        'flights are tombstoned, never deleted',
      );
    }
    await (_db.delete(_db.flightsTable)..where((t) => t.id.equals(flightId))).go();
  }

  Future<FlightRow> _requireRow(String flightId) async {
    final row = await (_db.select(_db.flightsTable)..where((t) => t.id.equals(flightId)))
        .getSingleOrNull();
    if (row == null) {
      throw StateError('No flight with id $flightId');
    }
    return row;
  }

  Future<void> _writeChildren(String flightId, Flight flight) async {
    for (final leg in flightRouteLegRows(flightId, flight)) {
      await _db.into(_db.flightRouteLegsTable).insert(leg);
    }
    for (final approach in flightApproachRows(flightId, flight)) {
      await _db.into(_db.flightApproachesTable).insert(approach);
    }
  }

  Future<void> _replaceChildren(String flightId, Flight flight) async {
    await (_db.delete(_db.flightRouteLegsTable)..where((t) => t.flightId.equals(flightId))).go();
    await (_db.delete(_db.flightApproachesTable)..where((t) => t.flightId.equals(flightId))).go();
    await _writeChildren(flightId, flight);
  }
}
```

Note this file is intentionally incomplete after this task — `flutter analyze` will report
`DriftFlightRepository` doesn't implement `commit`/`updateCommitted`/`tombstone`/`restore`. That
is expected; Task 8 adds them to this same class before the branch is done. Do not add
placeholder throwing stubs for them — that would make this task's `flutter analyze
--fatal-infos` step fail for the wrong reason. If you're executing this plan task-by-task,
running `flutter analyze` before Task 8 is skipped for this file; run it as part of Task 8's
verification instead.

- [ ] **Step 5: Run the draft tests**

Run: `flutter test test/data/repositories/flight_repository_draft_test.dart`
Expected: still FAIL, but now on `flutter analyze`/compilation because `DriftFlightRepository`
is abstract (missing overrides), not on missing files. This is the expected intermediate state
described in Step 4 — proceed directly to Task 8, which completes the class. Do not run the
"Full local verification" `flutter analyze --fatal-infos` step for this task in isolation.

- [ ] **Step 6: Commit**

```bash
git add lib/domain/repository/flight_repository.dart lib/data/repositories/flight_repository_drift.dart test/data/repositories/flight_repository_draft_test.dart
git commit -m "feat: FlightRepository draft lifecycle (#32) — commit/tombstone/restore in the next commit"
```

This commit is intentionally not analyze-clean in isolation (see Step 4's note) — the pre-commit
hook (`tool/hooks/pre-commit`, if installed) runs `flutter analyze --fatal-infos` and will block
it. If you have the hook installed, either uninstall it for this one commit
(`git config --unset core.hooksPath`, then restore it after Task 8's commit with
`git config core.hooksPath tool/hooks`) or squash Tasks 7 and 8 into a single commit once Task 8
is done — check with the user which they'd prefer before committing Task 7 alone if the hook is
active.

---

## Task 8: `FlightRepository` — commit, edit, tombstone, restore, and historical reconstruction

**Files:**
- Modify: `lib/data/repositories/flight_repository_drift.dart`
- Test: `test/data/repositories/flight_repository_committed_test.dart`
- Create: `lib/data/flight_history.dart`
- Test: `test/data/flight_history_test.dart`

**Interfaces:**
- Consumes: `DriftFlightRepository` (Task 7, same file, extended here).
- Produces: `commit`/`updateCommitted`/`tombstone`/`restore` on `DriftFlightRepository`;
  `Map<String, Object?> reconstructRowAsOf(FlightRow current, List<FlightRevisionRow> revisions, int asOfEpochMs)`
  in `lib/data/flight_history.dart` — a pure function over rows and revisions, not a repository
  method, since it's a read concern and #35 owns the read repository. It exists now because #34's
  acceptance criteria and the spec's Testing section both require historical reconstruction to
  work, even though nothing calls it from the UI yet.

- [ ] **Step 1: Write the failing test for commit/edit/tombstone/restore**

Create `test/data/repositories/flight_repository_committed_test.dart`. This reuses `_draft()`
and `_capacity` — copy the same two definitions from
`test/data/repositories/flight_repository_draft_test.dart` verbatim into this file (test files
in this codebase don't share fixture helpers across files for domain object construction; see
how `flight_repository_draft_test.dart` itself is self-contained):

```dart
import 'dart:convert';

import 'package:drift/native.dart';
import 'package:easa_digital_log/data/database.dart';
import 'package:easa_digital_log/data/repositories/aircraft_repository.dart';
import 'package:easa_digital_log/data/repositories/flight_repository_drift.dart';
import 'package:easa_digital_log/domain/model/aircraft.dart';
import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:flutter_test/flutter_test.dart';

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

Flight _draft({String remarks = ''}) {
  return Flight(
    aircraftRegistration: 'G-ABCD',
    route: const ['EGKA', 'EGKB'],
    prePlannedNavigation: false,
    offBlocks: UtcInstant.utc(2026, 6, 1, 10),
    onBlocks: UtcInstant.utc(2026, 6, 1, 11),
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
    remarks: remarks,
  );
}

void main() {
  late AppDatabase db;
  late DriftFlightRepository flights;
  late String aircraftId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    flights = DriftFlightRepository(db);
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

  Future<String> _committedFlight() async {
    final id = await flights.createDraft(_draft(), aircraftId: aircraftId);
    await flights.commit(id);
    return id;
  }

  test('commit sets committedAt and nothing else changes', () async {
    final id = await flights.createDraft(_draft(remarks: 'first'), aircraftId: aircraftId);
    await flights.commit(id);

    final row = await (db.select(db.flightsTable)..where((t) => t.id.equals(id))).getSingle();
    expect(row.committedAt, isNotNull);
    expect(row.remarks, 'first');
  });

  test('commit throws if already committed', () async {
    final id = await _committedFlight();
    expect(() => flights.commit(id), throwsStateError);
  });

  test('updateCommitted writes exactly one edit revision with the correct old '
      'values, and the row reflects the new values', () async {
    final id = await flights.createDraft(_draft(remarks: 'first'), aircraftId: aircraftId);
    await flights.commit(id);

    await flights.updateCommitted(id, _draft(remarks: 'corrected'), reason: 'typo');

    final row = await (db.select(db.flightsTable)..where((t) => t.id.equals(id))).getSingle();
    expect(row.remarks, 'corrected');

    final revisions = await (db.select(db.flightRevisionsTable)
          ..where((t) => t.flightId.equals(id)))
        .get();
    expect(revisions, hasLength(1));
    expect(revisions.single.kind, 'edit');
    expect(revisions.single.reason, 'typo');

    final changed = jsonDecode(revisions.single.changedFields) as Map<String, dynamic>;
    expect(changed['remarks'], 'first');
  });

  test('updateCommitted throws on a draft', () async {
    final id = await flights.createDraft(_draft(), aircraftId: aircraftId);
    expect(() => flights.updateCommitted(id, _draft()), throwsStateError);
  });

  test('updateCommitted throws on a tombstoned flight', () async {
    final id = await _committedFlight();
    await flights.tombstone(id);
    expect(() => flights.updateCommitted(id, _draft()), throwsStateError);
  });

  test('tombstone sets tombstonedAt and writes a tombstone revision', () async {
    final id = await _committedFlight();
    await flights.tombstone(id, reason: 'duplicate entry');

    final row = await (db.select(db.flightsTable)..where((t) => t.id.equals(id))).getSingle();
    expect(row.tombstonedAt, isNotNull);

    final revisions = await (db.select(db.flightRevisionsTable)
          ..where((t) => t.flightId.equals(id)))
        .get();
    expect(revisions.single.kind, 'tombstone');
    expect(revisions.single.reason, 'duplicate entry');
  });

  test('tombstone throws on a draft', () async {
    final id = await flights.createDraft(_draft(), aircraftId: aircraftId);
    expect(() => flights.tombstone(id), throwsStateError);
  });

  test('a tombstoned flight is excluded from a basic active-flights query', () async {
    final id = await _committedFlight();
    await flights.tombstone(id);

    final active = await (db.select(db.flightsTable)
          ..where((t) => t.tombstonedAt.isNull()))
        .get();
    expect(active.map((r) => r.id), isNot(contains(id)));
  });

  test('restore clears tombstonedAt and writes a restore revision', () async {
    final id = await _committedFlight();
    await flights.tombstone(id);

    await flights.restore(id, reason: 'reinstated');

    final row = await (db.select(db.flightsTable)..where((t) => t.id.equals(id))).getSingle();
    expect(row.tombstonedAt, isNull);

    final revisions = await (db.select(db.flightRevisionsTable)
          ..where((t) => t.flightId.equals(id)))
        .get();
    expect(revisions.last.kind, 'restore');
  });

  test('restore throws if not tombstoned', () async {
    final id = await _committedFlight();
    expect(() => flights.restore(id), throwsStateError);
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/repositories/flight_repository_committed_test.dart`
Expected: FAIL — `DriftFlightRepository` doesn't implement these four methods yet.

- [ ] **Step 3: Add the remaining four methods to `DriftFlightRepository`**

In `lib/data/repositories/flight_repository_drift.dart`, add `import 'dart:convert';` at the
top, and add these methods to the `DriftFlightRepository` class (alongside `createDraft` etc.
from Task 7):

```dart
  @override
  Future<void> commit(String flightId) async {
    final current = await _requireRow(flightId);
    if (current.committedAt != null) {
      throw StateError('Flight $flightId is already committed');
    }
    await (_db.update(_db.flightsTable)..where((t) => t.id.equals(flightId))).write(
      FlightsTableCompanion(
        committedAt: Value(DateTime.now().toUtc().millisecondsSinceEpoch),
      ),
    );
  }

  @override
  Future<void> updateCommitted(String flightId, Flight flight, {String? reason}) {
    return _db.transaction(() async {
      final current = await _requireRow(flightId);
      if (current.committedAt == null) {
        throw StateError(
          'updateCommitted called on draft flight $flightId — use '
          'updateDraft instead',
        );
      }
      if (current.tombstonedAt != null) {
        throw StateError(
          'updateCommitted called on tombstoned flight $flightId — restore '
          'it first',
        );
      }

      final newRow = flightToRow(
        flight,
        id: flightId,
        aircraftId: current.aircraftId,
        committedAt: current.committedAt,
        tombstonedAt: current.tombstonedAt,
      );
      final changed = _diffRows(current, newRow);

      if (changed.isNotEmpty) {
        await _db.into(_db.flightRevisionsTable).insert(
          FlightRevisionRow(
            id: generateUlid(),
            flightId: flightId,
            recordedAt: DateTime.now().toUtc().millisecondsSinceEpoch,
            kind: 'edit',
            reason: reason,
            changedFields: jsonEncode(changed),
          ),
        );
      }

      await (_db.update(_db.flightsTable)..where((t) => t.id.equals(flightId))).write(newRow);
      await _replaceChildren(flightId, flight);
    });
  }

  @override
  Future<void> tombstone(String flightId, {String? reason}) {
    return _db.transaction(() async {
      final current = await _requireRow(flightId);
      if (current.committedAt == null) {
        throw StateError('Cannot tombstone draft flight $flightId — delete it instead');
      }
      if (current.tombstonedAt != null) {
        throw StateError('Flight $flightId is already tombstoned');
      }

      await _db.into(_db.flightRevisionsTable).insert(
        FlightRevisionRow(
          id: generateUlid(),
          flightId: flightId,
          recordedAt: DateTime.now().toUtc().millisecondsSinceEpoch,
          kind: 'tombstone',
          reason: reason,
          changedFields: jsonEncode(<String, Object?>{'tombstonedAt': null}),
        ),
      );
      await (_db.update(_db.flightsTable)..where((t) => t.id.equals(flightId))).write(
        FlightsTableCompanion(
          tombstonedAt: Value(DateTime.now().toUtc().millisecondsSinceEpoch),
        ),
      );
    });
  }

  @override
  Future<void> restore(String flightId, {String? reason}) {
    return _db.transaction(() async {
      final current = await _requireRow(flightId);
      if (current.tombstonedAt == null) {
        throw StateError('Flight $flightId is not tombstoned');
      }

      await _db.into(_db.flightRevisionsTable).insert(
        FlightRevisionRow(
          id: generateUlid(),
          flightId: flightId,
          recordedAt: DateTime.now().toUtc().millisecondsSinceEpoch,
          kind: 'restore',
          reason: reason,
          changedFields: jsonEncode(<String, Object?>{'tombstonedAt': current.tombstonedAt}),
        ),
      );
      await (_db.update(_db.flightsTable)..where((t) => t.id.equals(flightId))).write(
        const FlightsTableCompanion(tombstonedAt: Value(null)),
      );
    });
  }
```

Add this top-level function at the bottom of the same file — the row-level diff both
`updateCommitted` and `reconstructRowAsOf` (Step 6) key off:

```dart
/// Every column in [newRow] that differs from [oldRow], keyed by the Dart
/// field name (matching [FlightRow.toJson]'s default key casing), mapped to
/// [oldRow]'s value. `id` is never included — it cannot change.
Map<String, Object?> _diffRows(FlightRow oldRow, FlightRow newRow) {
  final oldJson = oldRow.toJson();
  final newJson = newRow.toJson();
  final changed = <String, Object?>{};
  for (final key in oldJson.keys) {
    if (key == 'id') {
      continue;
    }
    if (oldJson[key] != newJson[key]) {
      changed[key] = oldJson[key];
    }
  }
  return changed;
}
```

Also add `import 'package:drift/drift.dart';` to the top of the file — `Value` and
`FlightsTableCompanion` need it.

- [ ] **Step 4: Run the committed-lifecycle tests**

Run: `flutter test test/data/repositories/flight_repository_committed_test.dart`
Expected: PASS. Then also re-run Task 7's draft test file, which was blocked on this class
compiling:

Run: `flutter test test/data/repositories/flight_repository_draft_test.dart`
Expected: PASS.

- [ ] **Step 5: Write the failing test for historical reconstruction**

Create `test/data/flight_history_test.dart`:

```dart
import 'dart:convert';

import 'package:easa_digital_log/data/flight_history.dart';
import 'package:easa_digital_log/data/tables/flight_tables.dart';
import 'package:flutter_test/flutter_test.dart';

FlightRow _row({String remarks = 'current', int? tombstonedAt}) {
  return FlightRow(
    id: 'f1',
    aircraftId: 'a1',
    prePlannedNavigation: false,
    offBlocks: 1000,
    onBlocks: 2000,
    takeoff: null,
    landing: null,
    otherPilotName: null,
    otherPilotCredentialNumber: null,
    carryingPassengers: false,
    takeoffsDayFullStop: 1,
    takeoffsDayTouchAndGo: 0,
    takeoffsNightFullStop: 0,
    takeoffsNightTouchAndGo: 0,
    landingsDayFullStop: 1,
    landingsDayTouchAndGo: 0,
    landingsNightFullStop: 0,
    landingsNightTouchAndGo: 0,
    ifrFlightPlanFiled: false,
    actualInstrumentMinutes: 0,
    simulatedInstrumentMinutes: 0,
    holdingProceduresCount: 0,
    trackingPerformed: false,
    seriesGroupId: null,
    airworthinessBasis: null,
    remarks: remarks,
    capacityCommandAuthority: true,
    capacitySoleManipulator: true,
    capacitySoleOccupant: true,
    capacityMultiPilotOperation: false,
    capacityAdditionalCrewRequiredByRule: false,
    capacityActingAsInstructor: false,
    capacityActingAsExaminer: false,
    capacityPicusClaimed: false,
    capacityPicInterventionNotRequired: false,
    capacityManipulationTimeMinutes: null,
    capacitySoloEndorsementHeld: null,
    capacityEndorsingInstructorName: null,
    capacityInstructorCapacity: null,
    capacityInstructorInfluencedFlight: null,
    capacityInstructorName: null,
    capacityInstructorCredentialNumber: null,
    capacityInstructorCredentialExpiry: null,
    capacityOtherPilotRole: null,
    capacityCountersignatureStatus: null,
    capacityCountersignatureSignatoryName: null,
    capacityCountersignatureSignatoryCredentialNumber: null,
    capacityCountersignatureSignatoryCredentialExpiry: null,
    capacityCountersignatureSignedAt: null,
    committedAt: 500,
    tombstonedAt: tombstonedAt,
  );
}

FlightRevisionRow _revision(int recordedAt, String kind, Map<String, Object?> changed) {
  return FlightRevisionRow(
    id: 'r-$recordedAt',
    flightId: 'f1',
    recordedAt: recordedAt,
    kind: kind,
    reason: null,
    changedFields: jsonEncode(changed),
  );
}

void main() {
  test('with no revisions newer than asOf, returns the current row unchanged', () {
    final result = reconstructRowAsOf(_row(remarks: 'current'), [], 5000);
    expect(result['remarks'], 'current');
  });

  test('applies one revision newer than asOf, restoring its old value', () {
    final revisions = [_revision(3000, 'edit', {'remarks': 'original'})];
    final result = reconstructRowAsOf(_row(remarks: 'current'), revisions, 2000);
    expect(result['remarks'], 'original');
  });

  test('chains two revisions in reverse order, each undoing on top of the last', () {
    // Row started as 'first', edited to 'second' at t=3000, edited to
    // 'current' at t=4000. Reconstructing at t=2500 must undo both edits.
    final revisions = [
      _revision(3000, 'edit', {'remarks': 'first'}),
      _revision(4000, 'edit', {'remarks': 'second'}),
    ];
    final result = reconstructRowAsOf(_row(remarks: 'current'), revisions, 2500);
    expect(result['remarks'], 'first');
  });

  test('ignores revisions at or before asOf', () {
    final revisions = [_revision(1000, 'edit', {'remarks': 'too old to matter'})];
    final result = reconstructRowAsOf(_row(remarks: 'current'), revisions, 2000);
    expect(result['remarks'], 'current');
  });
}
```

- [ ] **Step 6: Run test to verify it fails**

Run: `flutter test test/data/flight_history_test.dart`
Expected: FAIL — `lib/data/flight_history.dart` doesn't exist yet.

- [ ] **Step 7: Implement `reconstructRowAsOf`**

Create `lib/data/flight_history.dart`:

```dart
import 'dart:convert';

import 'tables/flight_tables.dart';

/// Reconstructs a flight row's state as of [asOfEpochMs]: starts from
/// [current], then walks [revisions] newer than [asOfEpochMs] in reverse
/// chronological order, applying each revision's old values back over the
/// running result — an "undo" replay, not a forward replay from creation.
/// See the M2 design spec's `flight_revisions` section.
///
/// Returns a plain column-name-keyed map, not a [FlightRow] or a domain
/// `Flight` — turning this into either needs a read/query layer (#35),
/// which does not exist yet. This function only proves the replay algorithm
/// is correct; wiring it into a caller is future work.
Map<String, Object?> reconstructRowAsOf(
  FlightRow current,
  List<FlightRevisionRow> revisions,
  int asOfEpochMs,
) {
  final result = current.toJson();

  final applicable = revisions.where((r) => r.recordedAt > asOfEpochMs).toList()
    ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));

  for (final revision in applicable) {
    final oldValues = jsonDecode(revision.changedFields) as Map<String, dynamic>;
    result.addAll(oldValues);
  }

  return result;
}
```

- [ ] **Step 8: Run test to verify it passes**

Run: `flutter test test/data/flight_history_test.dart`
Expected: PASS

- [ ] **Step 9: Full local verification**

```powershell
dart format --set-exit-if-changed .
flutter analyze --fatal-infos
dart run tool/check_layering.dart
dart run tool/check_domain_types.dart
flutter test
```
Expected: all clean, all green — this is the first point since Task 7 where
`DriftFlightRepository` is a complete, non-abstract class, so this is the first `flutter
analyze` that can pass for that file.

- [ ] **Step 10: Commit**

```bash
git add lib/data/repositories/flight_repository_drift.dart lib/data/flight_history.dart test/data/repositories/flight_repository_committed_test.dart test/data/flight_history_test.dart
git commit -m "feat: commit/edit/tombstone/restore lifecycle and historical reconstruction (#32, #33, #34)"
```

If Task 7 was committed separately and the pre-commit hook blocked it per that task's note,
this is the commit that makes the whole class analyze-clean — restore the hook
(`git config core.hooksPath tool/hooks`) before this commit if you'd uninstalled it.

---

## Self-Review

**Spec coverage:** Schema (all 8 tables) — Task 3. `flights`/`flight_route_legs`/
`flight_approaches` mapping — Task 6. `aircraft` + the jurisdiction absent-vs-empty split —
Task 4. `custom_aerodromes` — Task 5. Draft lifecycle — Task 7. Commit/edit/tombstone/restore
plus revision recording — Task 8. Historical reconstruction — Task 8, Step 5-8. Derived-quantity
schema sweep — Task 3, Step 7. ULID ids throughout — Task 2, used by every later task. The one
spec item with no task: read/query methods, jurisdiction-projected reads, streaming updates —
correctly, since the spec lists these under its own Non-goals as #35's job.

**Placeholder scan:** No task leaves a stub method, a "TODO," or an untested code path. Task 7
intentionally ends with an incomplete class (documented explicitly, with a named reason and a
named follow-up task) rather than a placeholder implementation — flagged with an explicit
pre-commit-hook interaction note rather than silently glossed over.

**Type consistency:** `String` ids used consistently from Task 2 (`generateUlid()`) through every
repository signature. `FlightRepository`'s abstract methods (Task 7) match
`DriftFlightRepository`'s overrides (Tasks 7-8) exactly. `flightToRow`/`flightRouteLegRows`/
`flightApproachRows` (Task 6) are called with matching signatures in Task 7's `_writeChildren`/
`_replaceChildren`. `AircraftRow`/`CustomAerodromeRow`/`FlightRow`/etc. field names match their
Drift table column getters throughout, since `@DataClassName` doesn't rename fields, only the
class.

---

## Execution

**Plan complete and saved to `docs/superpowers/plans/2026-08-09-m2-flight-persistence.md`. Two
execution options:**

**1. Subagent-Driven (recommended)** — fresh subagent per task, review between tasks, fast
iteration.

**2. Inline Execution** — execute tasks in this session using executing-plans, batch execution
with checkpoints.

**Which approach?**
