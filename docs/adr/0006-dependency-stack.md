# ADR-0006: Settle the dependency stack now, add packages per milestone

**Status:** Accepted
**Date:** 2026-08-06

## Context

CLAUDE.md requires asking before adding a dependency. Issue #3 was that ask, and it needs a
single answer covering the whole project rather than one ad hoc decision per package as each
milestone comes up.

## Decision

The full stack is settled now: `freezed` and `json_serializable` for models, `drift` for
persistence, `pdf` and `printing` for export, `csv` for import, `yaml` for rules, `riverpod` for
UI state. Each package is added to `pubspec.yaml` in the milestone that first imports it, not
before. As of this task: `freezed_annotation`, `json_annotation` and `yaml` are regular
dependencies, and `build_runner`, `freezed` and `json_serializable` are dev dependencies. `drift`
and `sqlite3_flutter_libs` are deferred to M2, `csv` to M5, `pdf` and `printing` to M6, and the
`riverpod` family to M4. Generated files (`*.freezed.dart`, `*.g.dart`) are gitignored and
regenerated in CI rather than committed.

**Record here, from Task 1:** `freezed` is pinned `^3.2.5`, not `^3.0.0`. freezed 3.0.0–3.2.4
depend on `build ^3` / `source_gen ^3` / `analyzer ^8`, while `build_runner ≥2.15.1` needs
`build ^4` and `json_serializable ≥6.13.1` needs `source_gen ^4.1.2` / `analyzer ≥10`. A
`^3.0.0` constraint resolves to 3.0.0 and then fails to co-resolve with either of the other two.
3.2.5 is the first stable `freezed` on the `build 4` / `analyzer 10` stack. Separately, freezed
3.x requires models to be declared `@freezed abstract class X with _$X`; the bare `@freezed class
X with _$X` form that worked under freezed 2.x is an error under 3.x. This was verified by
generating a smoke model in Task 1, and issue #11 — the `Flight` model — depends on it.

## Alternatives considered

Add all twelve packages now. Rejected: `sqlite3_flutter_libs` and `printing` carry native
platform components that would add build time and platform surface months before either is
used, for no benefit over adding them when M2 and M6 actually need them.

Commit the generated `*.freezed.dart` / `*.g.dart` files instead of gitignoring them. Rejected:
committed generated code is diff noise on every model change and a routine source of merge
conflicts on code nobody actually reviews line by line.

## Consequences

A fresh clone cannot run `flutter analyze` until `build_runner` has generated the `.freezed.dart`
and `.g.dart` files, so CI must run codegen before analysis, and `analysis_options.yaml` must
exclude generated files from lint rather than relying on them not existing. The freezed
`abstract class` requirement is now a fixed constraint on every future model, not just a Task 1
curiosity — issue #11 and everything under `lib/domain/model/` must follow the 3.x form from the
start.
