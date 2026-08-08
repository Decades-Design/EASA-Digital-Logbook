# ADR-0002: All stored times are UTC

**Status:** Accepted
**Date:** 2026-08-06

## Context

`AMC1 FCL.050` requires times to be recorded in UTC (see also `docs/jurisdiction-matrix.md` §2,
"all times should be in UTC"). Dart's `DateTime.isUtc` flag is trivially lost — a naive local
`DateTime`, or a UTC instant passed through a step that calls `.toLocal()`, still type-checks
and still compiles. The failure this produces is silent: night time and currency windows are
computed against the wrong instant with no exception raised, no test failure, and no visible
symptom until a number is wrong by the local UTC offset.

Regulatory text in `CLAUDE.md` is a working summary, not a verified citation, and AMC1 FCL.050
is amended by ED Decision 2025/002/R; this decision rests on the UTC requirement itself, which
`docs/jurisdiction-matrix.md` corroborates independently, rather than on any sub-paragraph
numbering that could have shifted.

## Decision

Every persisted instant is UTC. Local time exists only at the UI boundary, as a display and
entry convenience — `docs/entry-form.md` §2 specifies a local-entry-with-UTC-echo layout driven
by user preference, not by jurisdiction, precisely because storage and display are different
concerns. Never persist a local timestamp, and never persist a naive `DateTime`.

## Alternatives considered

Store local time together with a UTC offset. Rejected: it makes every downstream comparison —
sorting, duration arithmetic, twilight computation, currency windows — offset-aware for no
benefit, since the offset carries no information that isn't already recoverable from the
aerodrome and the UTC instant if it is ever needed for display.

## Consequences

A wrapper type over `DateTime` is needed so that "UTC" is enforced by the type system rather
than by convention (tracked in issue #15). Serialisation is always ISO-8601 with an explicit
`Z`, never a bare offset-less string that could be misread as local.

**Record here, from #15:** `UtcInstant` (`lib/domain/model/utc_instant.dart`) is the wrapper.
Rendering a local calendar reading returns a `WallClock`
(`lib/domain/model/wall_clock.dart`), not a `DateTime` — a `DateTime` with an offset baked into
its fields but no record of what that offset was is exactly the silent-local-time trap this ADR
exists to close. `WallClock` carries the offset it was rendered at alongside its calendar
fields and is documented as a display value, never an instant: it cannot be persisted, and two
`WallClock`s at different offsets are not comparable.

`UtcInstant.toWallClock(Duration offset)` takes the offset from the *caller* rather than
resolving it from a named zone. Mapping a zone identifier (`Europe/London`,
`America/New_York`) to the correct UTC offset at a given instant — including historical DST
rules — needs the IANA time zone database, and that lookup is deferred to the UI layer in M4.
No `package:timezone` dependency is added by this task; that is a deliberate scope decision by
the project owner, not an oversight, and `lib/domain/` stays free of it in the meantime.

`tool/check_domain_types.dart` is the enforcement mechanism this ADR called for: it fails the
build if `lib/domain/` names `DateTime` anywhere, matched on a word boundary after stripping
comments, sharing the comment-stripping regex (`tool/dart_source.dart`) with
`tool/check_layering.dart` from ADR-0001. Its allowlist is exactly the two files that must
legitimately touch `DateTime` — `lib/domain/model/utc_instant.dart` (the wrapper) and
`lib/domain/model/wall_clock.dart` (its display companion) — compared by exact normalised path
suffix, not substring, so a lookalike file name is never accidentally allowlisted. The guard
runs in CI immediately after the layering check.
