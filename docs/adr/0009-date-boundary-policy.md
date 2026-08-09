# ADR-0009: A flight's logbook date is the UTC calendar date of departure

**Status:** Accepted
**Date:** 2026-08-09

## Context

A flight departing 23:40 UTC and arriving 01:10 UTC crosses a UTC calendar-day boundary mid-flight.
It is one row of raw facts (rule 1) — never split into two — but list ordering, PDF pagination and
any currency rule with a calendar-window condition (`docs/jurisdiction-matrix.md` §5's "FAA windows
are frequently calendar months") all need a single, unambiguous answer to "which date does this
flight belong to?" #29's acceptance criteria require that answer to be decided, documented, and
applied from one place, since more than one convention is defensible and getting it wrong would
misfile a flight for currency purposes without any exception or test failure to reveal it.

Rule 3 (ADR-0002) already narrows the question: every stored instant is UTC, and no local
timestamp is ever persisted. There is therefore no stored "local date" to fall back on, and no
timezone lookup available in `lib/domain/` to derive one — the IANA-database boundary is
deliberately deferred to M4 (`UtcInstant`'s own dartdoc, "the M4 boundary").

## Decision

A flight's logbook date is the **UTC calendar date of `Flight.offBlocks`** — the date of
departure, always, regardless of the date `Flight.onBlocks` falls on. Implemented as
`Flight.logbookDate` (`flight_logbook_date.dart`), returning a new `CalendarDate` value
(`calendar_date.dart`): year/month/day only, no time-of-day component, so it cannot be confused
with an instant the way a truncated `DateTime` could be.

`CalendarDate` is deliberately general-purpose, not flight-specific — `PilotCapacity`'s
`credentialExpiry` and `signatoryCredentialExpiry` fields are provisionally typed as `UtcInstant`
with a note that a proper calendar-date type was #29's territory; they are candidates to migrate
to `CalendarDate` later, though that migration is out of scope for this issue.

This is the one place the UTC-date truncation happens. Every future consumer — list sort key, PDF
page break, currency-window bucketing — must call `Flight.logbookDate` rather than reading
`offBlocks` and truncating it independently, so the policy cannot quietly diverge between them.
None of those consumers exist yet as of M1; this ADR and the accompanying getter exist so the
single correct answer is available before they're built, not invented separately by each one.

## Alternatives considered

**Date of arrival.** Rejected: less conventional, and less intuitive for a pilot who is filling in
the entry as they depart rather than after they land — the departure date is the one they already
know before the flight even starts.

**Split the entry into two rows at the UTC date boundary.** Rejected outright by rule 1: a flight
is one row of raw facts. Splitting a single continuous flight into two logbook entries because it
happened to straddle midnight would misrepresent block time, landings and every derived quantity
that reads the flight as a whole.

**Local date of departure, at the departure aerodrome's timezone.** Rejected: resolving a named
timezone to a UTC offset — including historical DST rules — requires the IANA database, which
`lib/domain/` does not have access to until M4. It would also make the logbook date depend on
*where* the aircraft was, which is precisely what rule 3 exists to avoid: UTC storage means the
domain layer never needs to know or guess a location's offset to answer a question about time.

## Consequences

A flight logged 23:40Z-01:10Z UTC files under 2026-06-15, even though a pilot reading their own
wall clock at a foreign aerodrome might reach for a different date. That mismatch is real and will
need a UI-level explanation once M4 adds timezone-aware display, but the *stored and computed*
logbook date itself never changes based on which timezone is used to view it — only the display
layer's rendering of it can.

Every later milestone that needs to group or order flights by date (M2's list view, M5's PDF page
breaks, M6's currency-window evaluation) reads `Flight.logbookDate` rather than reimplementing the
truncation, so a future change to this policy is a one-line edit to `flight_logbook_date.dart`,
not a hunt across the codebase.
