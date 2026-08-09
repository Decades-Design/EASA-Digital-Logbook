# Flight Read Repository Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the M2 persistence layer a read side — filtered, jurisdiction-projected, reactive
queries over flights, plus draft lookups — so the UI never touches a raw Drift row.

**Architecture:** A new `FlightReadRepository` interface in `lib/domain/`, implemented by
`DriftFlightReadRepository` in `lib/data/`, built on top of a new `flightFromRow` mapper (the
mirror of M2's `flightToRow`) and Drift's built-in `.watch()` reactive queries.

**Tech Stack:** `drift` (already added in M2), `freezed` for the new result/query value types.

## Global Constraints

- `FlightRecord`, `ProjectedFlight`, `FlightQuery`, `CapacityFilter`, and the
  `FlightReadRepository` interface all live in one file,
  `lib/domain/repository/flight_read_repository.dart` — plain Dart/freezed, no Drift, no
  Flutter imports (must pass `dart run tool/check_layering.dart`).
- `flightFromRow` is the mirror of M2's `flightToRow`; it lives in the same file,
  `lib/data/mappers/flight_mapper.dart`, using the same conventions already established there
  (enums via `.name`/`Enum.values.byName`, `CalendarDate.parse` for the two
  `*CredentialExpiry` columns, epoch-ms for `UtcInstant`).
- `DriftFlightReadRepository` (`lib/data/repositories/flight_read_repository_drift.dart`) is
  built incrementally across Tasks 3-5. It does **not** analyze clean until Task 5 completes
  it — same documented pattern M2 used for `DriftFlightRepository`. Do not add placeholder stub
  method bodies to make an earlier task analyze-clean; that hides the real completion point.
- `find`/`findDraft` are one-shot `Future`s. `watchFlights`/`watchDrafts` are `Stream`s via
  Drift's `.watch()`. No method exists in both a `Future` and `Stream` form.
- `watchFlights` and `find` take a `Projection` supplied by the caller — the repository never
  resolves a jurisdiction id itself; it only calls `projection.project(flight, aircraft)`.
- List/watch methods (`watchFlights`) exclude drafts and tombstoned flights by default. `find`
  includes tombstoned flights but not drafts. `watchDrafts`/`findDraft` return only drafts.
- Drift's exact subquery/comparison-operator method names (`existsQuery`, `equalsExp`,
  `isBiggerOrEqualValue`, `isSmallerOrEqualValue`) are written from the installed `drift` 2.34.x
  API. If codegen or `flutter analyze` reports a different exact name, that is expected minor
  API drift — adjust the call site, not the filter design.
- `AppDatabase` enforces `PRAGMA foreign_keys = ON` (set in M2), which makes a flight row with a
  dangling `aircraftId` unreachable through any normal write path. Task 3's test for that
  defensive code path must toggle the pragma off, construct the dangling state directly, then
  toggle it back on — there is no other way to reach it.

---

## Task 1: Result and query types, and the `FlightReadRepository` interface

**Files:**
- Create: `lib/domain/repository/flight_read_repository.dart`
- Test: `test/domain/repository/flight_read_repository_test.dart`

**Interfaces:**
- Consumes: `Flight` (`lib/domain/model/flight.dart`), `Aircraft`
  (`lib/domain/model/aircraft.dart`), `CalendarDate` (`lib/domain/model/calendar_date.dart`),
  `Projection`/`ProjectionResult` (`lib/domain/projection/`).
- Produces: `FlightRecord { id, flight, aircraft }`, `ProjectedFlight { record, projection }`,
  `CapacityFilter { commandAuthority, soleManipulator, soleOccupant, multiPilotOperation,
  actingAsInstructor, actingAsExaminer, picusClaimed }` (all `bool?`), `FlightQuery { from, to,
  aircraftId, aerodromeIdentifier, capacity }`, and `abstract class FlightReadRepository` with
  `watchFlights`/`find`/`watchDrafts`/`findDraft`. Every later task implements or calls these
  exact names.

- [ ] **Step 1: Write the failing test**

Create `test/domain/repository/flight_read_repository_test.dart`:

```dart
import 'package:easa_digital_log/domain/model/calendar_date.dart';
import 'package:easa_digital_log/domain/repository/flight_read_repository.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('FlightQuery', () {
    test('defaults to no filters', () {
      const query = FlightQuery();
      expect(query.from, isNull);
      expect(query.to, isNull);
      expect(query.aircraftId, isNull);
      expect(query.aerodromeIdentifier, isNull);
      expect(query.capacity, isNull);
    });

    test('equal by value', () {
      const a = FlightQuery(aircraftId: 'a1', from: CalendarDate(2026, 1, 1));
      const b = FlightQuery(aircraftId: 'a1', from: CalendarDate(2026, 1, 1));
      expect(a, b);
    });
  });

  group('CapacityFilter', () {
    test('equal by value', () {
      const a = CapacityFilter(commandAuthority: true);
      const b = CapacityFilter(commandAuthority: true);
      expect(a, b);
    });

    test('defaults to no filters', () {
      const filter = CapacityFilter();
      expect(filter.commandAuthority, isNull);
      expect(filter.actingAsInstructor, isNull);
    });
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/domain/repository/flight_read_repository_test.dart`
Expected: FAIL — `package:easa_digital_log/domain/repository/flight_read_repository.dart` does
not exist.

- [ ] **Step 3: Implement the types and interface**

Create `lib/domain/repository/flight_read_repository.dart`:

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

import '../model/aircraft.dart';
import '../model/calendar_date.dart';
import '../model/flight.dart';
import '../projection/projection.dart';
import '../projection/projection_result.dart';

part 'flight_read_repository.freezed.dart';

/// A flight's raw facts, resolved from storage: which aircraft it names,
/// and the id it was stored under. No jurisdiction involved — used for
/// drafts, where nothing has been asserted yet (ADR-0003).
@freezed
abstract class FlightRecord with _$FlightRecord {
  const factory FlightRecord({
    required String id,
    required Flight flight,
    required Aircraft aircraft,
  }) = _FlightRecord;
}

/// A [FlightRecord] plus the derived quantities [Projection.project]
/// computed for it, under whichever jurisdiction the caller's [Projection]
/// represents.
@freezed
abstract class ProjectedFlight with _$ProjectedFlight {
  const factory ProjectedFlight({
    required FlightRecord record,
    required ProjectionResult projection,
  }) = _ProjectedFlight;
}

/// Matches against [PilotCapacity]'s own raw boolean discriminators —
/// deliberately not against a derived label like "PIC", since which flights
/// count as PIC is jurisdiction-dependent (rule 1). Every field unset means
/// "don't filter on this"; set fields are ANDed together.
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

/// Filters for [FlightReadRepository.watchFlights]. Every field unset means
/// "don't filter on this"; set fields are ANDed together. [from]/[to]
/// filter on [Flight.offBlocks]'s UTC calendar date (ADR-0009's "date of
/// departure, in UTC" policy, applied as a range). [aerodromeIdentifier]
/// matches a flight that touched that identifier anywhere — a route leg or
/// an approach.
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

/// Read access to flights, returning projections rather than raw rows — see
/// `docs/superpowers/specs/2026-08-09-flight-read-repository-design.md`.
/// The read-side counterpart to `FlightRepository` (write side, M2).
abstract class FlightReadRepository {
  /// Committed, active (non-tombstoned) flights matching [query], projected
  /// under [projection]. Re-emits whenever a write touches any flight this
  /// query could match.
  Stream<List<ProjectedFlight>> watchFlights({
    required Projection projection,
    FlightQuery query = const FlightQuery(),
  });

  /// A single committed flight by id — active or tombstoned. Null if
  /// [flightId] names a draft or does not exist.
  Future<ProjectedFlight?> find(String flightId, {required Projection projection});

  /// Draft flights, raw facts only — no jurisdiction, nothing to project.
  Stream<List<FlightRecord>> watchDrafts();

  /// A single draft by id. Null if [flightId] names a committed flight or
  /// does not exist.
  Future<FlightRecord?> findDraft(String flightId);
}
```

- [ ] **Step 4: Generate freezed code**

Run: `flutter pub run build_runner build`
Expected: generates `lib/domain/repository/flight_read_repository.freezed.dart` with no errors.

- [ ] **Step 5: Run test to verify it passes**

Run: `flutter test test/domain/repository/flight_read_repository_test.dart`
Expected: PASS

- [ ] **Step 6: Full local verification**

```powershell
dart format --set-exit-if-changed .
flutter analyze --fatal-infos
dart run tool/check_layering.dart
dart run tool/check_domain_types.dart
flutter test
```

- [ ] **Step 7: Commit**

```bash
git add lib/domain/repository/flight_read_repository.dart test/domain/repository/flight_read_repository_test.dart
git commit -m "feat: flight read repository result/query types and interface (#35)"
```

---

## Task 2: `flightFromRow` — the row-to-domain mapper

**Files:**
- Modify: `lib/data/mappers/flight_mapper.dart`
- Test: `test/data/mappers/flight_mapper_test.dart`

**Interfaces:**
- Consumes: `FlightRow`, `FlightRouteLegRow`, `FlightApproachRow` (from `lib/data/database.dart`,
  M2); `Flight`, `PilotCapacity`, `InstructorPresence`, `Countersignature`, `CalendarDate`,
  `FlightDuration`, `UtcInstant` (domain models).
- Produces: `Flight flightFromRow(FlightRow row, List<FlightRouteLegRow> legs,
  List<FlightApproachRow> approaches, {required String aircraftRegistration})`. Tasks 3-5 call
  this inside `DriftFlightReadRepository._recordFromRow`.

- [ ] **Step 1: Write the failing round-trip test**

Add to `test/data/mappers/flight_mapper_test.dart` — new imports and a new group. Add these
imports alongside the existing ones at the top of the file:

```dart
import 'package:easa_digital_log/domain/model/calendar_date.dart';
import 'package:easa_digital_log/domain/model/countersignature.dart';
import 'package:easa_digital_log/domain/model/instructor_presence.dart';
```

Add this group at the end of `main()`, after the existing `flightApproachRows` group:

```dart
  group('flightFromRow round trip', () {
    test(
      'reconstructs every field flightToRow set, including nested capacity '
      'structures',
      () {
        final original = Flight(
          aircraftRegistration: 'G-ABCD',
          route: const ['EGKA', 'EGKB', 'EGHI'],
          prePlannedNavigation: true,
          offBlocks: UtcInstant.utc(2026, 6, 1, 10, 0),
          onBlocks: UtcInstant.utc(2026, 6, 1, 12, 30),
          takeoff: UtcInstant.utc(2026, 6, 1, 10, 5),
          landing: UtcInstant.utc(2026, 6, 1, 12, 25),
          capacity: PilotCapacity(
            commandAuthority: true,
            soleManipulator: false,
            soleOccupant: false,
            multiPilotOperation: false,
            additionalCrewRequiredByRule: false,
            actingAsInstructor: false,
            actingAsExaminer: false,
            picusClaimed: true,
            picInterventionNotRequired: true,
            manipulationTime: FlightDuration.parseHoursMinutes('0:45'),
            soloEndorsementHeld: true,
            endorsingInstructorName: 'A. Trainer',
            instructor: InstructorPresence(
              capacity: InstructorCapacity.flightInstructor,
              influencedFlight: true,
              name: 'B. Coach',
              credentialNumber: 'GBR.FI.1234',
              credentialExpiry: const CalendarDate(2027, 5, 31),
            ),
            otherPilotRole: OtherPilotRole.requiredCrew,
            countersignature: Countersignature(
              status: CountersignatureStatus.signed,
              signatoryName: 'B. Coach',
              signatoryCredentialNumber: 'GBR.FI.1234',
              signatoryCredentialExpiry: const CalendarDate(2027, 5, 31),
              signedAt: UtcInstant.utc(2026, 6, 2),
            ),
          ),
          otherPilotName: 'C. Pilot',
          otherPilotCredentialNumber: 'GBR.PPL.5678',
          carryingPassengers: true,
          takeoffs: const CircuitCounts(
            dayFullStop: 2,
            dayTouchAndGo: 1,
          ),
          landings: const CircuitCounts(
            dayFullStop: 2,
            dayTouchAndGo: 1,
          ),
          ifrFlightPlanFiled: true,
          actualInstrumentTime: FlightDuration.parseHoursMinutes('0:20'),
          simulatedInstrumentTime: FlightDuration.parseHoursMinutes('0:10'),
          approaches: const [
            Approach(
              type: ApproachType.ils,
              aerodromeIcao: 'EGHI',
              runway: '20',
              count: 1,
            ),
          ],
          holdingProceduresCount: 1,
          trackingPerformed: true,
          seriesGroupId: 'series-1',
          airworthinessBasis: AirworthinessBasis.usRegistryStandardOrSpecial,
          remarks: 'Nav ex',
        );

        final row = flightToRow(original, id: 'f1', aircraftId: 'a1');
        final legs = flightRouteLegRows('f1', original);
        final approachRows = flightApproachRows('f1', original);

        final reconstructed = flightFromRow(
          row,
          legs,
          approachRows,
          aircraftRegistration: original.aircraftRegistration,
        );

        expect(reconstructed, original);
      },
    );

    test('reconstructs a minimal flight with every optional field null', () {
      final original = Flight(
        aircraftRegistration: 'G-ABCD',
        route: const [],
        prePlannedNavigation: false,
        offBlocks: UtcInstant.utc(2026, 6, 1, 10),
        onBlocks: UtcInstant.utc(2026, 6, 1, 11),
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
        approaches: const [],
        holdingProceduresCount: 0,
        trackingPerformed: false,
        remarks: '',
      );

      final row = flightToRow(original, id: 'f2', aircraftId: 'a1');
      final reconstructed = flightFromRow(
        row,
        const [],
        const [],
        aircraftRegistration: original.aircraftRegistration,
      );

      expect(reconstructed, original);
    });
  });
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/mappers/flight_mapper_test.dart`
Expected: FAIL — `flightFromRow` is not defined.

- [ ] **Step 3: Implement `flightFromRow`**

In `lib/data/mappers/flight_mapper.dart`, change the imports at the top to:

```dart
import '../../domain/model/calendar_date.dart';
import '../../domain/model/countersignature.dart' as domain;
import '../../domain/model/flight.dart' as domain;
import '../../domain/model/flight_duration.dart';
import '../../domain/model/instructor_presence.dart' as domain;
import '../../domain/model/pilot_capacity.dart' as domain;
import '../../domain/model/utc_instant.dart';
import '../database.dart';
import '../ulid.dart';
```

Add this function at the end of the file:

```dart
domain.Flight flightFromRow(
  FlightRow row,
  List<FlightRouteLegRow> legs,
  List<FlightApproachRow> approaches, {
  required String aircraftRegistration,
}) {
  domain.InstructorPresence? instructor;
  if (row.capacityInstructorCapacity != null) {
    instructor = domain.InstructorPresence(
      capacity: domain.InstructorCapacity.values.byName(
        row.capacityInstructorCapacity!,
      ),
      influencedFlight: row.capacityInstructorInfluencedFlight!,
      name: row.capacityInstructorName,
      credentialNumber: row.capacityInstructorCredentialNumber,
      credentialExpiry: row.capacityInstructorCredentialExpiry == null
          ? null
          : CalendarDate.parse(row.capacityInstructorCredentialExpiry!),
    );
  }

  domain.Countersignature? countersignature;
  if (row.capacityCountersignatureStatus != null) {
    countersignature = domain.Countersignature(
      status: domain.CountersignatureStatus.values.byName(
        row.capacityCountersignatureStatus!,
      ),
      signatoryName: row.capacityCountersignatureSignatoryName,
      signatoryCredentialNumber:
          row.capacityCountersignatureSignatoryCredentialNumber,
      signatoryCredentialExpiry:
          row.capacityCountersignatureSignatoryCredentialExpiry == null
              ? null
              : CalendarDate.parse(
                  row.capacityCountersignatureSignatoryCredentialExpiry!,
                ),
      signedAt: row.capacityCountersignatureSignedAt == null
          ? null
          : _fromEpoch(row.capacityCountersignatureSignedAt!),
    );
  }

  final capacity = domain.PilotCapacity(
    commandAuthority: row.capacityCommandAuthority,
    soleManipulator: row.capacitySoleManipulator,
    soleOccupant: row.capacitySoleOccupant,
    multiPilotOperation: row.capacityMultiPilotOperation,
    additionalCrewRequiredByRule: row.capacityAdditionalCrewRequiredByRule,
    actingAsInstructor: row.capacityActingAsInstructor,
    actingAsExaminer: row.capacityActingAsExaminer,
    picusClaimed: row.capacityPicusClaimed,
    picInterventionNotRequired: row.capacityPicInterventionNotRequired,
    manipulationTime: row.capacityManipulationTimeMinutes == null
        ? null
        : FlightDuration(row.capacityManipulationTimeMinutes!),
    soloEndorsementHeld: row.capacitySoloEndorsementHeld,
    endorsingInstructorName: row.capacityEndorsingInstructorName,
    instructor: instructor,
    otherPilotRole: row.capacityOtherPilotRole == null
        ? null
        : domain.OtherPilotRole.values.byName(row.capacityOtherPilotRole!),
    countersignature: countersignature,
  );

  final sortedLegs = [...legs]
    ..sort((a, b) => a.sequence.compareTo(b.sequence));

  return domain.Flight(
    aircraftRegistration: aircraftRegistration,
    route: [for (final leg in sortedLegs) leg.identifier],
    prePlannedNavigation: row.prePlannedNavigation,
    offBlocks: _fromEpoch(row.offBlocks),
    onBlocks: _fromEpoch(row.onBlocks),
    takeoff: row.takeoff == null ? null : _fromEpoch(row.takeoff!),
    landing: row.landing == null ? null : _fromEpoch(row.landing!),
    capacity: capacity,
    otherPilotName: row.otherPilotName,
    otherPilotCredentialNumber: row.otherPilotCredentialNumber,
    carryingPassengers: row.carryingPassengers,
    takeoffs: domain.CircuitCounts(
      dayFullStop: row.takeoffsDayFullStop,
      dayTouchAndGo: row.takeoffsDayTouchAndGo,
      nightFullStop: row.takeoffsNightFullStop,
      nightTouchAndGo: row.takeoffsNightTouchAndGo,
    ),
    landings: domain.CircuitCounts(
      dayFullStop: row.landingsDayFullStop,
      dayTouchAndGo: row.landingsDayTouchAndGo,
      nightFullStop: row.landingsNightFullStop,
      nightTouchAndGo: row.landingsNightTouchAndGo,
    ),
    ifrFlightPlanFiled: row.ifrFlightPlanFiled,
    actualInstrumentTime: FlightDuration(row.actualInstrumentMinutes),
    simulatedInstrumentTime: FlightDuration(row.simulatedInstrumentMinutes),
    approaches: [
      for (final approach in approaches)
        domain.Approach(
          type: domain.ApproachType.values.byName(approach.type),
          aerodromeIcao: approach.aerodromeIcao,
          runway: approach.runway,
          count: approach.count,
        ),
    ],
    holdingProceduresCount: row.holdingProceduresCount,
    trackingPerformed: row.trackingPerformed,
    seriesGroupId: row.seriesGroupId,
    airworthinessBasis: row.airworthinessBasis == null
        ? null
        : domain.AirworthinessBasis.values.byName(row.airworthinessBasis!),
    remarks: row.remarks,
  );
}

UtcInstant _fromEpoch(int ms) =>
    UtcInstant.fromDateTime(DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true));
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/mappers/flight_mapper_test.dart`
Expected: PASS — all tests in the file, including the two new round-trip tests and the
pre-existing `flightToRow`/`flightRouteLegRows`/`flightApproachRows` tests from M2.

- [ ] **Step 5: Full local verification and commit**

```powershell
dart format --set-exit-if-changed .
flutter analyze --fatal-infos
flutter test
```

```bash
git add lib/data/mappers/flight_mapper.dart test/data/mappers/flight_mapper_test.dart
git commit -m "feat: reconstruct a Flight from its stored row shape (#35)"
```

---

## Task 3: `DriftFlightReadRepository` — `find` and `findDraft`

**Files:**
- Create: `lib/data/repositories/flight_read_repository_drift.dart`
- Test: `test/data/repositories/flight_read_repository_find_test.dart`

**Interfaces:**
- Consumes: `FlightReadRepository`, `FlightRecord`, `ProjectedFlight` (Task 1); `flightFromRow`
  (Task 2); `AircraftRepository.find` (M2); `Projection`/`ProjectionResult` (M1).
- Produces: `DriftFlightReadRepository(AppDatabase db)` with `find`/`findDraft` implemented
  (`watchFlights`/`watchDrafts` remain unimplemented until Tasks 4-5 — the class will not
  analyze clean after this task; see Global Constraints).

- [ ] **Step 1: Write the failing test**

Create `test/data/repositories/flight_read_repository_find_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:easa_digital_log/data/database.dart';
import 'package:easa_digital_log/data/repositories/aircraft_repository.dart';
import 'package:easa_digital_log/data/repositories/flight_read_repository_drift.dart';
import 'package:easa_digital_log/data/repositories/flight_repository_drift.dart';
import 'package:easa_digital_log/domain/model/aircraft.dart';
import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:easa_digital_log/domain/projection/projection.dart';
import 'package:easa_digital_log/domain/projection/projection_result.dart';
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

Flight _flight() {
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
    remarks: '',
  );
}

/// A fixed, recognisable result — this task tests wiring, not projection
/// correctness (M1's job).
class _StubProjection implements Projection {
  @override
  ProjectionResult project(Flight flight, Aircraft aircraft) {
    return const ProjectionResult(
      jurisdictionId: 'test.stub',
      quantities: {},
    );
  }

  @override
  ProjectionResult projectAggregate(Iterable<(Flight, Aircraft)> flights) {
    throw UnimplementedError();
  }
}

void main() {
  late AppDatabase db;
  late DriftFlightReadRepository reads;
  late DriftFlightRepository writes;
  late String aircraftId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    reads = DriftFlightReadRepository(db);
    writes = DriftFlightRepository(db);
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

  test('find returns a committed flight, projected', () async {
    final id = await writes.createDraft(_flight(), aircraftId: aircraftId);
    await writes.commit(id);

    final result = await reads.find(id, projection: _StubProjection());

    expect(result, isNotNull);
    expect(result!.record.id, id);
    expect(result.record.flight, _flight());
    expect(result.record.aircraft.registration, 'G-ABCD');
    expect(result.projection.jurisdictionId, 'test.stub');
  });

  test('find returns a tombstoned flight', () async {
    final id = await writes.createDraft(_flight(), aircraftId: aircraftId);
    await writes.commit(id);
    await writes.tombstone(id);

    final result = await reads.find(id, projection: _StubProjection());

    expect(result, isNotNull);
  });

  test('find returns null for a draft', () async {
    final id = await writes.createDraft(_flight(), aircraftId: aircraftId);

    expect(await reads.find(id, projection: _StubProjection()), isNull);
  });

  test('find returns null for an unknown id', () async {
    expect(
      await reads.find('nonexistent', projection: _StubProjection()),
      isNull,
    );
  });

  test('findDraft returns a draft', () async {
    final id = await writes.createDraft(_flight(), aircraftId: aircraftId);

    final result = await reads.findDraft(id);

    expect(result, isNotNull);
    expect(result!.flight, _flight());
  });

  test('findDraft returns null for a committed flight', () async {
    final id = await writes.createDraft(_flight(), aircraftId: aircraftId);
    await writes.commit(id);

    expect(await reads.findDraft(id), isNull);
  });

  test(
    'find throws if a flight references an aircraft that no longer exists',
    () async {
      final id = await writes.createDraft(_flight(), aircraftId: aircraftId);
      await writes.commit(id);

      // FK enforcement (PRAGMA foreign_keys = ON, set in AppDatabase)
      // normally makes this state unreachable — deleting a referenced
      // aircraft is rejected. Turning it off here is the only way to
      // construct the dangling reference this defensive check exists for.
      await db.customStatement('PRAGMA foreign_keys = OFF');
      await (db.delete(
        db.aircraftsTable,
      )..where((t) => t.id.equals(aircraftId))).go();
      await db.customStatement('PRAGMA foreign_keys = ON');

      expect(
        () => reads.find(id, projection: _StubProjection()),
        throwsStateError,
      );
    },
  );
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/repositories/flight_read_repository_find_test.dart`
Expected: FAIL — `flight_read_repository_drift.dart` does not exist.

- [ ] **Step 3: Implement `find`/`findDraft`**

Create `lib/data/repositories/flight_read_repository_drift.dart`:

```dart
import '../../domain/projection/projection.dart';
import '../../domain/repository/flight_read_repository.dart';
import '../database.dart';
import '../mappers/flight_mapper.dart';
import 'aircraft_repository.dart';

class DriftFlightReadRepository implements FlightReadRepository {
  DriftFlightReadRepository(this._db) : _aircraft = AircraftRepository(_db);

  final AppDatabase _db;
  final AircraftRepository _aircraft;

  @override
  Future<ProjectedFlight?> find(
    String flightId, {
    required Projection projection,
  }) async {
    final row = await (_db.select(_db.flightsTable)..where(
      (t) => t.id.equals(flightId) & t.committedAt.isNotNull(),
    )).getSingleOrNull();
    if (row == null) {
      return null;
    }
    return _projectedFromRow(row, projection);
  }

  @override
  Future<FlightRecord?> findDraft(String flightId) async {
    final row = await (_db.select(
      _db.flightsTable,
    )..where((t) => t.id.equals(flightId) & t.committedAt.isNull())).getSingleOrNull();
    if (row == null) {
      return null;
    }
    return _recordFromRow(row);
  }

  Future<ProjectedFlight> _projectedFromRow(
    FlightRow row,
    Projection projection,
  ) async {
    final record = await _recordFromRow(row);
    return ProjectedFlight(
      record: record,
      projection: projection.project(record.flight, record.aircraft),
    );
  }

  Future<FlightRecord> _recordFromRow(FlightRow row) async {
    final legs = await (_db.select(
      _db.flightRouteLegsTable,
    )..where((t) => t.flightId.equals(row.id))).get();
    final approaches = await (_db.select(
      _db.flightApproachesTable,
    )..where((t) => t.flightId.equals(row.id))).get();

    final aircraft = await _aircraft.find(row.aircraftId);
    if (aircraft == null) {
      throw StateError(
        'Flight ${row.id} references aircraft ${row.aircraftId}, which no '
        'longer exists',
      );
    }

    final flight = flightFromRow(
      row,
      legs,
      approaches,
      aircraftRegistration: aircraft.registration,
    );

    return FlightRecord(id: row.id, flight: flight, aircraft: aircraft);
  }
}
```

This does not yet implement `watchFlights`/`watchDrafts` — `flutter analyze` will report
`DriftFlightReadRepository` is missing those two overrides. That is expected; Tasks 4 and 5 add
them. Do not add stub implementations.

- [ ] **Step 4: Run test to verify it fails on the expected error**

Run: `flutter test test/data/repositories/flight_read_repository_find_test.dart`
Expected: FAIL — compilation error naming `watchFlights`/`watchDrafts` as missing overrides on
`DriftFlightReadRepository`, not any error about `find`/`findDraft`/`flightFromRow`. This is the
same intermediate state M2's Task 7 documented; proceed to Task 4.

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories/flight_read_repository_drift.dart test/data/repositories/flight_read_repository_find_test.dart
git commit -m "feat: FlightReadRepository.find/findDraft (#35) — watch methods in the next commits"
```

If a pre-commit hook is installed (`git config core.hooksPath`), it will block this commit on
`flutter analyze --fatal-infos` for the same reason M2's Task 7 did — uninstall it for this one
commit and restore it after Task 5, or check with the user before committing an
analyze-incomplete state.

---

## Task 4: `watchFlights` with `FlightQuery` filtering

**Files:**
- Modify: `lib/data/repositories/flight_read_repository_drift.dart`
- Test: `test/data/repositories/flight_read_repository_watch_test.dart`

**Interfaces:**
- Consumes: `FlightQuery`, `CapacityFilter` (Task 1); everything from Task 3.
- Produces: `watchFlights` implemented on `DriftFlightReadRepository` (`watchDrafts` still
  missing until Task 5).

- [ ] **Step 1: Write the failing test**

Create `test/data/repositories/flight_read_repository_watch_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:easa_digital_log/data/database.dart';
import 'package:easa_digital_log/data/repositories/aircraft_repository.dart';
import 'package:easa_digital_log/data/repositories/flight_read_repository_drift.dart';
import 'package:easa_digital_log/data/repositories/flight_repository_drift.dart';
import 'package:easa_digital_log/domain/model/aircraft.dart';
import 'package:easa_digital_log/domain/model/calendar_date.dart';
import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:easa_digital_log/domain/projection/projection.dart';
import 'package:easa_digital_log/domain/projection/projection_result.dart';
import 'package:easa_digital_log/domain/repository/flight_read_repository.dart';
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

Flight _flight({
  List<String> route = const ['EGKA', 'EGKB'],
  UtcInstant? offBlocks,
  PilotCapacity capacity = _capacity,
  List<Approach> approaches = const [],
}) {
  final off = offBlocks ?? UtcInstant.utc(2026, 6, 1, 10);
  return Flight(
    aircraftRegistration: 'G-ABCD',
    route: route,
    prePlannedNavigation: false,
    offBlocks: off,
    onBlocks: off.add(const Duration(hours: 1)),
    capacity: capacity,
    carryingPassengers: false,
    takeoffs: const CircuitCounts(dayFullStop: 1),
    landings: const CircuitCounts(dayFullStop: 1),
    ifrFlightPlanFiled: false,
    actualInstrumentTime: FlightDuration.zero,
    simulatedInstrumentTime: FlightDuration.zero,
    approaches: approaches,
    holdingProceduresCount: 0,
    trackingPerformed: false,
    remarks: '',
  );
}

class _StubProjection implements Projection {
  @override
  ProjectionResult project(Flight flight, Aircraft aircraft) {
    return const ProjectionResult(
      jurisdictionId: 'test.stub',
      quantities: {},
    );
  }

  @override
  ProjectionResult projectAggregate(Iterable<(Flight, Aircraft)> flights) {
    throw UnimplementedError();
  }
}

void main() {
  late AppDatabase db;
  late DriftFlightReadRepository reads;
  late DriftFlightRepository writes;
  late String aircraftId;
  late String secondAircraftId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    reads = DriftFlightReadRepository(db);
    writes = DriftFlightRepository(db);
    final aircraft = AircraftRepository(db);
    aircraftId = await aircraft.upsert(
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
    secondAircraftId = await aircraft.upsert(
      const Aircraft(
        registration: 'G-WXYZ',
        manufacturer: 'Piper',
        model: 'PA-28',
        category: AircraftCategory.aeroplane,
        engineType: EngineType.piston,
        engineCount: 1,
        operatingSurface: OperatingSurface.land,
        requiresMultiCrew: false,
      ),
    );
  });

  tearDown(() => db.close());

  Future<String> commitFlight(Flight flight, {String? aircraft}) async {
    final id = await writes.createDraft(flight, aircraftId: aircraft ?? aircraftId);
    await writes.commit(id);
    return id;
  }

  test('excludes drafts and tombstoned flights by default', () async {
    final draftId = await writes.createDraft(_flight(), aircraftId: aircraftId);
    final activeId = await commitFlight(_flight());
    final tombstonedId = await commitFlight(_flight());
    await writes.tombstone(tombstonedId);

    final result = await reads.watchFlights(projection: _StubProjection()).first;
    final ids = result.map((p) => p.record.id).toSet();

    expect(ids, {activeId});
    expect(ids, isNot(contains(draftId)));
    expect(ids, isNot(contains(tombstonedId)));
  });

  test('filters by aircraftId', () async {
    final matchId = await commitFlight(_flight());
    await commitFlight(_flight(), aircraft: secondAircraftId);

    final result = await reads
        .watchFlights(
          projection: _StubProjection(),
          query: FlightQuery(aircraftId: aircraftId),
        )
        .first;

    expect(result.map((p) => p.record.id), [matchId]);
  });

  test('filters by date range', () async {
    final inRangeId = await commitFlight(
      _flight(offBlocks: UtcInstant.utc(2026, 6, 15, 9)),
    );
    await commitFlight(_flight(offBlocks: UtcInstant.utc(2026, 7, 1, 9)));

    final result = await reads
        .watchFlights(
          projection: _StubProjection(),
          query: const FlightQuery(
            from: CalendarDate(2026, 6, 1),
            to: CalendarDate(2026, 6, 30),
          ),
        )
        .first;

    expect(result.map((p) => p.record.id), [inRangeId]);
  });

  test('filters by aerodrome via a route leg', () async {
    final matchId = await commitFlight(
      _flight(route: const ['EGKA', 'EGSU']),
    );
    await commitFlight(_flight(route: const ['EGKA', 'EGKB']));

    final result = await reads
        .watchFlights(
          projection: _StubProjection(),
          query: const FlightQuery(aerodromeIdentifier: 'EGSU'),
        )
        .first;

    expect(result.map((p) => p.record.id), [matchId]);
  });

  test('filters by aerodrome via an approach-only match', () async {
    final matchId = await commitFlight(
      _flight(
        route: const ['EGKA', 'EGKB'],
        approaches: const [
          Approach(
            type: ApproachType.ils,
            aerodromeIcao: 'EGHI',
            runway: '20',
            count: 1,
          ),
        ],
      ),
    );
    await commitFlight(_flight());

    final result = await reads
        .watchFlights(
          projection: _StubProjection(),
          query: const FlightQuery(aerodromeIdentifier: 'EGHI'),
        )
        .first;

    expect(result.map((p) => p.record.id), [matchId]);
  });

  test('filters by capacity', () async {
    final instructorId = await commitFlight(
      _flight(capacity: _capacity.copyWith(actingAsInstructor: true)),
    );
    await commitFlight(_flight());

    final result = await reads
        .watchFlights(
          projection: _StubProjection(),
          query: const FlightQuery(
            capacity: CapacityFilter(actingAsInstructor: true),
          ),
        )
        .first;

    expect(result.map((p) => p.record.id), [instructorId]);
  });

  test('combines aircraft and date range filters', () async {
    final matchId = await commitFlight(
      _flight(offBlocks: UtcInstant.utc(2026, 6, 15, 9)),
    );
    await commitFlight(
      _flight(offBlocks: UtcInstant.utc(2026, 6, 15, 9)),
      aircraft: secondAircraftId,
    );
    await commitFlight(_flight(offBlocks: UtcInstant.utc(2026, 7, 15, 9)));

    final result = await reads
        .watchFlights(
          projection: _StubProjection(),
          query: FlightQuery(
            aircraftId: aircraftId,
            from: const CalendarDate(2026, 6, 1),
            to: const CalendarDate(2026, 6, 30),
          ),
        )
        .first;

    expect(result.map((p) => p.record.id), [matchId]);
  });

  test('re-emits when a matching flight is committed', () async {
    final stream = reads.watchFlights(projection: _StubProjection());
    final emissions = stream.take(2).toList();
    await Future<void>.delayed(Duration.zero);

    final id = await writes.createDraft(_flight(), aircraftId: aircraftId);
    await writes.commit(id);

    final results = await emissions;
    expect(results[0], isEmpty);
    expect(results[1].map((p) => p.record.id), contains(id));
  });

  test('re-emits when a flight is tombstoned', () async {
    final id = await commitFlight(_flight());

    final stream = reads.watchFlights(projection: _StubProjection());
    final emissions = stream.take(2).toList();
    await Future<void>.delayed(Duration.zero);

    await writes.tombstone(id);

    final results = await emissions;
    expect(results[0].map((p) => p.record.id), contains(id));
    expect(results[1].map((p) => p.record.id), isNot(contains(id)));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/repositories/flight_read_repository_watch_test.dart`
Expected: FAIL — `watchFlights` is not implemented.

- [ ] **Step 3: Implement `watchFlights`**

In `lib/data/repositories/flight_read_repository_drift.dart`, change the imports at the top to:

```dart
import 'package:drift/drift.dart';

import '../../domain/projection/projection.dart';
import '../../domain/repository/flight_read_repository.dart';
import '../database.dart';
import '../mappers/flight_mapper.dart';
import 'aircraft_repository.dart';
```

Add this method to `DriftFlightReadRepository`, before `_projectedFromRow`:

```dart
  @override
  Stream<List<ProjectedFlight>> watchFlights({
    required Projection projection,
    FlightQuery query = const FlightQuery(),
  }) {
    final statement = _db.select(_db.flightsTable)
      ..where((t) => t.committedAt.isNotNull() & t.tombstonedAt.isNull());

    if (query.aircraftId != null) {
      final aircraftId = query.aircraftId!;
      statement.where((t) => t.aircraftId.equals(aircraftId));
    }
    if (query.from != null) {
      final fromMs = _startOfDayUtcMs(query.from!);
      statement.where((t) => t.offBlocks.isBiggerOrEqualValue(fromMs));
    }
    if (query.to != null) {
      final toMs = _endOfDayUtcMs(query.to!);
      statement.where((t) => t.offBlocks.isSmallerOrEqualValue(toMs));
    }
    if (query.aerodromeIdentifier != null) {
      final identifier = query.aerodromeIdentifier!;
      statement.where(
        (t) =>
            existsQuery(
              _db.select(_db.flightRouteLegsTable)..where(
                (l) => l.flightId.equalsExp(t.id) & l.identifier.equals(identifier),
              ),
            ) |
            existsQuery(
              _db.select(_db.flightApproachesTable)..where(
                (a) =>
                    a.flightId.equalsExp(t.id) &
                    a.aerodromeIcao.equals(identifier),
              ),
            ),
      );
    }
    if (query.capacity != null) {
      _applyCapacityFilter(statement, query.capacity!);
    }

    return statement
        .watch()
        .asyncMap(
          (rows) async => [
            for (final row in rows) await _projectedFromRow(row, projection),
          ],
        );
  }

  void _applyCapacityFilter(
    SimpleSelectStatement<FlightsTable, FlightRow> statement,
    CapacityFilter filter,
  ) {
    if (filter.commandAuthority != null) {
      final value = filter.commandAuthority!;
      statement.where((t) => t.capacityCommandAuthority.equals(value));
    }
    if (filter.soleManipulator != null) {
      final value = filter.soleManipulator!;
      statement.where((t) => t.capacitySoleManipulator.equals(value));
    }
    if (filter.soleOccupant != null) {
      final value = filter.soleOccupant!;
      statement.where((t) => t.capacitySoleOccupant.equals(value));
    }
    if (filter.multiPilotOperation != null) {
      final value = filter.multiPilotOperation!;
      statement.where((t) => t.capacityMultiPilotOperation.equals(value));
    }
    if (filter.actingAsInstructor != null) {
      final value = filter.actingAsInstructor!;
      statement.where((t) => t.capacityActingAsInstructor.equals(value));
    }
    if (filter.actingAsExaminer != null) {
      final value = filter.actingAsExaminer!;
      statement.where((t) => t.capacityActingAsExaminer.equals(value));
    }
    if (filter.picusClaimed != null) {
      final value = filter.picusClaimed!;
      statement.where((t) => t.capacityPicusClaimed.equals(value));
    }
  }

  int _startOfDayUtcMs(CalendarDate date) =>
      DateTime.utc(date.year, date.month, date.day).millisecondsSinceEpoch;

  int _endOfDayUtcMs(CalendarDate date) => DateTime.utc(
    date.year,
    date.month,
    date.day,
    23,
    59,
    59,
    999,
  ).millisecondsSinceEpoch;
```

Add `import '../../domain/model/calendar_date.dart';` to the imports too (needed for the
`CalendarDate` parameter type on `_startOfDayUtcMs`/`_endOfDayUtcMs`).

`watchDrafts` is still missing — `flutter analyze` will still report one missing override. This
is expected; Task 5 adds it.

- [ ] **Step 4: Run test to verify it fails on the expected remaining error**

Run: `flutter test test/data/repositories/flight_read_repository_watch_test.dart`
Expected: FAIL — compilation error naming only `watchDrafts` as a missing override, not
anything about `watchFlights` or the filters. If the error instead names a Drift method that
doesn't exist (`existsQuery`, `equalsExp`, `isBiggerOrEqualValue`, `isSmallerOrEqualValue`),
check the installed `drift` version's query-builder documentation for the current equivalent —
this is the API-drift risk flagged in Global Constraints, not a design problem.

- [ ] **Step 5: Commit**

```bash
git add lib/data/repositories/flight_read_repository_drift.dart test/data/repositories/flight_read_repository_watch_test.dart
git commit -m "feat: FlightReadRepository.watchFlights with filtering (#35) — watchDrafts next"
```

---

## Task 5: `watchDrafts` — completing the repository

**Files:**
- Modify: `lib/data/repositories/flight_read_repository_drift.dart`
- Test: `test/data/repositories/flight_read_repository_drafts_test.dart`

**Interfaces:**
- Consumes: everything from Tasks 1-4.
- Produces: `watchDrafts` implemented — `DriftFlightReadRepository` is now a complete,
  non-abstract class implementing every `FlightReadRepository` method.

- [ ] **Step 1: Write the failing test**

Create `test/data/repositories/flight_read_repository_drafts_test.dart`:

```dart
import 'package:drift/native.dart';
import 'package:easa_digital_log/data/database.dart';
import 'package:easa_digital_log/data/repositories/aircraft_repository.dart';
import 'package:easa_digital_log/data/repositories/flight_read_repository_drift.dart';
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

Flight _flight() {
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
    remarks: '',
  );
}

void main() {
  late AppDatabase db;
  late DriftFlightReadRepository reads;
  late DriftFlightRepository writes;
  late String aircraftId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    reads = DriftFlightReadRepository(db);
    writes = DriftFlightRepository(db);
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

  test('returns only drafts', () async {
    final draftId = await writes.createDraft(_flight(), aircraftId: aircraftId);
    final committedId = await writes.createDraft(_flight(), aircraftId: aircraftId);
    await writes.commit(committedId);

    final result = await reads.watchDrafts().first;

    expect(result.map((r) => r.id), [draftId]);
  });

  test('re-emits when a draft is committed, and it disappears from the list', () async {
    final id = await writes.createDraft(_flight(), aircraftId: aircraftId);

    final stream = reads.watchDrafts();
    final emissions = stream.take(2).toList();
    await Future<void>.delayed(Duration.zero);

    await writes.commit(id);

    final results = await emissions;
    expect(results[0].map((r) => r.id), contains(id));
    expect(results[1].map((r) => r.id), isNot(contains(id)));
  });
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `flutter test test/data/repositories/flight_read_repository_drafts_test.dart`
Expected: FAIL — `watchDrafts` is not implemented.

- [ ] **Step 3: Implement `watchDrafts`**

Add this method to `DriftFlightReadRepository`, alongside `watchFlights`:

```dart
  @override
  Stream<List<FlightRecord>> watchDrafts() {
    final statement = _db.select(_db.flightsTable)
      ..where((t) => t.committedAt.isNull());

    return statement.watch().asyncMap(
      (rows) async => [for (final row in rows) await _recordFromRow(row)],
    );
  }
```

- [ ] **Step 4: Run test to verify it passes**

Run: `flutter test test/data/repositories/flight_read_repository_drafts_test.dart`
Expected: PASS. Then re-run every earlier test file for this repository, all of which were
blocked on the class compiling:

Run: `flutter test test/data/repositories/flight_read_repository_find_test.dart test/data/repositories/flight_read_repository_watch_test.dart`
Expected: PASS

- [ ] **Step 5: Full local verification**

```powershell
dart format --set-exit-if-changed .
flutter analyze --fatal-infos
dart run tool/check_layering.dart
dart run tool/check_domain_types.dart
flutter test
```
Expected: all clean — this is the first point `DriftFlightReadRepository` is a complete class,
so the first `flutter analyze` that can pass for this file.

- [ ] **Step 6: Commit**

```bash
git add lib/data/repositories/flight_read_repository_drift.dart test/data/repositories/flight_read_repository_drafts_test.dart
git commit -m "feat: FlightReadRepository.watchDrafts, completing the read repository (#35)"
```

If Task 3 or 4 was committed with the pre-commit hook uninstalled, restore it now
(`git config core.hooksPath tool/hooks`) — this is the commit that makes the whole class
analyze-clean.

---

## Self-Review

**Spec coverage:** Result/query types and interface — Task 1. Row→domain mapper — Task 2.
`find`/`findDraft` (single lookups, tombstoned-visible-via-find, dangling-aircraft contract) —
Task 3. `watchFlights` with every `FlightQuery` filter (date range, aircraft, aerodrome via both
route and approach, capacity, combined) and reactivity — Task 4. `watchDrafts` and its
reactivity — Task 5. Every item in the spec's Non-goals section (aggregates, currency,
comparison UI, pagination) has no task — correctly, since the spec explicitly excludes them.

**Placeholder scan:** No stub method bodies anywhere. Tasks 3 and 4 each leave
`DriftFlightReadRepository` genuinely incomplete between commits, exactly as documented in
Global Constraints and in each task's own text — not a placeholder, a deliberate, explained
intermediate state matching M2's established pattern.

**Type consistency:** `FlightReadRepository`'s abstract methods (Task 1) match
`DriftFlightReadRepository`'s overrides (Tasks 3-5) exactly in name and signature.
`flightFromRow`'s signature (Task 2) matches every call site in `_recordFromRow` (Task 3).
`FlightQuery`/`CapacityFilter` field names (Task 1) match every reference in `watchFlights`/
`_applyCapacityFilter` (Task 4) and every test file that constructs one (Tasks 3-5).
