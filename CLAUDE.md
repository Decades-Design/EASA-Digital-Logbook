# CLAUDE.md

Flutter (iOS + Android) pilot logbook and currency tracker for a pilot holding **both EASA
(primary) and FAA licences**. The app is the pilot's legal record of flight time. Treat data
integrity as a hard requirement, not a feature.

## Non-negotiable domain rules

Read these before touching anything in `lib/domain/`. Most bugs in this codebase come from
violating one of them.

1. **Never store a derived quantity.** A flight row stores *raw facts only*: UTC block times,
   aircraft, aerodromes, who was aboard, the pilot's role, instructor presence, landing counts
   by light condition. Quantities like "PIC time", "cross-country time", "night time" are
   **computed per jurisdiction** at read time. Do not add a `picTime` column to the flights
   table. If you think you need one, you need a projection instead.

2. **All stored times are UTC.** AMC1 FCL.050 requires it. Local time is a display concern
   only. Never persist a local timestamp, never persist a naive `DateTime`.

3. **FAA and EASA disagree, deliberately.** The same flight yields different numbers under
   each. Known divergences that must be handled in the projection layer:
   - *PIC*: FAA §61.51 lets a sole manipulator log PIC while receiving instruction. EASA does
     not — that is dual. EASA has separate SPIC and PICUS concepts with countersignature rules.
   - *Night*: differing definitions and differing currency windows.
   - *Cross-country*: FAA generally needs a landing >50 nm from origin for rating credit;
     EASA's definition differs and ATPL credit has its own logging requirement.
   - *Instrument*: FAA splits actual/simulated; EASA logs IFR time.
   When unsure which rule applies, **stop and ask** rather than guessing. A wrong currency
   calculation is worse than no calculation.

4. **Entries are append-only.** Edits create a new revision; the prior revision is retained
   with timestamp and reason. Never `UPDATE` or `DELETE` a flight row in place. EASA's 2023
   guidance on electronic records expects audit trails, authentication and correction
   tracking, and this is impossible to retrofit later.

5. **Landings are counted separately by day and night.** Not as a single total. Night currency
   depends on it.

## Architecture

```
lib/
  domain/          # Pure Dart. No Flutter imports, no I/O. Fully unit tested.
    model/         # Flight (raw facts), Aircraft, Crew, Licence, Aerodrome
    projection/    # EasaProjection, FaaProjection — derive columns from raw facts
    currency/      # Rule engine: evaluates YAML rule defs against a flight set
  data/            # Drift/SQLite, repositories, revision history
  io/              # Import/export adapters (ForeFlight, Garmin, CSV)
  export/          # PDF generation (AMC1 FCL.050 layout)
  ui/              # Flutter widgets, Riverpod providers
```

`domain/` must never import `package:flutter/*`. If a domain file needs a Flutter import, the
logic is in the wrong layer.

## Currency rules are data, not code

Currency requirements change. Encode them as declarative YAML under `assets/rules/`, versioned
with an effective-from date, evaluated by a generic engine. Do not hard-code thresholds in Dart.

```yaml
id: easa.fcl060.passenger_recency
jurisdiction: EASA
effective_from: 2011-11-08
requires:
  - count: 3
    of: takeoffs_and_landings
    within_days: 90
```

Each rule must record *which flights satisfied it*, so the UI can explain a result rather than
just showing a red or green pill. "Not current" with no explanation is a bug.

## Import / export

- **ForeFlight**: `logbook_template.csv` — a single CSV containing two tables (Aircraft, then
  Flights) plus typed custom fields in the form `[Hours]FieldName`. Column order and header
  names are load-bearing; do not reorder or omit columns on export. Importing the same file
  twice creates duplicates in ForeFlight, so exports must be range-scoped.
- **Garmin Pilot**: CSV logbook export. Distinct from G1000/G3X SD-card *data logs*, which are
  1 Hz telemetry and belong to the flight-recording feature, not the importer.
- All importers map into a **canonical internal model** via per-vendor adapters. Never let a
  vendor's field naming leak past `io/`.
- Every import is a transaction with a preview step and a full undo. Import must never
  partially apply.
- Expect messy input: decimal hours vs `HH:MM`, ambiguous date formats, non-ICAO type codes.
  Reject with a clear per-row error rather than silently coercing.

## EASA PDF export

The printable output is the compliance story: an electronic logbook is generally accepted
provided it can be printed, signed and dated. Use the `pdf` Dart package, landscape A4,
matching the AMC1 FCL.050 twelve column groups.

Requirements that are easy to get wrong:
- Running totals per page: *brought forward*, *this page*, *total to date*. These must
  reconcile exactly; add a golden test asserting the arithmetic across a multi-page export.
- Signature and certification blocks must be present even when empty.
- Page output must be deterministic — same input, byte-identical PDF — so it can be tested.

## Conventions

- State management: Riverpod. Immutable models via `freezed`. DB via `drift`.
- Run `dart format .` and `flutter analyze` before committing; both must be clean.
- Run `flutter test` before committing.
- Domain logic requires unit tests. Currency rules and projections require table-driven tests
  with real-world flight fixtures, including the FAA/EASA divergence cases above.
- Commits: conventional commits (`feat:`, `fix:`, `refactor:`).
- Prefer adding a fixture to `test/fixtures/` over inventing test data inline.

## Working style

- Offline-first. The app must be fully functional with no network. Sync, if added, is an
  additive layer and never a dependency.
- When a change touches regulatory interpretation, cite the specific rule (e.g. `AMC1
  FCL.050(b)(1)`, `§61.57(c)`) in a code comment and in the commit message.
- Do not add a cloud backend, account system or analytics without being asked. This data is
  personal data under GDPR and the scope decision is deliberate.
- Ask before adding a dependency. Prefer the standard library and packages already present.

## Deliberately out of scope for now

Flight recording (background GPS), cloud sync, instructor countersignature workflow,
multi-user. Do not scaffold for these speculatively.