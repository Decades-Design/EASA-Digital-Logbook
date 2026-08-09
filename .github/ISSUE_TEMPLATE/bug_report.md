---
name: Bug report
about: A computed figure, currency status, or export is wrong
title: ""
labels: type:bug
---

"The hours are wrong" is not actionable on its own — this app computes different numbers for the
same flight under different jurisdictions on purpose (CLAUDE.md rule 5), so a report needs enough
raw facts to tell a real bug apart from a correct-but-surprising divergence.

## Jurisdiction

Which authority's number is wrong — EASA, FAA, UK CAA? If more than one, say so; a bug that hits
every jurisdiction identically usually has a different cause than one that hits only one.

## The flight's raw facts

The inputs, not the output — route, off-blocks/on-blocks (and takeoff/landing if recorded),
capacity (command authority, sole manipulator, instructor presence and capacity, PICUS/SPIC
claim, countersignature state), and anything else that could plausibly affect the figure in
question. If you can attach or paste the flight as it would appear in a fixture (see
`test/fixtures/README.md`), that's ideal.

## Expected vs. actual

- **Expected:** what the figure should be, and why (cite the rule if you can — `FCL.010`,
  `§61.51(e)(1)(i)`, etc.)
- **Actual:** what the app shows

## Where you saw it

Screen or export (entry form, totals, currency page, PDF export), and app version / build if
known.
