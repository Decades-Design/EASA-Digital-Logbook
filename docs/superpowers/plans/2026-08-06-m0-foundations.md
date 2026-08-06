# M0 Foundations & Tooling Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make this project's architectural rules mechanically enforced — dependencies wired, `lib/domain/` purity checked by a tested script, CI green on every PR, decisions recorded as ADRs, and a fixture harness in place — so that no domain code is ever written without a guard behind it.

**Architecture:** Five independent deliverables landing as one commit each on a single branch. A plain Dart script (`tool/check_layering.dart`) enforces the layering rule rather than a lint plugin, because it needs no dependency and is fast enough to reuse in a pre-commit hook later. Code generation output is gitignored and regenerated in CI, which dictates both the analyzer exclusion list and the CI step order.

**Tech Stack:** Flutter 3.44.0, Dart 3.12.0, `freezed` 3.2.5, `json_serializable` 6.14.1, `build_runner` 2.15.1, `yaml` 3.1.3, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-08-06-m0-foundations-design.md`
**Issues closed:** #3, #4, #5, #6, #8
**Branch:** `chore/m0-foundations` (already created; the spec commit `e1c5198` is on it)

## Global Constraints

- **Run all `flutter` and `dart` commands through PowerShell, not Git Bash.** This machine uses puro (`C:\Users\giaco\.puro\bin\puro.bat`), and the Git Bash shim is broken — `flutter --version` fails there with "No such file or directory". Every command in this plan assumes PowerShell.
- Dart SDK constraint stays `^3.12.0`. Do not raise or lower it.
- `lib/domain/` must never import `package:flutter/*`, `dart:io`, or `dart:ui`. This is the rule Task 2 exists to enforce.
- All persisted times are UTC. No naive `DateTime` in any model. (Not exercised in M0, but do not introduce a counterexample.)
- Conventional commits: `feat:`, `fix:`, `refactor:`, `chore:`, `docs:`, `test:`, `ci:`.
- Never store a derived quantity. No fixture added in Task 5 may contain a `picTime`, `nightTime`, `totalTime`, or similar field.
- `dart format .`, `flutter analyze` and `flutter test` must all be clean before any commit.
- Do not add a dependency beyond the six named in Task 1. Anything else needs its own discussion per `CLAUDE.md`.

---

## File Structure

| Path | Status | Responsibility |
|---|---|---|
| `pubspec.yaml` | Modify | Dependency declarations and pin rationale |
| `.gitignore` | Modify | Exclude generated codegen output |
| `analysis_options.yaml` | Modify | Strict lints, strict language modes, generated-file exclusions |
| `tool/check_layering.dart` | Create | Layering guard: script entrypoint plus the pure `findViolations` function it is tested through |
| `test/tool/check_layering_test.dart` | Create | Proves the guard catches real violations and passes clean files |
| `.github/workflows/ci.yaml` | Create | Format, codegen, analyze, layering, test on push and PR |
| `docs/adr/template.md` | Create | ADR template |
| `docs/adr/README.md` | Create | ADR index |
| `docs/adr/0001..0006-*.md` | Create | The six foundational decision records |
| `CLAUDE.md` | Modify | Link to the ADR index (rule 4 rewrite already present, currently uncommitted) |
| `docs/entry-form.md`, `docs/jurisdiction-matrix.md` | Commit | Currently untracked; the matrix is the M1 spec |
| `test/fixtures/fixture_loader.dart` | Create | Single typed entry point for reading fixtures |
| `test/fixtures/README.md` | Create | What each fixture set is for, provenance, YAML quoting caveat |
| `test/fixtures/flights/faa_easa_divergence.yaml` | Create | The canonical divergence case from the jurisdiction matrix §4 |
| `test/fixtures/fixture_loader_test.dart` | Create | Proves the loader reads a fixture and fails clearly on a missing one |

`tool/check_layering.dart` deliberately holds both `main()` and `findViolations()`. Splitting a 60-line script across two files to satisfy a layering purist would cost more than it buys, and `findViolations` is directly importable from the test by relative path.

---

## Task 1: Dependency wiring and codegen policy (#3)

**Files:**
- Modify: `pubspec.yaml`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: nothing
- Produces: `package:yaml/yaml.dart` available to Task 5; `freezed`/`build_runner` available to CI in Task 3. No Dart symbols.

- [ ] **Step 1: Add the six dependencies with exact constraints**

Run in PowerShell:

```powershell
flutter pub add 'freezed_annotation:^3.1.0' 'json_annotation:^4.12.0' 'yaml:^3.1.3' 'dev:build_runner:^2.15.1' 'dev:freezed:^3.2.5' 'dev:json_serializable:^6.14.1'
```

Expected: resolves with `analyzer 10.2.0` and `source_gen 4.2.4`. If version solving fails, do not relax the `freezed` constraint — see Step 2.

- [ ] **Step 2: Add the pin rationale comment to `pubspec.yaml`**

`freezed` must be `^3.2.5`, not `^3.0.0`. This is the non-obvious choice issue #3 asks to be documented. Add above the `dev_dependencies` entry:

```yaml
dev_dependencies:
  # freezed is pinned to ^3.2.5 deliberately, NOT ^3.0.0.
  # freezed 3.0.0-3.2.4 depend on build ^3 / source_gen ^3 / analyzer ^8.
  # build_runner >=2.15.1 needs build ^4, and json_serializable >=6.13.1
  # needs source_gen ^4.1.2 / analyzer >=10. A ^3.0.0 constraint resolves
  # to 3.0.0 and then fails to co-resolve with either of them.
  # 3.2.5 is the first stable freezed on the build 4 / analyzer 10 stack.
  freezed: ^3.2.5
```

- [ ] **Step 3: Gitignore generated output**

Append to `.gitignore`:

```gitignore
# Code generation output (ADR-0006: regenerated in CI, never committed)
*.freezed.dart
*.g.dart
```

- [ ] **Step 4: Verify codegen runs clean**

```powershell
dart run build_runner build --delete-conflicting-outputs
```

Expected: exits 0. No files are generated — nothing is annotated yet. That is correct, not a failure.

- [ ] **Step 5: Verify the freezed 3.x syntax before M1 commits to it**

The spec flags this pin as load-bearing on issue #11. Prove the syntax now rather than discovering it there. Create a scratch file `lib/_codegen_smoke.dart`:

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part '_codegen_smoke.freezed.dart';

@freezed
abstract class SmokeTest with _$SmokeTest {
  const factory SmokeTest({required String value}) = _SmokeTest;
}
```

Note `abstract class`. In freezed 2.x this was `@freezed class X with _$X`; freezed 3.x requires the `abstract` (or `sealed`) modifier and errors without it.

- [ ] **Step 6: Run codegen and confirm the smoke model generates**

```powershell
dart run build_runner build --delete-conflicting-outputs
```

Expected: PASS, and `lib/_codegen_smoke.freezed.dart` now exists. Confirm it is untracked (`git status` must not list it) — that verifies Step 3.

- [ ] **Step 7: Delete the scratch file**

```powershell
Remove-Item lib\_codegen_smoke.dart, lib\_codegen_smoke.freezed.dart
```

Record the confirmed syntax form in ADR-0006 during Task 4. Do not leave the smoke model in the tree.

- [ ] **Step 8: Commit**

```powershell
git add pubspec.yaml pubspec.lock .gitignore
git commit -m "chore: add core dependencies and gitignore codegen output

Adds freezed, json_serializable, build_runner and yaml. Defers drift,
pdf, printing, csv and riverpod to the milestones that import them.

freezed pinned to ^3.2.5 rather than ^3.0.0 to stay on the build 4 /
analyzer 10 stack; see the rationale comment in pubspec.yaml.

Closes #3"
```

---

## Task 2: Strict analysis and the layering guard (#5)

**Files:**
- Modify: `analysis_options.yaml`
- Create: `tool/check_layering.dart`
- Test: `test/tool/check_layering_test.dart`

**Interfaces:**
- Consumes: nothing from Task 1
- Produces: `findViolations(String filePath, String source) -> List<Violation>` and `class Violation { final String filePath; final int line; final String uri; }`, both in `tool/check_layering.dart`. Task 3's CI invokes `dart run tool/check_layering.dart`.

- [ ] **Step 1: Write the failing test**

Create `test/tool/check_layering_test.dart`:

```dart
// flutter_test re-exports test/group/expect from package:test_api, so plain
// Dart tests need no separate package:test dependency.
import 'package:flutter_test/flutter_test.dart';

import '../../tool/check_layering.dart';

void main() {
  group('findViolations', () {
    test('flags a package:flutter import', () {
      const source = '''
import 'package:flutter/material.dart';

class Thing {}
''';
      final violations = findViolations('lib/domain/thing.dart', source);

      expect(violations, hasLength(1));
      expect(violations.single.uri, 'package:flutter/material.dart');
      expect(violations.single.line, 1);
    });

    test('flags an export as well as an import', () {
      const source = "export 'dart:io';\n";
      final violations = findViolations('lib/domain/thing.dart', source);

      expect(violations, hasLength(1));
      expect(violations.single.uri, 'dart:io');
    });

    test('allows a clean domain file', () {
      const source = '''
import 'dart:math';

import 'package:meta/meta.dart';

class Thing {}
''';
      expect(findViolations('lib/domain/thing.dart', source), isEmpty);
    });

    test('ignores a commented-out banned import', () {
      const source = '''
// import 'package:flutter/material.dart';
/* import 'dart:ui'; */

class Thing {}
''';
      expect(findViolations('lib/domain/thing.dart', source), isEmpty);
    });

    test('reports the correct line number for a later violation', () {
      const source = '''
import 'dart:math';

import 'dart:ui';
''';
      final violations = findViolations('lib/domain/thing.dart', source);

      expect(violations.single.line, 3);
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```powershell
flutter test test/tool/check_layering_test.dart
```

Expected: FAIL — `Error: Error when reading '../../tool/check_layering.dart': No such file or directory`. That is the expected pre-implementation failure.

Do NOT add `package:test`. `flutter_test` re-exports `test`, `group` and `expect` from `package:test_api`, and it is already a dev dependency. Adding a seventh package would violate this plan's Global Constraints.

- [ ] **Step 3: Write the implementation**

Create `tool/check_layering.dart`:

```dart
/// Enforces the layering rule from CLAUDE.md: `lib/domain/` is pure Dart and
/// must never reach for Flutter, the filesystem, or the rendering layer.
///
/// Run: `dart run tool/check_layering.dart [path]`
/// Exits 0 when clean or when the target directory does not exist yet.
library;

import 'dart:io';

/// Import/export URI prefixes that `lib/domain/` may not depend on.
///
/// Extend this list rather than adding special cases below.
const List<String> bannedPrefixes = <String>[
  'package:flutter/',
  'dart:io',
  'dart:ui',
];

const String defaultTarget = 'lib/domain';

/// A banned directive found in a domain file.
class Violation {
  const Violation({
    required this.filePath,
    required this.line,
    required this.uri,
  });

  final String filePath;
  final int line;
  final String uri;

  @override
  String toString() => '$filePath:$line  imports $uri';
}

final RegExp _blockComment = RegExp(r'/\*.*?\*/', dotAll: true);
final RegExp _directive = RegExp('''^\\s*(?:import|export)\\s+['"]([^'"]+)['"]''');

/// Returns every banned import or export in [source].
///
/// Block and line comments are stripped first, so a commented-out import is
/// not a violation. Both `import` and `export` are checked — a re-export
/// reintroduces the dependency just as effectively.
List<Violation> findViolations(String filePath, String source) {
  final withoutBlockComments = source.replaceAll(_blockComment, '');
  final lines = withoutBlockComments.split('\n');
  final violations = <Violation>[];

  for (var i = 0; i < lines.length; i++) {
    final line = lines[i];
    if (line.trimLeft().startsWith('//')) {
      continue;
    }

    final match = _directive.firstMatch(line);
    if (match == null) {
      continue;
    }

    final uri = match.group(1)!;
    final isBanned = bannedPrefixes.any(uri.startsWith);
    if (isBanned) {
      violations.add(
        Violation(filePath: filePath, line: i + 1, uri: uri),
      );
    }
  }

  return violations;
}

void main(List<String> args) {
  final target = args.isNotEmpty ? args.first : defaultTarget;
  final directory = Directory(target);

  if (!directory.existsSync()) {
    stdout.writeln('check_layering: $target does not exist yet — nothing to check.');
    exit(0);
  }

  final violations = <Violation>[];
  for (final entity in directory.listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.dart')) {
      violations.addAll(
        findViolations(entity.path, entity.readAsStringSync()),
      );
    }
  }

  if (violations.isEmpty) {
    stdout.writeln('check_layering: $target is clean.');
    exit(0);
  }

  stderr.writeln('check_layering: ${violations.length} layering violation(s):');
  for (final violation in violations) {
    stderr.writeln('  $violation');
  }
  stderr.writeln('');
  stderr.writeln('lib/domain/ must be pure Dart. See CLAUDE.md and ADR-0001.');
  exit(1);
}
```

Note the block-comment strip runs before splitting into lines, so a multi-line `/* ... */` spanning a banned import is handled. Line numbers after a multi-line block comment will shift; that is an accepted trade-off for a guard whose job is to fail the build, not to produce perfect diagnostics.

- [ ] **Step 4: Run the test to verify it passes**

```powershell
flutter test test/tool/check_layering_test.dart
```

Expected: PASS, 5 tests.

- [ ] **Step 5: Run the guard against the real tree**

```powershell
dart run tool/check_layering.dart
```

Expected: `check_layering: lib/domain does not exist yet — nothing to check.` and exit 0.

- [ ] **Step 6: Tighten `analysis_options.yaml`**

Replace the file entirely:

```yaml
include: package:flutter_lints/flutter.yaml

analyzer:
  # Generated code is not ours to lint. ADR-0006: it is gitignored and
  # regenerated in CI, so it must not gate `flutter analyze --fatal-infos`.
  exclude:
    - "**/*.freezed.dart"
    - "**/*.g.dart"
  language:
    strict-casts: true
    strict-inference: true
    strict-raw-types: true

linter:
  rules:
    - always_declare_return_types
    - prefer_final_locals
    - avoid_dynamic_calls
    - require_trailing_commas
```

- [ ] **Step 7: Verify analysis is clean at the new settings**

```powershell
dart format .
flutter analyze --fatal-infos
```

Expected: `No issues found!`

The scaffold `lib/main.dart` is expected to pass as written — it declares all return types, has no locals, no dynamic calls, and already carries trailing commas. If `--fatal-infos` does surface anything, fix it here; bringing the tree clean is part of this task, not a follow-up. Do not weaken the lint set to make it pass.

- [ ] **Step 8: Commit**

```powershell
git add analysis_options.yaml tool/check_layering.dart test/tool/check_layering_test.dart pubspec.yaml pubspec.lock
git commit -m "feat: enforce domain layering and enable strict analysis

Adds tool/check_layering.dart, which fails the build when lib/domain/
imports or exports package:flutter/, dart:io or dart:ui. The guard has
its own unit test — lib/domain/ is empty today, so an untested guard
would pass vacuously and rot undetected.

Enables strict-casts, strict-inference and strict-raw-types, and
excludes generated files from analysis.

Closes #5"
```

---

## Task 3: CI (#6)

**Files:**
- Create: `.github/workflows/ci.yaml`

**Interfaces:**
- Consumes: `dart run tool/check_layering.dart` from Task 2; the dependency set from Task 1
- Produces: nothing consumed by later tasks

- [ ] **Step 1: Write the workflow**

Create `.github/workflows/ci.yaml`:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  verify:
    # ubuntu is sufficient: analysis and unit tests need no iOS/Android toolchain.
    runs-on: ubuntu-latest
    timeout-minutes: 15

    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          # Pinned deliberately, not `stable`. A silent SDK bump breaking the
          # build is a bad way to lose an evening. Matches the local puro env.
          flutter-version: '3.44.0'
          channel: stable
          cache: true

      - name: Install dependencies
        run: flutter pub get

      # Format runs BEFORE codegen. Generated files are gitignored but present
      # on disk once build_runner has run, and `--set-exit-if-changed` would
      # then fail CI on output nobody controls.
      - name: Check formatting
        run: dart format --set-exit-if-changed .

      - name: Generate code
        run: dart run build_runner build --delete-conflicting-outputs

      - name: Analyze
        run: flutter analyze --fatal-infos

      - name: Check domain layering
        run: dart run tool/check_layering.dart

      - name: Test
        run: flutter test
```

- [ ] **Step 2: Commit**

```powershell
git add .github/workflows/ci.yaml
git commit -m "ci: run format, codegen, analyze, layering check and tests

Pins Flutter to 3.44.0 rather than tracking stable. Format runs before
codegen so the check never sees generated output.

Closes #6"
```

- [ ] **Step 3: Push and verify the run is green**

```powershell
git push -u origin chore/m0-foundations
gh run watch
```

Expected: all steps pass. If the `dart format` step fails, run `dart format .` locally and amend — do not add a format-skip flag.

---

## Task 4: ADRs and tracking the design docs (#4)

**Files:**
- Create: `docs/adr/template.md`, `docs/adr/README.md`, `docs/adr/0001-raw-facts-only.md` … `0006-dependency-stack.md`
- Modify: `CLAUDE.md` (add ADR index link)
- Commit: `docs/entry-form.md`, `docs/jurisdiction-matrix.md` (currently untracked)

**Interfaces:**
- Consumes: the confirmed `freezed` version and syntax form from Task 1 Step 7
- Produces: nothing consumed by later tasks

- [ ] **Step 1: Write the template**

Create `docs/adr/template.md`:

```markdown
# ADR-NNNN: <title>

**Status:** Proposed | Accepted | Superseded by ADR-NNNN
**Date:** YYYY-MM-DD

## Context

What forces are at play? What makes this decision necessary? Cite the specific
regulation where the decision turns on one (e.g. `AMC1 FCL.050(b)(1)`, `§61.57(c)`).

## Decision

What we are doing, stated in the active voice.

## Alternatives considered

What else was on the table, and why it was rejected. A decision with no
rejected alternative was not a decision.

## Consequences

What becomes easier. What becomes harder. What this forecloses.
```

- [ ] **Step 2: Write the six ADRs**

Each follows the template. Required content, so the record is not a restatement of the rule but the argument behind it:

**`0001-raw-facts-only.md`** — Status Accepted.
*Context:* jurisdictions disagree on what a given hour counts as; a derived value stored today cannot be recomputed under a licence added tomorrow. *Decision:* flight rows store raw facts; every derived quantity is computed per jurisdiction at read time. *Alternatives:* store EASA-derived columns and backfill later — rejected because command authority on a 2023 flight cannot be recalled retroactively. *Consequences:* every read path needs a projection; no `picTime` column ever; adding an authority never triggers a data migration.

**`0002-utc-only.md`** — Status Accepted.
*Context:* `AMC1 FCL.050` requires UTC; Dart's `DateTime.isUtc` is trivially lost and the failure is silent, producing wrong night time and wrong currency with no error. *Decision:* every persisted instant is UTC; local time exists only at the UI boundary. *Alternatives:* store local time with an offset — rejected as it makes every comparison offset-aware for no gain. *Consequences:* a wrapper type is needed (issue #15); serialisation is always ISO-8601 with explicit `Z`.

**`0003-draft-until-exported.md`** — Status Accepted. **This is the one with real reasoning; give it the most space.**
*Context:* EASA's May 2023 guidance on electronic records expects audit trails, authentication and correction tracking. But a logbook entry being typed is not yet a record of anything. *Decision:* an entry is freely mutable in place until it is first included in a generated PDF export; at that point it is committed, and every subsequent change appends a delta revision retaining the prior state. Committed entries are never `UPDATE`d or `DELETE`d. Revision history is device-local and backup-scoped, and is not part of any future sync payload. *Alternatives:* unconditional append-only from first keystroke — rejected because it produces a revision per typo, making the audit trail noise rather than evidence, and because export is the moment the record is asserted to an authority; before that there is nothing to be reliable about. *Consequences:* the schema needs a draft/committed state machine (M2); export is a state transition with side effects, not a read; the paper-logbook analogy argues *for* retaining history — a crossed-out ink entry remains legible — rather than against it.

**`0004-rules-as-data.md`** — Status Accepted.
*Context:* thresholds and windows differ per authority and change over time with effective-from dates. *Decision:* currency rules are versioned YAML under `assets/rules/`, evaluated by a generic engine; YAML references named, tested Dart primitives rather than expressing logic itself. *Alternatives:* rules as Dart classes — rejected against the stated acceptance test that adding Transport Canada should require a YAML profile and at most one new primitive. *Consequences:* the engine must report which flights satisfied each requirement, so results are explainable rather than a red or green pill.

**`0005-offline-first.md`** — Status Accepted.
*Context:* the data is a pilot's licensing record — personal data under GDPR, and the pilot's legal evidence of flight time. *Decision:* fully functional with no network; no cloud backend, no account system, no analytics. Sync, if ever added, is additive and never a dependency. *Alternatives:* cloud-first with offline cache — rejected because it makes a legal record dependent on a service that can be discontinued, and turns a personal file into a controller/processor relationship under GDPR. *Consequences:* backup/restore is the user's responsibility and must be first-class (M2); no telemetry means bug reports must carry the raw facts themselves (issue #9's bug template).

**`0006-dependency-stack.md`** — Status Accepted.
*Context:* `CLAUDE.md` requires asking before adding a dependency; issue #3 was that asking. *Decision:* the full stack is settled now — `freezed` + `json_serializable` for models, `drift` for persistence, `pdf` + `printing` for export, `csv` for import, `yaml` for rules, `riverpod` for UI state — but each package is added in the milestone that first imports it. Generated files (`*.freezed.dart`, `*.g.dart`) are gitignored and regenerated in CI. *Alternatives:* add all twelve now — rejected because `sqlite3_flutter_libs` and `printing` carry native components that would add build time and platform surface months before use. Commit generated files — rejected for diff noise and merge conflicts on code nobody reviews. *Consequences:* a fresh clone cannot analyze until `build_runner` has run; CI must generate before analysis; `analysis_options.yaml` must exclude generated files. **Record here:** `freezed` is pinned `^3.2.5` (first stable on the build 4 / analyzer 10 stack), and freezed 3.x requires models to be declared `@freezed abstract class X with _$X` — the bare `@freezed class X` form from 2.x is an error. Issue #11 depends on this.

- [ ] **Step 3: Write the index**

Create `docs/adr/README.md` with a table of the six ADRs — number, title, status, one-line summary — and a line stating that new ADRs are numbered sequentially and never renumbered, and that a reversed decision is superseded rather than edited.

- [ ] **Step 4: Link the index from `CLAUDE.md`**

Add immediately after the "Non-negotiable domain rules" heading paragraph:

```markdown
The reasoning behind each of these rules is recorded in [docs/adr/](docs/adr/README.md).
Rules 1–5 correspond to ADR-0001 through ADR-0005.
```

- [ ] **Step 5: Verify the tree is clean**

```powershell
dart format .
flutter analyze --fatal-infos
flutter test
```

Expected: all clean. (This task is docs-only, but the constraint is unconditional.)

- [ ] **Step 6: Commit**

Note this commit also picks up the uncommitted `CLAUDE.md` rule 4 rewrite and the two untracked design docs.

```powershell
git add docs/adr CLAUDE.md docs/entry-form.md docs/jurisdiction-matrix.md
git commit -m "docs: seed the ADR directory and track the design docs

Records the six foundational decisions, including ADR-0003 on entries
being mutable drafts until first exported. Also commits the CLAUDE.md
rule 4 rewrite and the jurisdiction matrix, which is effectively the
specification for M1 and should not live on one machine only.

Closes #4"
```

- [ ] **Step 7: Fix the stale rule reference in issue #15**

Issue #15 cites "CLAUDE.md rule 2" for the UTC requirement; UTC is rule 3. The numbering drifted when rule 4 was rewritten.

```powershell
gh issue edit 15 --repo Decades-Design/EASA-Digital-Logbook --body-file -
```

Paste the existing body with `rule 2` corrected to `rule 3`. Retrieve it first with `gh issue view 15 --json body --jq .body`.

---

## Task 5: Fixture harness (#8)

**Files:**
- Create: `test/fixtures/README.md`
- Create: `test/fixtures/fixture_loader.dart`
- Create: `test/fixtures/flights/faa_easa_divergence.yaml`
- Create: `test/fixtures/{aircraft,importers,pdf}/README.md`
- Test: `test/fixtures/fixture_loader_test.dart`

**Interfaces:**
- Consumes: `package:yaml/yaml.dart` from Task 1
- Produces: `loadFixture(String category, String name) -> YamlMap` and `FixtureNotFoundException`, in `test/fixtures/fixture_loader.dart`. M1 will add typed per-model decoders on top of this — it does not replace it.

- [ ] **Step 1: Write the failing test**

Create `test/fixtures/fixture_loader_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

import 'fixture_loader.dart';

void main() {
  group('loadFixture', () {
    test('loads the FAA/EASA divergence flight', () {
      final fixture = loadFixture('flights', 'faa_easa_divergence');

      expect(fixture, isA<YamlMap>());
      expect(fixture['sole_manipulator'], isTrue);
      expect(fixture['command_authority'], isFalse);
      expect(fixture['instructor_aboard'], isTrue);
    });

    test('stores no derived quantities', () {
      final fixture = loadFixture('flights', 'faa_easa_divergence');

      // CLAUDE.md rule 1: raw facts only. These are projection outputs.
      const forbidden = <String>[
        'pic_time',
        'dual_time',
        'night_time',
        'cross_country_time',
        'total_time',
      ];
      for (final key in forbidden) {
        expect(fixture.containsKey(key), isFalse, reason: '$key is derived');
      }
    });

    test('throws a clear error for a missing fixture', () {
      expect(
        () => loadFixture('flights', 'does_not_exist'),
        throwsA(
          isA<FixtureNotFoundException>().having(
            (e) => e.toString(),
            'message',
            allOf(contains('flights'), contains('does_not_exist')),
          ),
        ),
      );
    });
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

```powershell
flutter test test/fixtures/fixture_loader_test.dart
```

Expected: FAIL — `fixture_loader.dart` does not exist.

- [ ] **Step 3: Write the loader**

Create `test/fixtures/fixture_loader.dart`:

```dart
import 'dart:io';

import 'package:yaml/yaml.dart';

/// Thrown when a fixture file cannot be found, naming the category and fixture
/// so the failure is actionable without opening the loader.
class FixtureNotFoundException implements Exception {
  const FixtureNotFoundException(this.category, this.name, this.path);

  final String category;
  final String name;
  final String path;

  @override
  String toString() =>
      'FixtureNotFoundException: no fixture "$name" in category "$category" '
      '(looked for $path)';
}

const String _fixtureRoot = 'test/fixtures';

/// Loads the YAML fixture at `test/fixtures/<category>/<name>.yaml`.
///
/// Tests are run from the package root, so the path is resolved relative to
/// the current working directory.
YamlMap loadFixture(String category, String name) {
  final path = '$_fixtureRoot/$category/$name.yaml';
  final file = File(path);

  if (!file.existsSync()) {
    throw FixtureNotFoundException(category, name, path);
  }

  final parsed = loadYaml(file.readAsStringSync());
  if (parsed is! YamlMap) {
    throw StateError(
      'Fixture $path parsed as ${parsed.runtimeType}, expected a YAML map.',
    );
  }

  return parsed;
}
```

- [ ] **Step 4: Write the divergence fixture**

Create `test/fixtures/flights/faa_easa_divergence.yaml`. This is the canonical case from §4 of `docs/jurisdiction-matrix.md`, which requires that this exact flight exist in fixtures and produce different PIC time under each profile.

```yaml
# The canonical FAA/EASA divergence case.
# Rated private pilot, sole manipulator, instructor aboard giving instruction.
#
# Expected projections (asserted in M1, issues #18 and #19 — NOT stored here):
#   FAA  §61.51(e)(1)(i): PIC = full flight time, dual = full flight time
#   EASA FCL.010:         PIC = 0,                dual = full flight time
#
# Raw facts only. See CLAUDE.md rule 1 and ADR-0001.

id: "faa-easa-divergence-001"

# All instants UTC. See ADR-0002.
off_blocks: "2026-03-14T09:05:00Z"
takeoff: "2026-03-14T09:18:00Z"
landing: "2026-03-14T10:42:00Z"
on_blocks: "2026-03-14T10:51:00Z"

aircraft_registration: "G-ABCD"

# Quoted deliberately — see the YAML caveat in test/fixtures/README.md.
route:
  - "EGKA"
  - "EGHR"
  - "EGKA"

# The discriminators the divergence turns on.
command_authority: false      # EASA PIC requires this; the instructor held it
sole_manipulator: true        # FAA §61.51(e)(1)(i) PIC turns on this
sole_occupant: false
instructor_aboard: true
instructor_capacity: "FI"     # FI | FE | safety_pilot
instructor_influenced_flight: true   # so this is dual, not SPIC
multi_pilot_operation: false
aircraft_requires_multi_crew: false

landings:
  day_full_stop: 1
  day_touch_and_go: 3
  night_full_stop: 0
  night_touch_and_go: 0

ifr_flight_plan_filed: false
actual_instrument_minutes: 0
simulated_instrument_minutes: 0

remarks: "Dual instruction, circuits at EGHR. Student rated PPL(A) SEP."
```

- [ ] **Step 5: Run the test to verify it passes**

```powershell
flutter test test/fixtures/fixture_loader_test.dart
```

Expected: PASS, 3 tests.

- [ ] **Step 6: Write the fixtures README**

Create `test/fixtures/README.md` covering:
- What each subdirectory holds: `flights/` raw-fact flight entries, `aircraft/` aircraft definitions, `importers/` real vendor CSV samples, `pdf/` expected export output for golden tests.
- Provenance rule: where a fixture came from a real ForeFlight or Garmin export, say so, and confirm personal data was scrubbed.
- **The YAML quoting caveat:** quote aerodrome identifiers and anything time-shaped. Dart's `yaml` implements the YAML 1.2 core schema, so the 1.1 sexagesimal (`1:30`) and `yes`/`no`/`on`/`off` boolean traps are largely absent — but bare `NO` and bare `1:30` are exactly the shapes a logbook fixture is full of, and quoting costs nothing.
- **Rule 1 reminder:** fixtures hold raw facts. Expected projection outputs belong in the test that asserts them, or as a YAML comment, never as a stored field.

Add a one-line `README.md` in `aircraft/`, `importers/` and `pdf/` stating what belongs there, so the empty directories survive in git.

- [ ] **Step 7: Verify the full suite and analysis**

```powershell
dart format .
flutter analyze --fatal-infos
flutter test
dart run tool/check_layering.dart
```

Expected: all clean, 8 tests passing across both test files.

- [ ] **Step 8: Commit**

```powershell
git add test/fixtures
git commit -m "test: add the fixture harness and the divergence flight

Establishes test/fixtures/ with a single YAML loading path and clear
failure messages. Seeds the canonical FAA/EASA divergence flight from
section 4 of the jurisdiction matrix, so issues #18 and #19 have a
concrete case to project against.

Typed per-model decoders arrive with the models in M1; Flight and
Aircraft do not exist yet.

Closes #8"
```

- [ ] **Step 9: Push and open the PR**

```powershell
git push
gh pr create --title "M0: foundations and tooling" --body "Implements the M0 guardrails per docs/superpowers/specs/2026-08-06-m0-foundations-design.md.

Closes #3, #4, #5, #6, #8.

Deferred with reasons in the spec: #1 (needs a product decision), #2 (better after the stack exists), #7 (vacuous against an empty lib/domain/), #9, #10.

Unblocks #16, #15, #13 and #20 — all pure Dart, all startable immediately.

🤖 Generated with [Claude Code](https://claude.com/claude-code)"
```

---

## Self-Review

**Spec coverage:** D1 → Task 1 Steps 1–2. D2 → Task 1 Step 3, Task 2 Step 6, Task 3 Step 1. D3 → Task 2. D4 → Task 5 Steps 4, 6. D5 → commit structure throughout. Issue #3 → Task 1. #5 → Task 2. #6 → Task 3. #4 → Task 4. #8 → Task 5. All five success criteria in the spec map to a verification step.

**One correction against the spec:** the spec states the scaffold `lib/main.dart` *will not* pass the strict settings and that fixing it is in scope. On inspection it declares all return types, has no locals, no dynamic calls and already carries trailing commas — it is expected to pass. Task 2 Step 7 verifies rather than assumes, and still treats fixing it as in scope if analysis disagrees.

**Type consistency:** `findViolations(String, String) -> List<Violation>` is defined in Task 2 Step 3 and consumed with that exact signature in Task 2 Step 1. `Violation` exposes `filePath`, `line`, `uri` — the fields the test reads. `loadFixture(String, String) -> YamlMap` and `FixtureNotFoundException` are defined in Task 5 Step 3 and used with those names in Task 5 Step 1. The fixture keys asserted in Task 5 Step 1 (`sole_manipulator`, `command_authority`, `instructor_aboard`) all exist in the YAML written in Step 4.

**Pre-flight resolutions** (found scanning this plan against its own Global Constraints before execution):

1. *No seventh dependency.* An earlier draft had Task 2 adding `package:test`, which contradicts the Global Constraint limiting this plan to the six packages in Task 1. Both test files import `package:flutter_test/flutter_test.dart` instead — it re-exports `test`, `group` and `expect` from `package:test_api` and is already a dev dependency.
2. *The "flutter test must be clean" constraint applies from Task 2 onward.* `flutter test` exits 1 with `Test directory "test" not found` when no `test/` exists, which is the state during Task 1. Task 1's verification is `dart format`, `flutter analyze` and a clean `build_runner` run. Every task from 2 on runs the full suite.
