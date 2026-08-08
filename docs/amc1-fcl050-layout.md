---
paths: ["lib/export/**", "test/fixtures/pdf/**"]
---

# AMC1 FCL.050 — the printed logbook layout

Transcribed from the EASA-published pilot logbook template, **ED Decision 2020/005/R**. This is
the sheet the EASA/UK PDF export must reproduce, and the authority for every "column N"
citation in this codebase.

> **Note the ED Decision number.** `docs/jurisdiction-matrix.md` attributes the column structure
> to ED Decision 2022/014/R as amended by 2025/002/R. The template EASA actually publishes is
> marked 2020/005/R. Before M6 hardens the layout, confirm whether a later decision revised the
> sheet — if it did, this file needs re-transcribing from that one.

---

## 1. Front matter

Page 1, centred:

```
PILOT LOGBOOK

Holder's name(s)         ______________________________

Holder's licence number  ______________________________
```

Page 2 — **HOLDER'S ADDRESS**, six blocks in a 2 × 3 grid. The first block is the original
address; the remaining five are each labelled *[space for address change]* and carry three
blank rules. A pilot's address changes over a career and the record has to absorb that without
a reissue.

## 2. The entry table

Twelve numbered column groups, spread across a landscape opening: groups 1–8 on the left page,
9–12 on the right. **Groups, not columns** — several carry sub-columns, and the group number is
what regulations and this codebase cite.

| # | Group | Sub-columns |
|---|---|---|
| 1 | DATE | dd/mm/yy |
| 2 | DEPARTURE | PLACE, TIME |
| 3 | ARRIVAL | PLACE, TIME |
| 4 | AIRCRAFT | MAKE, MODEL, VARIANT — REGISTRATION |
| 5 | SINGLE-PILOT TIME / MULTI-PILOT TIME | SE, ME (single-pilot); multi-pilot has no sub-column |
| 6 | TOTAL TIME OF FLIGHT | — |
| 7 | NAME(S) PIC | — |
| 8 | LANDINGS | DAY, NIGHT |
| 9 | OPERATIONAL CONDITION TIME | NIGHT, IFR |
| 10 | PILOT FUNCTION TIME | PIC, CO-PILOT, DUAL, INSTRUCTOR |
| 11 | FSTD SESSION | DATE (dd/mm/yy), TYPE, TOTAL TIME OF SESSION |
| 12 | REMARKS AND ENDORSEMENTS | — |

**Group 5 spans both single-pilot and multi-pilot time under one number.** This is the detail
that made every earlier count come out at thirteen groups instead of twelve, and it is why
"multi-pilot time is column 6" — which this repo asserted in several places — was wrong.

Group 11 records a *session*, and carries its own date. An FSTD session is therefore a row of
this table that has no aircraft, no departure or arrival, no landings and no flight time: the
sheet itself treats simulator time as a different kind of entry sharing a page with flights.
See §5.

## 3. Page totals

Three summary rows close every page, rendered in the time columns:

```
TOTAL THIS PAGE
TOTAL FROM PREVIOUS PAGES
TOTAL TIME
```

These are the exact printed labels — not "brought forward" / "carried forward", which is the
usual paper-logbook wording and which CLAUDE.md paraphrases. `TOTAL TIME` is the running
total to date, and must equal `TOTAL THIS PAGE + TOTAL FROM PREVIOUS PAGES` exactly, in every
time column, on every page. That reconciliation is the golden test M6 needs.

## 4. Certification block

Sits inside group 12 on each page:

```
I certify that the entries in this log are true.

PILOT'S SIGNATURE
```

Verbatim wording. It must be rendered on every page **even when unsigned** — an electronic
logbook is accepted on the basis that it can be printed, signed and dated, so an export that
omits the block where a signature would go is not a compliant printout.

## 5. What this implies for the data model

- **Group 10 is the projection layer's output surface.** PIC, co-pilot, dual and instructor are
  four separate sub-columns of one group, which is exactly the per-jurisdiction derivation
  `domain/projection/` produces. The sheet has no column for "sole manipulator" or "command
  authority" — those are raw facts that never appear in print, which is the clearest possible
  statement of why the model stores them and the logbook does not.
- **Group 5 forces the single/multi-pilot split to be a stored fact**, not a lookup from the
  aircraft record at print time. Both halves are printed side by side.
- **Group 11 confirms FSTD sessions are entries, not flights.** Its own date column means a
  session need not correspond to any flight, and its total is deliberately outside
  `TOTAL TIME OF FLIGHT` (group 6). Issue #28 covers the model; nothing yet designs the entry
  screen for one — see `docs/entry-form.md`, which assumes an aircraft throughout.
- **Group 12 is a single free-text cell** carrying both the mandatory remarks (skill tests,
  proficiency checks, SPIC/PICUS countersignatures, instrument training toward a licence) and
  the certification block. It is not a structured field in the printed record, however
  structured the app makes it internally.
- **Group 2 and 3 carry a TIME each**, in UTC. There is no separate "block time" column: total
  time of flight (group 6) is the derived figure, and departure/arrival times are the raw ones.

## 6. Still to confirm before M6

1. Whether a decision later than 2020/005/R revised this sheet.
2. Column widths and the rows-per-page count, neither of which is prescribed by the AMC — they
   are a layout choice, but a fixed one once golden tests exist.
3. Whether the UK CAA's published template diverges from this. UK Part-FCL is retained EU law
   that the CAA amends independently, so the layout is a per-profile field for a reason.
