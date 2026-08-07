# M1 Value Types Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the three pure-Dart value types that `Flight` (#11) is built from — duration (#16), UTC instant (#15) and pilot operating capacity (#13) — as the first code in `lib/domain/`.

**Architecture:** Three small immutable value types under `lib/domain/model/`, plus a second `tool/` guard that mechanically bans raw `DateTime` from the domain layer. `FlightDuration` and `UtcInstant` are hand-written (single-field wrappers; freezed would add a generated file for a four-line `==`/`hashCode`). `PilotCapacity` and its two companions use freezed. No new dependencies.

**Tech Stack:** Dart 3.12.0 / Flutter 3.44.0 via puro. `freezed ^3.2.5` + `build_runner` (already wired, ADR-0006). Tests via `package:flutter_test/flutter_test.dart`. Fixtures in YAML via the existing `loadFixture` harness.

---

## Global Constraints

Every task's requirements implicitly include this section.

1. **`flutter` and `dart` are puro shims that work ONLY under PowerShell.** They are broken under Git Bash. Use the PowerShell tool for every toolchain command. This bit every M0 subagent.
2. **`lib/domain/` must never import** `package:flutter/*`, `package:flutter_test/*`, `dart:io`, `dart:ui`, `dart:ffi`, `dart:isolate`, `dart:developer`, `dart:mirrors`, `dart:cli`, `dart:html`, `dart:js`, or any `package:easa_digital_log/{data,io,export,ui}/`. Enforced by `dart run tool/check_layering.dart`.
3. **Do not use `package:meta`** (e.g. `@immutable`). It is not a declared dependency and `depend_on_referenced_packages` (via `flutter_lints`) will flag it. Use `final` fields and `const` constructors.
4. **Do not add any dependency.** CLAUDE.md requires asking first, and nothing here needs one.
5. **freezed 3.x form is mandatory:** `@freezed abstract class X with _$X`. The bare `@freezed class X with _$X` form is a freezed 2.x-only construct and is an error under 3.x (ADR-0006).
6. **Tests import `package:flutter_test/flutter_test.dart`**, which re-exports `test`/`group`/`expect`. There is no `package:test` dependency and none may be added.
7. **Rule 1 (CLAUDE.md): never store a derived quantity.** No `picTime`, `nightTime`, `crossCountryTime`, `totalTime`, `picusTime`, `spicTime`, `isCrossCountry`. These are projection outputs.
8. **Rule 3 (CLAUDE.md): all stored times are UTC.** Never persist a local or naive `DateTime`.
9. **Fixtures hold raw facts only.** Expected projection outcomes go in YAML *comments*, marked "NOT stored here" — the precedent set by `test/fixtures/flights/faa_easa_divergence.yaml`.
10. **Quote anything time-shaped or aerodrome-shaped in YAML** (`"1:30"`, `"EGKA"`, `"NO"`) — see the caveat in `test/fixtures/README.md`.
11. **Cite the specific rule** (`AMC1 FCL.050(b)(1)`, `§61.51(e)(1)(i)`, `FCL.010`) in a code comment AND in the commit message whenever a change touches regulatory interpretation.
12. **Conventional commits** (`feat:`, `fix:`, `refactor:`). One commit per task.
13. **The full local pipeline must be clean before every commit**, in this exact order (format BEFORE codegen, so it never sees gitignored generated output):

    ```powershell
    flutter pub get
    dart format --set-exit-if-changed .
    dart run build_runner build --delete-conflicting-outputs
    flutter analyze --fatal-infos
    dart run tool/check_layering.dart
    dart run tool/check_domain_types.dart   # exists from Task 2 onward only
    flutter test
    ```

14. **Strict analysis is on:** `strict-casts`, `strict-inference`, `strict-raw-types`, plus `always_declare_return_types`, `prefer_final_locals`, `avoid_dynamic_calls`, `require_trailing_commas`.
15. **Every guard test must be verified red-then-green** against the real guard. The M0 layering guard passed seven tests while being fundamentally broken; asserting a test passes is not evidence it can fail.

---

## File Structure

```
lib/domain/model/
  flight_duration.dart        Task 1  hand-written value type
  utc_instant.dart            Task 2  hand-written value type
  wall_clock.dart             Task 2  hand-written value type
  pilot_capacity.dart         Task 3  freezed
  instructor_presence.dart    Task 3  freezed
  countersignature.dart       Task 3  freezed
tool/
  dart_source.dart            Task 2  shared comment stripping
  check_domain_types.dart     Task 2  bans raw DateTime in lib/domain/
test/domain/model/
  flight_duration_test.dart   Task 1
  utc_instant_test.dart       Task 2
  capacity_scenarios.dart     Task 3  the scenario table #18/#19 will consume
  pilot_capacity_test.dart    Task 3
test/tool/
  check_domain_types_test.dart Task 2
test/fixtures/capacities/     Task 3  12 scenario YAML files
test/fixtures/decoders/
  pilot_capacity_fixture.dart Task 3
docs/adr/
  0007-duration-representation.md      Task 1
  0008-capacity-as-composed-facts.md   Task 3
```

---

## Task 1: FlightDuration (issue #16)

**Files:**
- Create: `lib/domain/model/flight_duration.dart`
- Create: `test/domain/model/flight_duration_test.dart`
- Create: `docs/adr/0007-duration-representation.md`
- Modify: `docs/adr/README.md` (add the ADR-0007 index row)

**Interfaces:**
- Consumes: nothing.
- Produces: `class FlightDuration` with `const FlightDuration(int inMinutes)`, `static const FlightDuration zero`, `int get inMinutes`, `String toHoursMinutes()`, `String toDecimalHours()`, `factory FlightDuration.parseHoursMinutes(String)`, `factory FlightDuration.parseDecimalHours(String)`, `static FlightDuration sum(Iterable<FlightDuration>)`, `operator +`, `operator -`, `operator <`, `operator <=`, `operator >`, `operator >=`, `bool get isNegative`, `compareTo`. Task 3 uses `FlightDuration` for `PilotCapacity.manipulationTime`.

### Why this exists

Logbook time is `HH:MM` under EASA and decimal hours under the FAA. A `double hours` field accumulates float error across thousands of flights, and the M6 golden PDF test then fails intermittently and inexplicably — thousands of flights away from the cause. Integer minutes make the arithmetic exact; decimal is a *display* format only.

- [ ] **Step 1: Write the failing tests**

Create `test/domain/model/flight_duration_test.dart`. These two are the load-bearing ones — both are mutation-resistant, meaning a plausible-looking wrong implementation turns them red:

```dart
// flutter_test re-exports test/group/expect from package:test_api, so plain
// Dart tests need no separate package:test dependency.
import 'package:flutter_test/flutter_test.dart';

import 'package:easa_digital_log/domain/model/flight_duration.dart';

void main() {
  group('FlightDuration', () {
    test('sums ten thousand flights with exact integer arithmetic', () {
      final flights = List<FlightDuration>.filled(
        10000,
        FlightDuration.parseHoursMinutes('1:23'),
      );

      final total = FlightDuration.sum(flights);

      // 10,000 x 83 minutes.
      expect(total, const FlightDuration(830000));
      expect(total.inMinutes, 830000);
      expect(total.toHoursMinutes(), '13833:20');
      expect(total.toDecimalHours(), '13833.3');
    });

    test('rounding at the display boundary is not the same as rounding first', () {
      // This is the whole reason the type exists. Summing the DISPLAY values
      // instead of the stored minutes is wrong by 166.7 hours over 10,000
      // flights, and nothing about the printed total would look suspicious.
      final one = FlightDuration.parseHoursMinutes('1:23');

      var roundedFirst = 0.0;
      for (var i = 0; i < 10000; i++) {
        roundedFirst += double.parse(one.toDecimalHours());
      }

      expect(roundedFirst, 14000.0);
      expect(FlightDuration.sum(List.filled(10000, one)).toDecimalHours(), '13833.3');
    });

    test('decimal hours round-trip from decimal to minutes and back', () {
      // Minutes CANNOT round-trip through decimal hours: at one decimal place
      // only multiples of 6 minutes survive. The guaranteed direction is
      // decimal -> minutes -> decimal, which is what import fidelity needs.
      const samples = <String>[
        '0.0', '0.1', '0.5', '1.0', '1.4', '2.5', '12.3', '999.9',
      ];

      for (final sample in samples) {
        expect(
          FlightDuration.parseDecimalHours(sample).toDecimalHours(),
          sample,
          reason: 'round-trip failed for $sample',
        );
      }
    });

    test('parses decimal hours with integer arithmetic, not doubles', () {
      // double.parse('1.4') * 60 == 84.00000000000001. If the implementation
      // routes through a double, one of these will be off by a minute.
      expect(FlightDuration.parseDecimalHours('1.4').inMinutes, 84);
      expect(FlightDuration.parseDecimalHours('1.45').inMinutes, 87);
      expect(FlightDuration.parseDecimalHours('0.05').inMinutes, 3);
      expect(FlightDuration.parseDecimalHours('0.1').inMinutes, 6);
      expect(FlightDuration.parseDecimalHours('2').inMinutes, 120);
      expect(FlightDuration.parseDecimalHours('100.0').inMinutes, 6000);
    });

    test('formats decimal hours to tenths, half away from zero', () {
      const cases = <int, String>{
        0: '0.0',
        2: '0.0',    // 0.0333 h
        3: '0.1',    // 0.05 h exactly -> half away from zero
        6: '0.1',
        83: '1.4',   // 1.3833 h
        85: '1.4',   // 1.4166 h
        87: '1.5',   // 1.45 h exactly -> half away from zero
        90: '1.5',
      };

      cases.forEach((minutes, expected) {
        expect(FlightDuration(minutes).toDecimalHours(), expected,
            reason: '$minutes minutes');
      });
    });

    test('formats and parses HH:MM', () {
      const cases = <int, String>{
        0: '00:00',
        59: '00:59',
        60: '01:00',
        83: '01:23',
        6000: '100:00',
        74096: '1234:56',
      };

      cases.forEach((minutes, expected) {
        expect(FlightDuration(minutes).toHoursMinutes(), expected);
        expect(FlightDuration.parseHoursMinutes(expected).inMinutes, minutes);
      });

      // Unpadded hours are accepted on input even though output pads to two.
      expect(FlightDuration.parseHoursMinutes('1:23').inMinutes, 83);
    });

    test('rejects malformed input', () {
      const bad = <String>[
        '', 'abc', '1:60', '1:5', '1:', ':30', '-1:00', '1:23:45',
        '1.4.5', '1,4', '.5', '-1.4', '1.0000000000',
      ];

      for (final source in bad) {
        expect(
          () => source.contains(':')
              ? FlightDuration.parseHoursMinutes(source)
              : FlightDuration.parseDecimalHours(source),
          throwsFormatException,
          reason: 'should reject "$source"',
        );
      }
    });

    test('orders, compares and de-duplicates by value', () {
      const a = FlightDuration(83);
      const b = FlightDuration(83);
      const c = FlightDuration(90);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(<FlightDuration>{a, b, c}, hasLength(2));
      expect(a < c, isTrue);
      expect(c > a, isTrue);
      expect(a <= b, isTrue);
      expect(<FlightDuration>[c, a].toList()..sort(), <FlightDuration>[a, c]);
      expect(a + c, const FlightDuration(173));
      expect((a - c).isNegative, isTrue);
      expect(FlightDuration.sum(const <FlightDuration>[]), FlightDuration.zero);
    });
  });
}
```

- [ ] **Step 2: Run the tests to verify they fail**

```powershell
flutter test test/domain/model/flight_duration_test.dart
```

Expected: FAIL — `Target of URI doesn't exist: 'package:easa_digital_log/domain/model/flight_duration.dart'`.

- [ ] **Step 3: Implement `FlightDuration`**

Create `lib/domain/model/flight_duration.dart`. The two arithmetic rules below are the substance of the task; get them wrong and the tests in Step 1 go red.

**Formatting to decimal — integer arithmetic, never `double`:**

```dart
final tenths = (inMinutes * 10 + 30) ~/ 60;   // + 30 = half away from zero
return '${tenths ~/ 10}.${tenths % 10}';
```

**Parsing decimal — integer arithmetic on the digit string, never `double.parse(x) * 60`:**

```dart
// '1.45' -> whole = 1, fractionDigits = 45, scale = 100
final minutes = whole * 60 + (fractionDigits * 60 + scale ~/ 2) ~/ scale;
// = 60 + (2700 + 50) ~/ 100 = 87
```

Requirements the tests pin:

- `toHoursMinutes()` pads hours to at least two digits and minutes to exactly two: `'01:23'`, `'1234:56'`.
- `parseHoursMinutes` accepts unpadded hours (`'1:23'`), requires exactly two minute digits, rejects minutes > 59, rejects a leading `-`, rejects more than one colon.
- `parseDecimalHours` accepts an optional fractional part (`'2'` is valid), rejects a leading `-`, rejects a leading `.`, rejects more than one `.`, and rejects more than **9** fractional digits with a `FormatException` (guarding the `fractionDigits * 60` multiply against overflow).
- Both parse factories throw `FormatException` naming the offending source string.
- Arithmetic is **closed**: `a - b` may go negative and reports `isNegative` rather than throwing. A value type that throws mid-computation is worse than one that reports. Rejecting a negative *flight* time is `Flight`'s validation job (#11), not this type's.
- `FlightDuration.sum` of an empty iterable is `FlightDuration.zero`.

The class dartdoc must state, in plain words:

- durations are stored as whole minutes, and why (exact arithmetic; the M6 golden PDF test);
- the decimal display policy — one place, half away from zero;
- **rounding happens only at the display or export boundary; totals are always summed in integer minutes and never from rounded values**;
- the round-trip is asymmetric: decimal → minutes → decimal is guaranteed, minutes → decimal → minutes is not, because only multiples of 6 minutes survive one decimal place.

- [ ] **Step 4: Run the tests to verify they pass**

```powershell
flutter test test/domain/model/flight_duration_test.dart
```

Expected: PASS, all 8 tests.

- [ ] **Step 5: Write ADR-0007**

Create `docs/adr/0007-duration-representation.md` following the shape of the existing ADRs (read `docs/adr/template.md` and `docs/adr/0002-utc-only.md` first — match their structure, tone and line wrapping exactly).

It records: integer minutes as the internal representation; the tenths / half-away-from-zero decimal display policy; the display-boundary rule; the asymmetric round-trip guarantee; and, under *Alternatives considered*, why `double` hours and Dart's own `Duration` were both rejected — `Duration` is already exact, but it admits sub-minute precision and its `inHours` truncates, so it does not make the wrong thing impossible to express.

Add the index row to `docs/adr/README.md`, matching the existing table format.

- [ ] **Step 6: Run the full local pipeline**

```powershell
flutter pub get
dart format --set-exit-if-changed .
dart run build_runner build --delete-conflicting-outputs
flutter analyze --fatal-infos
dart run tool/check_layering.dart
flutter test
```

All six must be clean. (`check_domain_types.dart` does not exist until Task 2.) If `dart format --set-exit-if-changed` fails, run `dart format .` and re-run — do not hand-edit whitespace.

- [ ] **Step 7: Commit**

```powershell
git add lib/domain/model/flight_duration.dart test/domain/model/flight_duration_test.dart docs/adr/0007-duration-representation.md docs/adr/README.md
git commit -m "feat: represent logbook durations as integer minutes (#16)"
```

The commit body should note the decimal display policy and that AMC1 FCL.050 column 7 permits either hours-and-minutes or decimal, which is why both formatters exist.

---

## Task 2: UtcInstant, WallClock and the raw-DateTime guard (issue #15)

**Files:**
- Create: `lib/domain/model/utc_instant.dart`
- Create: `lib/domain/model/wall_clock.dart`
- Create: `tool/dart_source.dart`
- Create: `tool/check_domain_types.dart`
- Create: `test/domain/model/utc_instant_test.dart`
- Create: `test/tool/check_domain_types_test.dart`
- Modify: `tool/check_layering.dart` (extract the comment stripper into `tool/dart_source.dart`)
- Modify: `.github/workflows/ci.yaml` (new step after `Check domain layering`)
- Modify: `docs/adr/0002-utc-only.md` (append an implementation record)

**Interfaces:**
- Consumes: nothing from Task 1.
- Produces: `class UtcInstant` and `class WallClock`. Task 3 uses `UtcInstant` for `Countersignature.signedAt`, `Countersignature.signatoryCredentialExpiry` and `InstructorPresence.credentialExpiry`. Also produces `List<TypeViolation> findBannedTypes(String filePath, String source)` in `tool/check_domain_types.dart`, whose `const bannedIdentifiers` list issue #11 will extend.

### Why this exists

`DateTime.isUtc` is trivially lost, and the failure is silent: a local timestamp persisted as UTC gives wrong night time and wrong currency with no exception and no test failure. Worse, `DateTime.parse('2026-03-14T09:05:00')` — no zone designator — returns a **local** `DateTime` without complaint. Make the wrong thing impossible to express rather than merely discouraged.

- [ ] **Step 1: Extract the shared comment stripper**

`tool/check_layering.dart` currently owns a private `_comment` regex and `_stripComments`. That regex took a full fix wave to get right in M0 (five fail-open evasion classes) and must not be duplicated. Move both into a new `tool/dart_source.dart`:

```dart
/// Shared source-text helpers for the `tool/` guards.
///
/// Both guards match Dart syntactically rather than depending on
/// `package:analyzer` (see ADR-0001). They therefore share one comment
/// stripper — duplicating this regex would mean fixing it twice.
library;

/// Matches a line comment or a block comment — whichever opens first.
///
/// The single alternation is load-bearing. The engine tries the alternatives
/// left to right at each position, so `// toggle: /*` is consumed as a line
/// comment (its `/*` never opens a block) and `/* a // b */` is consumed as a
/// block comment. Stripping one kind before the other — in *either* order —
/// lets the loser swallow real code.
final RegExp _comment = RegExp(r'//[^\n]*|/\*[\s\S]*?\*/');

/// Replaces comments with blanks, preserving line breaks so violation line
/// numbers still point at the real line.
String stripComments(String source) => source.replaceAllMapped(
  _comment,
  (match) => '\n' * '\n'.allMatches(match.group(0)!).length,
);
```

Update `tool/check_layering.dart` to `import 'dart_source.dart';` and use `stripComments`, deleting its private copies. Preserve the existing doc comments on `findViolations` verbatim — the fail-open/fail-closed discussion there is the record of an accepted gap and a decision your human partner made explicitly.

- [ ] **Step 2: Verify the extraction broke nothing**

```powershell
flutter test test/tool/check_layering_test.dart
```

Expected: PASS, all existing tests (19 at last count). If any fail, the extraction is wrong — fix it before going further.

- [ ] **Step 3: Write the failing guard tests**

Create `test/tool/check_domain_types_test.dart`. Model the file on the existing `test/tool/check_layering_test.dart` (read it first for the established shape).

```dart
import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_domain_types.dart';

void main() {
  group('findBannedTypes', () {
    const path = 'lib/domain/model/thing.dart';

    test('flags a DateTime field', () {
      const source = 'class Thing {\n  final DateTime when;\n}\n';
      final violations = findBannedTypes(path, source);

      expect(violations, hasLength(1));
      expect(violations.single.identifier, 'DateTime');
      expect(violations.single.line, 2);
    });

    test('flags a DateTime parameter', () {
      const source = 'void log(DateTime when) {}\n';
      expect(findBannedTypes(path, source), hasLength(1));
    });

    test('flags a DateTime return type', () {
      const source = 'DateTime now() => throw UnimplementedError();\n';
      expect(findBannedTypes(path, source), hasLength(1));
    });

    test('flags DateTime inside a generic', () {
      const source = 'final List<DateTime> stamps = <DateTime>[];\n';
      expect(findBannedTypes(path, source), hasLength(2));
    });

    test('flags DateTime as a map value type', () {
      const source = 'Map<String, DateTime> byName = {};\n';
      expect(findBannedTypes(path, source), hasLength(1));
    });

    test('flags DateTime.now(), which is nondeterminism as well as a raw type', () {
      const source = 'final stamp = DateTime.now();\n';
      expect(findBannedTypes(path, source), hasLength(1));
    });

    test('ignores DateTime in a line comment', () {
      const source = '// Never store a raw DateTime here.\nclass Thing {}\n';
      expect(findBannedTypes(path, source), isEmpty);
    });

    test('ignores DateTime in a block comment', () {
      const source = '/*\n * DateTime is banned.\n */\nclass Thing {}\n';
      expect(findBannedTypes(path, source), isEmpty);
    });

    test('ignores an identifier that merely contains DateTime', () {
      const source = 'class UtcDateTimeHolder {}\nfinal x = myDateTime;\n';
      expect(findBannedTypes(path, source), isEmpty);
    });

    test('allows the two files that must wrap DateTime', () {
      const source = 'final DateTime value = DateTime.utc(2026);\n';

      expect(
        findBannedTypes('lib/domain/model/utc_instant.dart', source),
        isEmpty,
      );
      expect(
        findBannedTypes('lib/domain/model/wall_clock.dart', source),
        isEmpty,
      );
      // Windows-style separators must resolve to the same allowlist entry.
      expect(
        findBannedTypes(r'lib\domain\model\utc_instant.dart', source),
        isEmpty,
      );
      // But a lookalike path is not allowlisted.
      expect(
        findBannedTypes('lib/domain/model/utc_instant_helper.dart', source),
        hasLength(2),
      );
    });

    test('reports every occurrence with its own line number', () {
      const source = 'final DateTime a = DateTime.utc(2026);\nfinal DateTime b = a;\n';
      final violations = findBannedTypes(path, source);

      expect(violations, hasLength(3));
      expect(violations.map((v) => v.line), <int>[1, 1, 2]);
    });
  });
}
```

- [ ] **Step 4: Run the guard tests to verify they fail**

```powershell
flutter test test/tool/check_domain_types_test.dart
```

Expected: FAIL — `Target of URI doesn't exist: '../../tool/check_domain_types.dart'`.

**Then, once the guard exists (Step 5), verify each test can actually fail.** For at least the comment cases, the allowlist case and the word-boundary case, temporarily break the corresponding line of the guard, confirm the test goes red, and restore it. Global Constraint 15: the M0 layering guard passed seven tests while being fundamentally broken. Record in your report which tests you verified red-then-green and how.

- [ ] **Step 5: Implement the guard**

Create `tool/check_domain_types.dart`, structured exactly like `tool/check_layering.dart` (read it first): a pure `findBannedTypes` function the tests exercise, plus a `main` that walks the tree, prints `file:line`, and exits non-zero on violations. It must exit 0 cleanly when `lib/domain` does not exist, and skip `*.freezed.dart` / `*.g.dart`.

```dart
/// Identifiers `lib/domain/` may not name. Extend this list rather than
/// adding special cases.
///
/// `DateTime` is banned outright — not merely as a field type. Rule 3 of
/// CLAUDE.md and ADR-0002 require every stored instant to be UTC, and
/// `DateTime.isUtc` is trivially lost. The blunt form also catches
/// `DateTime.now()`, which is nondeterminism the domain layer should not
/// have either. Issue #11 extends this list with derived-quantity names.
const List<String> bannedIdentifiers = <String>['DateTime'];

/// Files permitted to name a banned identifier, with the reason.
///
/// These two are the wrapper and its display companion: they exist precisely
/// to be the only place in `lib/domain/` that touches `DateTime`, so that
/// nothing else has to.
const List<String> allowlist = <String>[
  'lib/domain/model/utc_instant.dart',
  'lib/domain/model/wall_clock.dart',
];
```

Requirements:

- Match on a **word boundary**: `RegExp(r'\b' + identifier + r'\b')`. `UtcDateTimeHolder` and `myDateTime` must not match.
- Strip comments via `stripComments` from `tool/dart_source.dart` before matching.
- Normalise `\` to `/` before comparing against the allowlist, so Windows paths resolve.
- Compare the allowlist by **exact normalised path suffix**, not `contains` — `utc_instant_helper.dart` must not be allowlisted.
- Report one `TypeViolation { String filePath; int line; String identifier; }` per occurrence, with a `toString()` matching the style of `Violation` in `check_layering.dart`.
- Exit message on failure must point at CLAUDE.md rule 3 and ADR-0002, the way `check_layering.dart` points at rule 1 and ADR-0001.

The `findBannedTypes` dartdoc must state the accepted trade-off honestly, mirroring how `check_layering.dart` documents its own: this guard has no notion of string literals, so the word `DateTime` inside a string or a dartdoc code fence is reported. That is a **fail-closed** false positive — it breaks the build, a human looks, and nothing slips through — which is the correct bias for a guard, and the reason the blunt form was chosen over a narrower type-position match that would fail open.

- [ ] **Step 6: Run the guard tests to verify they pass**

```powershell
flutter test test/tool/check_domain_types_test.dart
```

Expected: PASS, all 11 tests.

- [ ] **Step 7: Write the failing `UtcInstant` / `WallClock` tests**

Create `test/domain/model/utc_instant_test.dart`. The DST group is the load-bearing one:

```dart
import 'package:flutter_test/flutter_test.dart';

import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:easa_digital_log/domain/model/wall_clock.dart';

void main() {
  group('UtcInstant construction', () {
    test('rejects a local DateTime', () {
      expect(
        () => UtcInstant.fromDateTime(DateTime(2026, 3, 14, 9, 5)),
        throwsArgumentError,
      );
    });

    test('accepts a UTC DateTime', () {
      final instant = UtcInstant.fromDateTime(DateTime.utc(2026, 3, 14, 9, 5));
      expect(instant.toIso8601String(), '2026-03-14T09:05:00.000Z');
    });

    test('rejects an ISO string with no zone designator', () {
      // DateTime.parse returns a LOCAL DateTime for this string, silently.
      // That silence is the entire reason this type exists.
      expect(
        () => UtcInstant.parse('2026-03-14T09:05:00'),
        throwsFormatException,
      );
      expect(UtcInstant.tryParse('2026-03-14T09:05:00'), isNull);
    });

    test('accepts Z and normalises an explicit offset', () {
      expect(
        UtcInstant.parse('2026-03-14T09:05:00Z').toIso8601String(),
        '2026-03-14T09:05:00.000Z',
      );
      expect(
        UtcInstant.parse('2026-03-14T10:05:00+01:00').toIso8601String(),
        '2026-03-14T09:05:00.000Z',
      );
      expect(
        UtcInstant.parse('2026-03-14T04:05:00-05:00').toIso8601String(),
        '2026-03-14T09:05:00.000Z',
      );
    });

    test('always serialises with an explicit Z', () {
      // ADR-0002: never a bare offset-less string that could be read as local.
      final instant = UtcInstant.utc(2026, 3, 14, 9, 5);
      expect(instant.toIso8601String(), endsWith('Z'));
      expect(instant.asUtcDateTime.isUtc, isTrue);
    });

    test('round-trips through parse and format', () {
      const source = '2026-10-25T01:30:00.000Z';
      expect(UtcInstant.parse(source).toIso8601String(), source);
    });
  });

  group('UtcInstant ordering', () {
    test('orders, compares and de-duplicates by instant', () {
      final a = UtcInstant.utc(2026, 3, 14, 9, 5);
      final b = UtcInstant.utc(2026, 3, 14, 9, 5);
      final c = UtcInstant.utc(2026, 3, 14, 10, 42);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(<UtcInstant>{a, b, c}, hasLength(2));
      expect(a < c, isTrue);
      expect(c > a, isTrue);
      expect(a <= b, isTrue);
      expect(<UtcInstant>[c, a].toList()..sort(), <UtcInstant>[a, c]);
      expect(c.difference(a), const Duration(hours: 1, minutes: 37));
      expect(a.add(const Duration(hours: 1, minutes: 37)), c);
      expect(c.subtract(const Duration(hours: 1, minutes: 37)), a);
    });
  });

  group('WallClock rendering across DST transitions', () {
    // Europe/London 2026: BST begins 2026-03-29T01:00Z, ends 2026-10-25T01:00Z.

    test('renders either side of the spring-forward gap', () {
      expect(
        UtcInstant.parse('2026-03-29T00:59:00Z').toWallClock(Duration.zero),
        const WallClock(
          year: 2026, month: 3, day: 29,
          hour: 0, minute: 59, second: 0,
          offset: Duration.zero,
        ),
      );

      // 01:00 GMT is 02:00 BST — the hour 01:00-02:00 local never happens.
      expect(
        UtcInstant.parse('2026-03-29T01:00:00Z')
            .toWallClock(const Duration(hours: 1))
            .hour,
        2,
      );
    });

    test('the autumn ambiguous hour is one wall clock over two instants', () {
      // THE test. 01:30 local happens twice on 2026-10-25: once as BST and
      // once, an hour later, as GMT. Two different instants, one wall clock.
      // Storing the wall clock would make these indistinguishable; storing
      // UTC keeps them apart. This is what fails if anyone "simplifies"
      // UtcInstant back to a bare DateTime.
      final bst = UtcInstant.parse('2026-10-25T00:30:00Z')
          .toWallClock(const Duration(hours: 1));
      final gmt = UtcInstant.parse('2026-10-25T01:30:00Z')
          .toWallClock(Duration.zero);

      expect(bst.hour, 1);
      expect(bst.minute, 30);
      expect(gmt.hour, 1);
      expect(gmt.minute, 30);

      expect(bst.offset, const Duration(hours: 1));
      expect(gmt.offset, Duration.zero);
      expect(bst, isNot(gmt));

      expect(
        UtcInstant.parse('2026-10-25T00:30:00Z'),
        isNot(UtcInstant.parse('2026-10-25T01:30:00Z')),
      );
    });

    test('renders a western offset', () {
      // America/New_York 2026: EDT begins 2026-03-08T07:00Z (-5 -> -4).
      final before = UtcInstant.parse('2026-03-08T06:59:00Z')
          .toWallClock(const Duration(hours: -5));
      final after = UtcInstant.parse('2026-03-08T07:00:00Z')
          .toWallClock(const Duration(hours: -4));

      expect(before.hour, 1);
      expect(before.minute, 59);
      expect(after.hour, 3);
      expect(after.minute, 0);
    });

    test('renders a half-hour offset', () {
      final india = UtcInstant.parse('2026-03-14T09:05:00Z')
          .toWallClock(const Duration(hours: 5, minutes: 30));

      expect(india.hour, 14);
      expect(india.minute, 35);
      expect(india.toString(), '2026-03-14 14:35 +05:30');
    });

    test('crosses the date boundary when the offset shifts the day', () {
      final auckland = UtcInstant.parse('2026-03-14T23:30:00Z')
          .toWallClock(const Duration(hours: 13));

      expect(auckland.year, 2026);
      expect(auckland.month, 3);
      expect(auckland.day, 15);
      expect(auckland.hour, 12);
      expect(auckland.toString(), '2026-03-15 12:30 +13:00');
    });

    test('formats negative offsets correctly', () {
      final honolulu = UtcInstant.parse('2026-03-14T09:05:00Z')
          .toWallClock(const Duration(hours: -10, minutes: -30));

      expect(honolulu.toString(), '2026-03-13 22:35 -10:30');
    });
  });
}
```

- [ ] **Step 8: Run the tests to verify they fail**

```powershell
flutter test test/domain/model/utc_instant_test.dart
```

Expected: FAIL — targets of both URIs do not exist.

- [ ] **Step 9: Implement `WallClock`**

Create `lib/domain/model/wall_clock.dart`: a `const`-constructible immutable value with named required `year`, `month`, `day`, `hour`, `minute`, `second`, `offset`, plus `==`, `hashCode` and `toString()` rendering `'2026-03-29 02:30 +01:00'` — date, space, `HH:MM`, space, signed `±HH:MM` offset. Zero-pad every component; a zero offset renders `+00:00`.

Its dartdoc must say what it is *not*: a `WallClock` is a rendered calendar reading at a stated offset, not an instant. It cannot be persisted, cannot be compared across offsets, and has no meaning without the offset it carries. This is why `toWallClock` does not return a `DateTime`.

- [ ] **Step 10: Implement `UtcInstant`**

Create `lib/domain/model/utc_instant.dart`:

```dart
class UtcInstant implements Comparable<UtcInstant> {
  const UtcInstant._(this._value);

  factory UtcInstant.fromDateTime(DateTime value);   // ArgumentError if !value.isUtc
  factory UtcInstant.utc(int year, [int month = 1, int day = 1,
      int hour = 0, int minute = 0, int second = 0, int millisecond = 0]);
  factory UtcInstant.parse(String source);           // FormatException if no zone
  static UtcInstant? tryParse(String source);

  final DateTime _value;

  DateTime get asUtcDateTime;      // always isUtc == true
  int get millisecondsSinceEpoch;
  String toIso8601String();        // always ends 'Z' (ADR-0002)
  WallClock toWallClock(Duration offset);

  UtcInstant add(Duration d);
  UtcInstant subtract(Duration d);
  Duration difference(UtcInstant other);
  bool operator <(UtcInstant other);    // and <=, >, >=
  @override int compareTo(UtcInstant other);
}
```

- `parse` must reject any string `DateTime.parse` resolves to a non-UTC value — i.e. one with no `Z` and no numeric offset — with a `FormatException` naming the source. An explicit offset is accepted and normalised, because `DateTime.parse` converts it losslessly and vendor CSV import will need it; output is always `Z`.
- `tryParse` returns `null` where `parse` would throw. It must not swallow programming errors — catch only `FormatException`.
- `toWallClock(offset)` computes the shifted calendar fields and returns a `WallClock` carrying `offset`.

The class dartdoc must state:

- every persisted instant is UTC, citing CLAUDE.md rule 3, ADR-0002 and `AMC1 FCL.050`;
- the `DateTime.parse` trap, in one sentence, because it is the specific thing this type defends against;
- that `asUtcDateTime` is an escape hatch for interop and its result must never be `.toLocal()`ed inside `lib/domain/`;
- **the M4 boundary:** `toWallClock` takes an offset the *caller* supplies. Choosing which offset applies to a named zone requires the IANA timezone database and belongs to the UI layer in M4 — it is deliberately not in `lib/domain/`, and no `timezone` dependency is added now.

- [ ] **Step 11: Run the tests to verify they pass**

```powershell
flutter test test/domain/model/utc_instant_test.dart
```

Expected: PASS, all 12 tests.

- [ ] **Step 12: Wire the guard into CI**

In `.github/workflows/ci.yaml`, add a step immediately after `Check domain layering`, matching the existing steps' style:

```yaml
      - name: Check domain types
        run: dart run tool/check_domain_types.dart
```

- [ ] **Step 13: Append the implementation record to ADR-0002**

Append a `**Record here, from #15:**` block to the *Consequences* section of `docs/adr/0002-utc-only.md` — the same pattern ADR-0006 already uses for a Task 1 finding. Do **not** edit the Decision. The block records: the `WallClock` return type and why `toWallClock` does not return a `DateTime`; the explicit-offset boundary and the M4 deferral of zone-aware conversion with no `timezone` dependency; and the new `tool/check_domain_types.dart` guard with its allowlist.

- [ ] **Step 14: Run the full local pipeline**

```powershell
flutter pub get
dart format --set-exit-if-changed .
dart run build_runner build --delete-conflicting-outputs
flutter analyze --fatal-infos
dart run tool/check_layering.dart
dart run tool/check_domain_types.dart
flutter test
```

All seven clean. The new guard must pass against the real `lib/domain/` — which now contains `flight_duration.dart` from Task 1 and the two new files. If it reports a violation in `flight_duration.dart`, that is a real finding, not a guard bug.

- [ ] **Step 15: Commit**

```powershell
git add lib/domain/model/utc_instant.dart lib/domain/model/wall_clock.dart tool/dart_source.dart tool/check_domain_types.dart tool/check_layering.dart test/domain/model/utc_instant_test.dart test/tool/check_domain_types_test.dart .github/workflows/ci.yaml docs/adr/0002-utc-only.md
git commit -m "feat: add a UTC-only instant type and ban raw DateTime in domain (#15)"
```

The commit body must cite `AMC1 FCL.050` (times recorded in UTC) and note the M4 deferral of zone-aware local conversion.

---

## Task 3: PilotCapacity (issue #13)

**Files:**
- Create: `lib/domain/model/pilot_capacity.dart`
- Create: `lib/domain/model/instructor_presence.dart`
- Create: `lib/domain/model/countersignature.dart`
- Create: `test/fixtures/capacities/` — 12 YAML files, named below
- Create: `test/fixtures/decoders/pilot_capacity_fixture.dart`
- Create: `test/domain/model/capacity_scenarios.dart`
- Create: `test/domain/model/pilot_capacity_test.dart`
- Create: `docs/adr/0008-capacity-as-composed-facts.md`
- Modify: `test/fixtures/README.md` (add the `capacities/` subdirectory row)
- Modify: `docs/adr/README.md` (add the ADR-0008 index row)

**Interfaces:**
- Consumes: `FlightDuration` from Task 1 (`package:easa_digital_log/domain/model/flight_duration.dart`); `UtcInstant` from Task 2 (`package:easa_digital_log/domain/model/utc_instant.dart`).
- Produces: `PilotCapacity`, `InstructorPresence`, `Countersignature`, and the enums `OtherPilotRole`, `InstructorCapacity`, `CountersignatureStatus`. Issue #11 embeds `PilotCapacity` in `Flight`; issues #18 and #19 consume `capacityScenarios` from `test/domain/model/capacity_scenarios.dart`.

### The decision this task implements — read before writing code

Issue #13 asks for a flat `enum` whose values include `spic`, `picus` and `soleManipulatorReceivingInstruction`. **That shape was rejected by the project owner and must not be built.** The reasons:

- SPIC and PICUS are EASA *conclusions*, not raw facts. PICUS-ness depends on whether the PIC's intervention was required **and** on whether a countersignature has arrived — so it changes after the flight. Storing it violates CLAUDE.md rule 1.
- "Sole manipulator while receiving instruction" is not a peer of "PIC". It is the *combination* `soleManipulator && instructor != null`, and it is exactly the canonical FAA/EASA divergence case.
- `test/fixtures/flights/faa_easa_divergence.yaml` and `docs/entry-form.md` §4 already model capacity as independent discriminators. `docs/entry-form.md` §4C states the principle: *"Capture the arrangement rather than the conclusion."*

Read `docs/jurisdiction-matrix.md` §4 and §9 and `docs/entry-form.md` §4 before writing the model. §9 is the authoritative list of discriminators without which a jurisdiction's numbers are unrecoverable.

- [ ] **Step 1: Write the model**

Create the three files. freezed 3.x form is mandatory (`@freezed abstract class X with _$X`).

`lib/domain/model/pilot_capacity.dart`:

```dart
@freezed
abstract class PilotCapacity with _$PilotCapacity {
  const factory PilotCapacity({
    /// Command authority held for the flight. EASA FCL.010 PIC turns on this
    /// and on nothing else; FAA acting PIC under §91.3 is the same concept.
    /// Deliberately independent of [soleManipulator]: under the FAA both
    /// pilots can log PIC simultaneously, which is impossible under EASA.
    required bool commandAuthority,

    /// Sole manipulator of the controls. FAA §61.51(e)(1)(i) PIC turns on
    /// this; EASA has no general sole-manipulator concept.
    required bool soleManipulator,

    /// Sole occupant of the aircraft. FAA §61.51(d) solo and §61.51(e)(4)
    /// student PIC both require it.
    required bool soleOccupant,

    /// Multi-pilot operation. EASA AMC1 FCL.050 columns 5 and 6 split
    /// single-pilot from multi-pilot time; FAA SIC under §61.51(f) requires
    /// an aircraft requiring more than one pilot.
    required bool multiPilotOperation,

    /// The pilot was acting as the authorised flight instructor. EASA logs
    /// instructor time and PIC together; FAA §61.51(e)(3) lets a CFI log PIC
    /// for instruction given when rated to act as PIC of that aircraft.
    required bool actingAsInstructor,

    /// The pilot was acting as examiner. Drives the mandatory AMC1 FCL.050
    /// column 13 remarks for skill tests and proficiency checks.
    required bool actingAsExaminer,

    /// The pilot claimed PICUS for this flight. EASA FCL.010 — an assertion
    /// the pilot makes, and therefore a raw fact. Whether the claim is
    /// *creditable* is a projection output and depends on
    /// [picInterventionNotRequired] and on [countersignature].
    required bool picusClaimed,

    /// The substantive PICUS condition: the PIC's intervention in the
    /// interest of safety was not required (EASA FCL.010).
    required bool picInterventionNotRequired,

    /// Time spent manipulating the controls where that was less than the
    /// whole flight. Null means "the whole flight" — see docs/entry-form.md
    /// §4C. This is what makes a mid-flight takeover loggable under FAA
    /// §61.51(e)(1)(i).
    FlightDuration? manipulationTime,

    /// Null when no instructor was aboard.
    InstructorPresence? instructor,

    /// Null when no other pilot was aboard.
    OtherPilotRole? otherPilotRole,

    /// Null when no countersignature is required or expected.
    Countersignature? countersignature,
  }) = _PilotCapacity;
}

/// The role of another pilot aboard, where that pilot was not an instructor.
enum OtherPilotRole {
  /// Required crew: a crewmember station occupied under the type certificate
  /// or under the operating rules. EASA co-pilot time; FAA SIC §61.51(f).
  requiredCrew,

  /// Aboard but not required. Under EASA this pilot logs nothing, even in
  /// command — see docs/jurisdiction-matrix.md §4.
  notRequiredCrew,

  /// FAA safety pilot for another pilot's simulated instrument flight.
  /// Required crew under §91.109; the name must be recorded per
  /// §61.51(b)(1)(v). EASA has no equivalent category.
  safetyPilot,
}
```

`lib/domain/model/instructor_presence.dart` — `InstructorPresence` with:

- `required InstructorCapacity capacity`
- `required bool influencedFlight` — the EASA SPIC discriminator. FCL.010 requires that the instructor *only observed* and did not influence or control the flight. `true` makes the flight dual, not SPIC.
- `String? name`
- `String? credentialNumber` — required for EASA countersignature and FAA endorsements
- `UtcInstant? credentialExpiry` — FAA §61.51(h)(2)(ii)

and `enum InstructorCapacity { flightInstructor, flightExaminer }`.

`lib/domain/model/countersignature.dart` — `Countersignature` with `required CountersignatureStatus status`, `String? signatoryName`, `String? signatoryCredentialNumber`, `UtcInstant? signatoryCredentialExpiry`, `UtcInstant? signedAt`; and `enum CountersignatureStatus { notRequired, pending, signed, refused }`.

The `Countersignature` dartdoc must note that CLAUDE.md places countersignature *workflow* out of scope while requiring the *data* now, and that uncountersigned PICUS time is not creditable as PIC under AMC1 FCL.050 — the projection must return it as *not creditable, with a reason*, never silently as zero and never silently as valid.

**Every field carries a doc comment naming the rule that defines it.** That is an explicit acceptance criterion of #13 and is not optional.

### Two calls to make explicitly, not silently

**Safety pilot is an `OtherPilotRole`, not an `InstructorCapacity`.** CLAUDE.md rule 2's parenthetical reads *"instructor aboard, and in what capacity (FI/FE/safety pilot)"*, but a safety pilot is required crew under §91.109, not an instructor, and `docs/entry-form.md` §4C models them under "with another pilot". State this divergence from CLAUDE.md and its reason explicitly in ADR-0008. Do not quietly differ.

**Deliberately out of scope, with pointers in the dartdoc:** `carryingPassengers` is a flight-level fact (#11). `aircraftRequiresMultiCrew` is an aircraft attribute (#12) — `multiPilotOperation` stays here because `docs/entry-form.md` §4C makes it overridable for operations requiring two pilots by regulation rather than by type certificate. `credentialExpiry` and `signatoryCredentialExpiry` are calendar dates modelled as `UtcInstant` for now; a proper calendar-date type is #29's territory.

- [ ] **Step 2: Generate and verify the model compiles**

```powershell
dart run build_runner build --delete-conflicting-outputs
flutter analyze --fatal-infos
dart run tool/check_layering.dart
dart run tool/check_domain_types.dart
```

All four clean. If `check_domain_types` flags the new files, use `UtcInstant`, not `DateTime` — the guard is right.

- [ ] **Step 3: Write the twelve scenario fixtures**

Create `test/fixtures/capacities/`, one YAML file per scenario. Follow `test/fixtures/flights/faa_easa_divergence.yaml` **exactly** as the precedent: raw facts as keys, expected projection outcomes in a header comment marked "NOT stored here", regulatory citations as comments next to the values they justify, everything time-shaped or aerodrome-shaped quoted.

| File | Scenario |
|---|---|
| `pic_sole_occupant.yaml` | Solo. Command, sole manipulator, sole occupant. EASA PIC = block; FAA PIC and solo = block. |
| `pic_with_passengers.yaml` | Command, sole manipulator, not sole occupant. Feeds FCL.060(b)(1) and §61.57(a). |
| `sole_manipulator_receiving_instruction.yaml` | **The canonical divergence.** Rated PPL, no command authority, sole manipulator, FI aboard influencing the flight. FAA PIC = block; EASA PIC = 0, dual = block. Must match the discriminators in `test/fixtures/flights/faa_easa_divergence.yaml`. |
| `dual_received_not_manipulating.yaml` | Instructor flying. Dual under both; no FAA PIC. |
| `spic.yaml` | Student holding command authority, FI aboard **not** influencing the flight, countersignature pending. EASA SPIC; FAA has no analogue. |
| `picus_countersigned.yaml` | Multi-pilot, command with the other pilot, PICUS claimed, intervention not required, countersignature `signed`. Creditable toward ATPL(A) under FCL.510(a)(2). |
| `picus_pending.yaml` | Identical to the above but countersignature `pending`. Not creditable — the projection must say so with a reason. |
| `co_pilot_sic.yaml` | Multi-pilot, no command, no PICUS claim. EASA co-pilot; FAA SIC §61.51(f). |
| `flight_instructor.yaml` | Acting as FI, holding command. EASA instructor + PIC; FAA §61.51(e)(3). |
| `examiner.yaml` | Acting as examiner, holding command. Forces AMC1 FCL.050 column 13 remarks. |
| `safety_pilot.yaml` | FAA safety pilot for another pilot's simulated instrument flight, §91.109. Other pilot aboard, `otherPilotRole: safety_pilot` applied to the *other* pilot's arrangement per `docs/entry-form.md` §4C. |
| `second_pilot_single_pilot_aircraft.yaml` | Single-pilot aeroplane, other pilot in command, this pilot not flying, not required crew. **EASA logs nothing at all**; the FAA licence may permit logging. The counterintuitive case from `docs/entry-form.md` §4C. |

Add a `capacities/` row to the subdirectory list in `test/fixtures/README.md`, matching the existing entries' style.

- [ ] **Step 4: Write the fixture decoder**

Create `test/fixtures/decoders/pilot_capacity_fixture.dart`, exposing `PilotCapacity pilotCapacityFromFixture(YamlMap yaml)` built on the existing `loadFixture` in `test/fixtures/fixture_loader.dart`. It lives in `test/`, not `lib/domain/`, because YAML fixture shape is a test concern — the fixture README already says M1 adds typed per-model decoders on top of the loader.

Snake-case YAML keys map to camelCase fields. A missing required key must throw with a message naming the key and the fixture, not produce a silent default — a silently defaulted discriminator is exactly the failure mode rule 2 exists to prevent.

- [ ] **Step 5: Write the scenario table**

Create `test/domain/model/capacity_scenarios.dart`, exporting a named table that issues #18 and #19 will consume rather than reinventing:

```dart
/// One capacity scenario: the raw facts, plus what each jurisdiction is
/// expected to make of them.
///
/// The expectations are prose for now — the projections that turn them into
/// assertions are issues #18 (EASA) and #19 (FAA). Those issues consume this
/// table; do not fork it.
class CapacityScenario {
  const CapacityScenario({
    required this.name,
    required this.capacity,
    required this.expectedEasa,
    required this.expectedFaa,
  });

  final String name;
  final PilotCapacity capacity;
  final String expectedEasa;
  final String expectedFaa;
}

List<CapacityScenario> loadCapacityScenarios();
```

- [ ] **Step 6: Write the tests**

Create `test/domain/model/pilot_capacity_test.dart`.

Projections do not exist yet, so this task cannot assert PIC values. It asserts what it can, and the second test below is genuinely load-bearing — it is the closest thing to a projection test available before projections exist, and it is mutation-resistant in the way that matters:

```dart
test('every scenario fixture decodes', () {
  final scenarios = loadCapacityScenarios();
  expect(scenarios, hasLength(12));
  for (final scenario in scenarios) {
    expect(scenario.expectedEasa, isNotEmpty, reason: scenario.name);
    expect(scenario.expectedFaa, isNotEmpty, reason: scenario.name);
  }
});

test('no two scenarios are indistinguishable', () {
  // Delete any discriminator from PilotCapacity and two scenarios collide,
  // turning this red. That is the point: it proves the model actually
  // captures every case issue #13 requires it to distinguish, without
  // needing the projections that will interpret them.
  final scenarios = loadCapacityScenarios();
  final capacities = scenarios.map((s) => s.capacity).toSet();

  expect(
    capacities,
    hasLength(scenarios.length),
    reason: 'two scenarios produced an equal PilotCapacity',
  );
});
```

Plus: the canonical divergence scenario decodes to `commandAuthority: false`, `soleManipulator: true`, an `instructor` with `influencedFlight: true`; `spic` decodes to `commandAuthority: true` with `influencedFlight: false`; `picus_pending` and `picus_countersigned` differ **only** in `countersignature.status`; the decoder throws a named error on a missing required key.

- [ ] **Step 7: Run the tests**

```powershell
flutter test test/domain/model/pilot_capacity_test.dart
```

Expected: PASS. Before moving on, confirm the "no two scenarios" test can fail: temporarily drop one discriminator from two colliding scenario fixtures, watch it go red, restore. Record this in your report.

- [ ] **Step 8: Write ADR-0008**

Create `docs/adr/0008-capacity-as-composed-facts.md`, matching the existing ADRs' structure and tone. It records:

- the decision: capacity is a composition of independent raw discriminators;
- under *Alternatives considered*, the flat enum that issue #13's own text asks for, and why it was rejected — SPIC and PICUS are EASA conclusions that change when a countersignature arrives, so storing one violates rule 1 and makes an FAA reading of a historic flight unrecoverable;
- the safety-pilot placement and its divergence from CLAUDE.md rule 2's parenthetical;
- under *Consequences*, that #18 and #19 must derive SPIC/PICUS/dual rather than reading a stored value, and that the `capacityScenarios` table is the shared input they consume.

Add the index row to `docs/adr/README.md`.

- [ ] **Step 9: Run the full local pipeline**

```powershell
flutter pub get
dart format --set-exit-if-changed .
dart run build_runner build --delete-conflicting-outputs
flutter analyze --fatal-infos
dart run tool/check_layering.dart
dart run tool/check_domain_types.dart
flutter test
```

All seven clean, whole suite.

- [ ] **Step 10: Commit**

```powershell
git add lib/domain/model/ test/fixtures/ test/domain/model/ docs/adr/
git commit -m "feat: model pilot operating capacity as composed raw facts (#13)"
```

The commit body must cite `FCL.010` (PIC, SPIC, PICUS definitions), `§61.51(e)(1)(i)` (sole manipulator), `§91.109` (safety pilot) and `AMC1 FCL.050` (countersignature), and must state that the flat enum in the issue text was rejected under rule 1, pointing at ADR-0008.

---

## Verification

After all three tasks, from the repository root under PowerShell:

```powershell
flutter pub get
dart format --set-exit-if-changed .
dart run build_runner build --delete-conflicting-outputs
flutter analyze --fatal-infos
dart run tool/check_layering.dart
dart run tool/check_domain_types.dart
flutter test
```

**Done when:**

- the 10,000-flight sum test passes and demonstrates the 166.7-hour rounded-first error;
- the two 2026-10-25 instants render the same wall clock at different offsets and remain unequal;
- every guard test was seen red before green, and the report says which and how;
- all twelve capacity scenarios decode and none collide;
- ADR-0007 and ADR-0008 exist and `docs/adr/README.md` indexes them;
- CI's `verify` check is green on the PR.

One PR closing all three issues, with **one `Closes #N` per line** — `Closes #16, #15, #13` on a single line binds only the first, which cost a rewrite on PR #97.
