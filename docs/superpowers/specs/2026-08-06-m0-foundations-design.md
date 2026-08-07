# M0 — Foundations & Tooling: Design

**Date:** 2026-08-06
**Status:** Approved
**Scope:** GitHub issues #3, #4, #5, #6, #8
**Milestone:** M0 — Foundations & Tooling

---

## Context

The repository is an unmodified `flutter create` scaffold: `lib/main.dart`, no `lib/domain/`,
no `test/`, no `docs/adr/`, and a `pubspec.yaml` carrying no dependencies beyond
`flutter_lints`.

`CLAUDE.md` describes an architecture whose central rule — `domain/` must never import
`package:flutter/*` — is currently enforced by nothing but discipline. The M0 milestone
description states the constraint plainly: *nothing domain-specific ships until the layering
rules are mechanically enforced.*

This design covers the subset of M0 that gates M1. It exists to make the architecture
mechanically enforced before any domain code is written, because retrofitting a layering
guard onto an existing domain layer means fixing violations rather than preventing them.

## Goals

1. A dependency set that lets M1 models be written, with the full stack choice recorded so it
   is not re-argued at each milestone boundary.
2. A layering guard that fails the build when `lib/domain/` reaches for Flutter or I/O.
3. CI that runs format, codegen, analysis, the layering guard, and tests on every PR.
4. The reasoning behind `CLAUDE.md`'s constraints captured as ADRs.
5. A fixture harness that makes "add a fixture" the path of least resistance.

## Non-goals

Deferred M0 issues, with reasons:

| Issue | Deferred because |
|---|---|
| #1 Replace scaffold identifiers | Needs a product decision (reverse-DNS identifier, display name) and touches every platform directory. Only blocking before store or TestFlight work. |
| #2 Write a real README | Better written once the stack and codegen commands actually exist, so build instructions can be verified rather than predicted. |
| #7 Coverage gate for `lib/domain/` | `lib/domain/` currently contains zero files. A 90% threshold against an empty directory measures nothing. Land immediately after the first domain code. |
| #9 LICENSE, issue and PR templates | Administrative. LICENSE needs a decision from the repository owner. |
| #10 Pre-commit hook | Explicitly optional and opt-in per its own issue. CI is the enforcement point. |

Also out of scope: anything in M1 or later. This design deliberately stops at the point where
`Flight` could be written.

---

## Decisions

### D1 — Dependencies are adopted per milestone; the stack is settled now

`CLAUDE.md` requires asking before adding a dependency. Issue #3 is that asking. The decision
is to settle the *whole* stack now — recorded in ADR-0006 — while adding only the packages
M1–M3 actually import.

**Added now** (runtime): `freezed_annotation`, `json_annotation`, `yaml`.
**Added now** (dev): `build_runner`, `freezed`, `json_serializable`.

**Settled but deferred to the milestone that imports them:**

| Package | Milestone | Why not now |
|---|---|---|
| `drift`, `sqlite3_flutter_libs` | M2 | Native components; adds build time and platform surface before any persistence exists |
| `csv` | M5 | Unused until import adapters |
| `pdf`, `printing` | M6 | `printing` carries platform channels |
| `flutter_riverpod`, `riverpod_annotation`, `riverpod_generator`, `riverpod_lint`, `custom_lint` | M4 | Riverpod is a UI-layer concern. `domain/` is pure Dart and must not depend on it. Adding it now would contradict this very decision. |

Versions are pinned to caret ranges on explicit current majors, with a rationale comment where
the choice is non-obvious.

### D2 — Generated files are gitignored and regenerated in CI

`*.freezed.dart` and `*.g.dart` are not committed. Issue #6's requirement that *codegen runs
before analysis so generated files are present* only makes sense under this policy.

Consequence: `analysis_options.yaml` must exclude generated files from analysis, or the strict
lint set from D3 will fail on code that neither of us wrote. This is the most common way this
configuration breaks.

### D3 — Strict analysis, with the layering guard as a script

Lints per issue #5: `always_declare_return_types`, `prefer_final_locals`, `avoid_dynamic_calls`,
`require_trailing_commas`. Language modes: `strict-casts`, `strict-inference`,
`strict-raw-types`.

The layering guard is `tool/check_layering.dart` — a plain Dart script, not a `custom_lint`
rule, per issue #5's own note that a script is fine and faster to write. It adds no dependency
and is fast enough to reuse in a pre-commit hook later (#10).

### D4 — Fixtures are YAML

A single format everywhere. Comments are the deciding factor: every fixture in this project
wants a regulatory citation next to the value it justifies, and JSON cannot carry one.
`yaml` is already a dependency under D1.

Documented caveat: quote aerodrome identifiers and anything time-shaped. Dart's `yaml` package
implements the YAML 1.2 core schema, so the YAML 1.1 sexagesimal and `yes`/`no`/`on`/`off`
boolean traps are largely absent — but bare `NO` and bare `1:30` are exactly the shapes a
logbook fixture is full of, and the discipline costs nothing.

### D5 — One branch, one commit per issue, one PR

Branch `chore/m0-foundations`. Conventional commits, one per issue, each closing its issue.
Five separate PRs would be ceremony without benefit on a solo repository, and #6's CI cannot
be verified green until #3 and #5 have landed anyway.

---

## Component design

### #3 — Dependency wiring

Per D1. `dart run build_runner build --delete-conflicting-outputs` must complete clean against
an empty model set. `.gitignore` gains `*.freezed.dart` and `*.g.dart` per D2.

**Risk — `freezed` 3.x changed its public syntax.** Models are declared `sealed`/`abstract
class` rather than the 2.x `@freezed class X with _$X` form. Whichever major is pinned here
dictates how every M1 model is written, making this pin load-bearing on issue #11. The pinned
version and its syntax form are to be stated explicitly in ADR-0006 so #11 does not have to
rediscover it.

### #5 — Strict analysis and the layering guard

`analysis_options.yaml` gains the lint and language-mode settings from D3, plus an
`analyzer.exclude` for `**/*.freezed.dart` and `**/*.g.dart` per D2.

`tool/check_layering.dart`:

- Walks `lib/domain/**.dart`.
- Strips line and block comments before matching, so a commented-out import is not a violation.
- Flags both `import` **and** `export` directives — a re-export reintroduces the dependency
  just as effectively and is the case most often forgotten.
- Banned prefixes as a top-level `const` list, so extending it is a one-line change:
  `package:flutter/`, `dart:io`, `dart:ui`.
- Prints `file:line` per violation; exits non-zero if any are found.
- Exits zero cleanly when `lib/domain/` does not yet exist.

`test/tool/check_layering_test.dart` — **the guard is itself tested.** `lib/domain/` is empty
today, so the check passes trivially and could keep passing indefinitely while silently
broken. The test writes a temporary file importing `package:flutter/material.dart`, asserts
the checker reports it, and asserts a clean file passes. An untested guard is not a guard.

**Known work:** the existing `lib/main.dart` scaffold will not pass the strict settings.
Bringing it clean is part of this issue, not a follow-up, because #6 requires
`flutter analyze --fatal-infos` to be green.

### #6 — CI

`.github/workflows/ci.yaml`, triggered on `push` and `pull_request`, running on
`ubuntu-latest` — no iOS or Android build is needed for analysis and unit tests.

`subosito/flutter-action@v2` pinned to **3.44.0**, matching the local puro environment, with
SDK and pub caching configured to keep runs under roughly three minutes.

Step order, which is deliberate:

```
flutter pub get
dart format --set-exit-if-changed .
dart run build_runner build --delete-conflicting-outputs
flutter analyze --fatal-infos
dart run tool/check_layering.dart
flutter test
```

**Format runs before codegen, not after.** Generated files are gitignored but present on disk
once codegen has run; a format check that sees them fails CI on output nobody controls.
Formatting source first, then generating, satisfies #6's requirement that generated files
exist before analysis without ever formatting them.

### #4 — ADRs

`docs/adr/` with `template.md` (context / decision / consequences / status + date) and
`README.md` as the index.

| ADR | Subject |
|---|---|
| 0001 | Raw facts only, never derived quantities |
| 0002 | All persisted times are UTC, citing `AMC1 FCL.050` |
| 0003 | Entries are mutable drafts until first exported, then committed with delta revisions |
| 0004 | Currency rules are declarative data, not Dart code |
| 0005 | Offline-first; no backend, no account system, no analytics; GDPR reasoning |
| 0006 | Stack settled, dependencies adopted per milestone, generated files gitignored |

ADR-0003 records the reasoning behind the `CLAUDE.md` rule 4 rewrite: export is the commit
point because it is the moment the record is asserted to an authority; before that there is
nothing to be reliable about. It must state why unconditional append-only was rejected, and
why the paper-logbook analogy argues *for* retaining history rather than against it. Revision
history is device-local and backup-scoped, not part of any future sync payload.

ADR-0006 records D1 and D2, and states the pinned `freezed` major and its syntax form.

This issue also commits work currently untracked or uncommitted in the working tree:

- The `CLAUDE.md` rule 4 rewrite (drafts-until-exported), currently modified and uncommitted.
- `docs/entry-form.md` and `docs/jurisdiction-matrix.md`, currently untracked. The matrix is
  effectively the specification for M1 and should not live only on one machine.
- A link from `CLAUDE.md` to the ADR index.

Separately, issue #15 cites "CLAUDE.md rule 2" for the UTC requirement; UTC is rule 3. The
numbering drifted when rule 4 was rewritten. Correct the issue text.

### #8 — Fixture harness

```
test/fixtures/
  README.md          # what each set is for, provenance, scrubbing status
  flights/
  aircraft/
  importers/
  pdf/
```

A loader helper providing a single way to read fixtures everywhere, with clear failure
messages naming the fixture and the missing or mistyped key.

**Limitation, stated honestly:** `Flight` and `Aircraft` do not exist yet, so this issue ships
the harness — directory layout, YAML loading, typed access with good errors — and per-model
decoders arrive with the models in M1. Writing decoders now would mean inventing the very
types issue #11 is meant to define.

**Seeded fixture:** the canonical divergence case from §4 of `docs/jurisdiction-matrix.md` —
rated private pilot, sole manipulator, instructor aboard, dual instruction being given — as
raw facts, with its regulatory annotations as YAML comments. The matrix requires that this
exact flight exist in `test/fixtures/` and produce different PIC time under each profile.
Seeding it now makes issues #18 and #19 concrete rather than abstract.

---

## Risks

| Risk | Mitigation |
|---|---|
| `freezed` 3.x syntax differs from 2.x; the pin dictates how all M1 models are written | State the pinned major and its syntax form explicitly in ADR-0006 |
| Strict lints fail on generated code | `analyzer.exclude` for `**/*.freezed.dart`, `**/*.g.dart` (D2) |
| `dart format --set-exit-if-changed` fails on generated output | Format before codegen, not after (#6 step order) |
| Layering guard passes vacuously against an empty `lib/domain/` and rots undetected | The guard has its own unit test asserting it catches a real violation |
| Scaffold `lib/main.dart` blocks a green CI run | Bringing it clean is in scope for #5 |

## Success criteria

- `flutter analyze --fatal-infos` is clean at the strict settings.
- `dart run tool/check_layering.dart` exits zero on the current tree, and its unit test proves
  it exits non-zero on a real violation.
- CI is green on the PR, in under roughly three minutes.
- `dart run build_runner build` completes clean.
- Six ADRs exist and `CLAUDE.md` links to the index.
- `docs/jurisdiction-matrix.md` and `docs/entry-form.md` are tracked in git.
- A fixture can be loaded through the helper in a test.
- Issues #3, #4, #5, #6 and #8 are closed.

## What this unblocks

Issues #16 (duration representation), #15 (UTC instant type) and #13 (operating capacity enum)
become startable immediately — all pure Dart, all dependency-free, and all of them field types
that #11 (`Flight`) needs before it can be written. #20 (solar position engine) is independent
of the model layer and startable in parallel.
