# ADR-0007: Represent logbook durations as integer minutes

**Status:** Accepted
**Date:** 2026-08-08

## Context

Logbook time is presented in two different formats depending on authority and personal
preference: `HH:MM` is the traditional paper-logbook format retained under EASA (`AMC1
FCL.050` column 7 permits either hours-and-minutes or decimal hours), while FAA logbooks and
many electronic tools default to decimal hours. Whichever format a duration is displayed in, it
is still exported and summed across a career's worth of entries — the M6 golden PDF test
asserts running totals (*brought forward*, *this page*, *total to date*) reconcile exactly
across a multi-page export.

A `double hours` field looks adequate for a single flight but does not stay exact under
summation: floating-point addition accumulates rounding error across thousands of additions,
and that error surfaces nowhere near its cause — a multi-page PDF export's running totals stop
reconciling, thousands of flights away from the entry that introduced the drift. The failure is
intermittent in the sense that it depends on which values happened to sum, not on any single
flight being wrong.

## Decision

`FlightDuration` stores a duration as a single whole number of minutes (`int inMinutes`).
Arithmetic — `operator +`, `operator -`, `sum` — is always performed on this integer and is
therefore exact; there is no accumulation of rounding error regardless of how many durations are
combined.

`HH:MM` and decimal hours are display formats only, produced by `toHoursMinutes()` and
`toDecimalHours()`. `toDecimalHours()` renders to one decimal place (tenths of an hour),
rounding half away from zero, computed with integer arithmetic on the minute count rather than
through `double` — an exact `.05`-hour boundary rounds outward, not to even and not toward zero.
Rounding happens only at this display boundary: a total is always the sum of the underlying
integer minutes, and only that final sum is ever rounded for display. Summing already-rounded
display values instead produces a materially different, and wrong, result — see the "rounding at
the display boundary" test in `test/domain/model/flight_duration_test.dart`, where doing so
overstates a 10,000-flight total by more than 150 hours.

Because rounding is one-directional, neither decimal round-trip is total, and the two fail
differently.

`parseDecimalHours` followed by `toDecimalHours` reproduces the original string only when that
string was already written to one decimal place. `'1.4'` survives; `'2'` returns as `'2.0'`,
`'0.05'` as `'0.1'`, and `'1.025'` as `'1.0'`. The parse itself is exact — `'1.025'` is 62
minutes and stays 62 minutes — so what a higher-precision vendor CSV loses is display digits,
not stored time.

`toDecimalHours` followed by `parseDecimalHours` returns the original minute count only for
multiples of 6 minutes (exact tenths of an hour). `FlightDuration(83)` (`1:23`) renders as
`'1.4'`, and `FlightDuration.parseDecimalHours('1.4')` is 84 minutes, not 83.

Neither limitation loses stored data, because decimal hours are never a storage format here.
`toHoursMinutes()`/`parseHoursMinutes()` and `toDecimalHours()`/`parseDecimalHours()` both exist,
rather than one being picked, because `AMC1 FCL.050` column 7 permits either and both EASA-style
and FAA-style input must be readable.

## Alternatives considered

**`double hours`.** Rejected for the reason above: it is not exact under summation, and the
failure it produces is silent and displaced from its cause.

**Dart's own `Duration`.** `Duration` is internally exact (it stores microseconds as an `int`),
so it does not have the summation problem. It was rejected anyway because it does not make the
wrong thing impossible to express: `Duration` admits sub-minute, even sub-second, precision, and
nothing in a logbook is ever meaningfully more precise than a minute — a `Duration` constructed
from imported or user-entered seconds would silently carry spurious precision. Its `inHours`
getter also truncates rather than rounding, which is the wrong policy for a display quantity
that should round half away from zero. A logbook-specific type makes minute granularity and the
rounding policy explicit instead of relying on callers to apply both correctly every time.

## Consequences

Every place that needs a human-readable duration must go through `toHoursMinutes()` or
`toDecimalHours()` rather than formatting `inMinutes` ad hoc, which keeps the rounding policy in
one place. Every place that combines durations — projections, currency-rule totals, PDF running
totals — must combine `FlightDuration` values (or raw minutes) before ever converting to a
display string, never the reverse. `Flight` (#11) is expected to use `FlightDuration` for its own
duration fields and is responsible for rejecting a negative duration where that is a business
rule; `FlightDuration` itself stays a closed, total value type — `operator -` can produce a
negative result, reported via `isNegative`, rather than throwing.
