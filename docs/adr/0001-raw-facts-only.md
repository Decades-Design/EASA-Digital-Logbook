# ADR-0001: Store raw facts only, never a derived quantity

**Status:** Accepted
**Date:** 2026-08-06

## Context

The authorities this app must support disagree about what a given hour of flight counts as.
The clearest case: under FAA §61.51(e), a sole manipulator of the controls can log PIC time
while receiving instruction; EASA has no general sole-manipulator concept, and the same
hand-flying hour is dual time with no PIC credit unless the pilot separately held command
authority (see `docs/jurisdiction-matrix.md` §4, "the canonical divergence case"). A value like
"PIC time" is therefore not a property of a flight — it is the output of applying one
authority's rule to that flight.

A pilot who logs a flight today and adds a second licence next year needs that flight's PIC
time recomputed under the new authority's rule. If "PIC time" were stored as a column captured
at entry time, that recomputation is impossible: the raw circumstances of the flight — who was
manipulating, who held command, who was aboard and in what capacity — are gone the moment they
are collapsed into a single derived number for one jurisdiction.

## Decision

A flight row stores raw facts only: command authority, sole manipulator, sole occupant,
instructor aboard and in what capacity, full route, and the other discriminators enumerated in
CLAUDE.md rule 2 and `docs/jurisdiction-matrix.md` §9. Quantities like PIC time, cross-country
time, and night time are never persisted. They are computed per jurisdiction at read time by
the `domain/projection/` layer, which applies a resolved jurisdiction profile to the stored
facts.

## Alternatives considered

Store EASA-derived columns (`picTime`, `nightTime`, …) now and backfill FAA-derived columns
later, when a second licence is actually added. Rejected: this is the one mistake that cannot
be repaired later. Whether a pilot held command authority — as distinct from sole manipulation
— on a specific flight in 2023 is not something that can be reconstructed from an EASA PIC
total after the fact. The backfill has no data to backfill from.

## Consequences

Every read path — dashboard, currency engine, PDF export — must go through a projection instead
of reading a column directly; there is no shortcut path to "just the number." No `picTime`
column ever appears on the `flights` table, and any pull request that adds one is by
construction reintroducing this bug. Adding a new authority never triggers a data migration on
existing flights, because the raw facts were already jurisdiction-agnostic; it only requires a
new profile and, where needed, new primitives (see ADR-0004).
