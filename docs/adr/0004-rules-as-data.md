# ADR-0004: Currency rules are versioned data, not Dart logic

**Status:** Accepted
**Date:** 2026-08-06

## Context

Currency thresholds and windows differ per authority and change over time with effective-from
dates — `docs/jurisdiction-matrix.md` §5 alone lists rolling-day windows (EASA FCL.060(b)(1): 3
take-offs, approaches and landings in 90 days), calendar-month windows (FAA §61.57(c): 6 months),
and a UK divergence in the same requirement (12 hours across the whole 2-year validity period
rather than the 12 months preceding expiry). Hard-coding any of this in Dart means every new
authority, and every amendment to an existing one, is a code change and a release.

## Decision

Currency rules are versioned YAML under `assets/rules/`, each carrying an `effective_from` date,
evaluated by a generic rule engine. The YAML references named, tested Dart primitives — it does
not express the derivation logic itself. This mirrors the same declarative/imperative split
CLAUDE.md draws for jurisdiction profiles: thresholds, windows, counts and rule composition are
data; deriving a quantity from raw facts is real logic and belongs in Dart.

## Alternatives considered

Rules as Dart classes, one per authority or per rule. Rejected against the acceptance test
CLAUDE.md sets for the whole jurisdiction abstraction: adding Transport Canada should require a
YAML profile and at most one new primitive, with no changes to the engine, repositories or UI.
Rules expressed as Dart classes fail that test by construction — a new authority's currency
requirements would mean new code paths through the engine, not new data fed to an existing one.

## Consequences

The engine must report which flights satisfied each requirement of a rule, not just whether the
rule passed, so the UI can explain a result rather than showing a red or green pill — "not
current" with no explanation is treated as a bug, not a missing feature. New authorities and
rule amendments become data changes reviewable as a diff against a YAML file, rather than logic
changes requiring the same scrutiny as the projection or currency engine itself.
