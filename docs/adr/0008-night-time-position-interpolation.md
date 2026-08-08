# ADR-0008: Approximate in-flight position as a straight great-circle line between two waypoints

**Status:** Accepted
**Date:** 2026-08-09

## Context

Both EASA (`FCL.010`) and the FAA define night by the sun's position relative to the aircraft,
not a fixed clock time — `docs/jurisdiction-matrix.md` line 87. The sun's position at a given
instant depends on where the aircraft is, and a flight's position genuinely changes over its
duration: a flight that departs in daylight can land after the sun has set at the destination,
or vice versa, and a long east-west flight can cross the twilight boundary purely from the
position change even if the clock time barely moves.

`Flight` (#11, ADR-0001) stores a route as an ordered list of waypoint identifiers
(`docs/jurisdiction-matrix.md` §3) plus overall `offBlocks`/`onBlocks` and optional
`takeoff`/`landing` instants. It does not store a timestamp per waypoint — only two instants
bound the whole flight — and a route entry is free text, not guaranteed to resolve to a real
position (`docs/entry-form.md`, #14: private strips and unlicensed fields have no ICAO code).
#21's acceptance criteria require this decision to be made and documented explicitly, since more
than one approach is defensible.

## Decision

Position during the flight is approximated as a single straight line — in the great-circle
sense, via `interpolateGreatCircle` — between the first and last **resolvable** route waypoints,
walked linearly in step with elapsed time between `takeoff`/`landing` (or `offBlocks`/`onBlocks`
where airborne times are not recorded). Intermediate route waypoints are not used for
positioning, even when they resolve to a real position.

If only one endpoint resolves, that single position is used for the whole flight (no
interpolation). If neither resolves, night time is reported as `DerivedQuantity.notCreditable`
with an explanation naming the reason, rather than guessed — "not creditable" here is honest: the
duration is real flight time, but its night/day split could not be determined.

Each minute of the flight is classified atomically as day or night from the sun's elevation at
that minute's midpoint (`FlightDuration`'s own granularity — ADR-0007 — so no sub-minute
precision is ever needed downstream).

## Alternatives considered

**Multi-leg interpolation, using every resolvable waypoint.** Rejected: `Flight` has no
per-waypoint timestamp, so splitting elapsed time between legs would itself be a guess —
apportioned by great-circle distance, not by any recorded fact — layering one approximation
(leg timing) on top of another (position along a leg) for a precision gain that the missing
per-leg timestamps can't actually support. The straight line between endpoints is simpler and no
less honest about what is actually known.

**Treating the whole flight as stationary at the departure point.** Rejected outright by #21's
acceptance criteria ("flights crossing longitudes handled: the relevant position changes during
the flight") and demonstrated wrong by
`test/domain/primitives/easa_night_time_test.dart`'s interpolation test: a flight from a position
already past its own evening twilight toward one that has not yet reached it is neither wholly
day nor wholly night, and a departure-only reading would report one or the other, incorrectly.

**Throwing, or defaulting to zero, when no waypoint resolves.** Rejected: CLAUDE.md's rule 5 and
the `DerivedQuantity` design (`derived_quantity.dart`) both exist specifically so a value that
cannot be honestly computed is marked unreliable and explained, not silently zeroed (which reads
as "definitely no night time," a false positive) or thrown (which would fail the whole
projection for one flight's missing data, rather than degrading gracefully).

## Consequences

A flight with real intermediate stops gets a position estimate no more refined than
departure-to-final-destination in a straight line, even mid-route. This is a known,
accepted limitation: for any realistic single-flight duration, the twilight boundary does not
move fast enough over distance for a multi-leg path to change the night/day minute count in a
way the missing per-leg timing could support anyway. A private-strip departure or destination
with no ICAO code degrades to single-endpoint or "cannot be computed" rather than blocking the
computation on unrelated route data; the FAA night-time primitive (#22) reuses the same
`interpolateGreatCircle` helper and inherits the same limitation.
