# CLAUDE.md

Flutter (iOS + Android) pilot logbook and currency tracker for a pilot holding licences under
**more than one authority** (today: EASA primary, FAA secondary; UK CAA planned). The app is
the pilot's legal record of flight time. Treat data integrity as a hard requirement.

Solo project, no certification audit. Keep documentation proportionate: put the reasoning in a
comment beside the code it explains rather than in a separate document.

## Non-negotiable domain rules

Read these before touching anything in `lib/domain/`. Most bugs in this codebase come from
violating one of them.

1. **Never store a derived quantity.** A flight row stores *raw facts only*. Quantities like
   "PIC time", "cross-country time", "night time" are **computed per jurisdiction** at read
   time. Do not add a `picTime` column to the flights table. If you think you need one, you
   need a projection instead.

2. **Raw facts must be the union of every authority's discriminators, not just EASA's.** This
   is the one mistake that cannot be repaired later: you cannot retroactively recall whether
   you held command authority on a flight from 2023. Before adding or changing a field in
   `Flight`, check it against FAA, EASA, UK CAA and one unrelated authority (Transport Canada
   or CASA) as a stress test. Fields that are easy to omit and impossible to backfill:
   - command authority as a flag **separate** from sole manipulation
   - instructor aboard, and in what capacity
   - solo vs accompanied
   - full route, so cross-country distance is computable against *any* threshold — never store
     a precomputed "is cross-country" boolean
   - landings split full-stop vs touch-and-go, **and** day vs night, as four counts
   - IFR flight plan filed, distinct from actual instrument conditions, distinct from simulated
   - FSTD qualification level, not just "sim: yes"
   - countersignature state and signatory identity

3. **All stored times are UTC.** AMC1 FCL.050 requires it. Local time is a display concern
   only. Never persist a local timestamp, never persist a naive `DateTime` — use `UtcInstant`.

4. **Entries are drafts until exported, then immutable.** A flight entry is freely mutable in
   place until it is first included in a generated PDF export; at that point it is committed
   and every subsequent change appends a delta revision retaining the prior state. Committed
   entries are never UPDATEd or DELETEd. Export is the commit point because it is the moment
   the record is asserted to an authority. Revision history is device-local and backup-scoped.

5. **Never render a jurisdiction-dependent number without its jurisdiction.** Total flight time
   is universal. PIC, night, cross-country and instrument are not. An unlabelled "PIC: 142.3"
   is a bug.

## Reference documents

- `docs/jurisdiction-matrix.md` — how EASA, FAA and UK CAA differ, rule by rule. The
  authoritative source for which raw facts must exist. Read §4 and §9 before touching a model.
- `docs/entry-form.md` — how the flight entry screen should behave and why.
- `docs/adr/` — existing decisions, kept as history. Add a new one only for a decision that is
  genuinely hard to reverse and cannot live in a code comment.

Regulatory text in this file is a working summary, not a verified citation. Confirm against the
current instrument before it becomes load-bearing — AMC1 FCL.050 is amended by ED Decision
2025/002/R.

## Jurisdictions are profiles, not an enum

Do not write `enum Jurisdiction { easa, faa }` or a class per authority. Authorities are
**declarative profiles** in `assets/jurisdictions/`, resolved through a registry.

They form a lineage, not a flat set. UK Part-FCL is retained EU law that the CAA amends
independently — currently near-identical to EASA and diverging over time. Model that as
inheritance so a fix lands in one place. The same mechanism covers national variation *within*
EASA, since FCL.050 defers to the competent authority.

```yaml
id: uk.caa.part-fcl
extends: eu.easa.part-fcl
overrides:
  currency_rules: [uk.fcl060.passenger_recency]
  logbook_layout: uk_caa_amc1_fcl050
```

**Key on the issuing authority, not the licence type.** A pilot holds N licences; each licence
records its issuing authority; each authority resolves to a profile. One licence is marked
primary. "Let the user choose their primary jurisdiction" must be a settings value, never a
code path.

**Where declarative stops.** Thresholds, windows, counts and rule composition are data.
Deriving PIC from raw facts is real logic and belongs in Dart. YAML references **named, tested
primitives** rather than expressing the logic itself:

```yaml
pic_rule: faa.sole_manipulator     # vs easa.command_authority
night_rule: faa.civil_twilight_plus_hour
```

Acceptance test for the abstraction: *adding Transport Canada should require a YAML profile and
at most one new primitive — no changes to the engine, repositories or UI.*

Known divergences the primitives must handle, each needing a test:
- *PIC*: FAA §61.51 lets a sole manipulator log PIC while receiving instruction. EASA does not
  — that is dual. EASA has separate SPIC and PICUS concepts with countersignature rules.
- *Night*: differing definitions and differing currency windows.
- *Cross-country*: FAA generally needs a landing >50 nm from origin for rating credit; EASA's
  definition differs.
- *Instrument*: FAA splits actual/simulated; EASA logs IFR time.

When unsure which rule applies, **stop and ask** rather than guessing. A wrong currency
calculation is worse than no calculation.

## Architecture

```
lib/
  domain/          # Pure Dart. No Flutter imports, no I/O. Unit tested.
    model/         # Flight (raw facts), Aircraft, Crew, Licence, Authority, Aerodrome
    jurisdiction/  # Profile registry, YAML loader, inheritance resolution
    primitives/    # Named derivation functions referenced by profiles
    projection/    # Applies a resolved profile to a flight set -> derived columns
    currency/      # Rule engine: evaluates rule defs against a projected flight set
  data/            # Drift/SQLite, repositories, revision history
  io/              # Import/export adapters (ForeFlight, Garmin, CSV)
  export/          # PDF generation (AMC1 FCL.050 layout)
  ui/              # Flutter widgets, Riverpod providers
```

`domain/` must never import `package:flutter/*`. Enforced by `dart run tool/check_layering.dart`;
`dart run tool/check_domain_types.dart` enforces rule 3. Both run in CI.

## Currency rules are data

Versioned with an effective-from date, evaluated by a generic engine. Do not hard-code
thresholds in Dart.

```yaml
id: easa.fcl060.passenger_recency
jurisdiction: eu.easa.part-fcl
effective_from: 2011-11-08
requires:
  - count: 3
    of: takeoffs_and_landings
    within_days: 90
```

Each rule must record *which flights satisfied it*, so the UI can explain a result rather than
showing a red or green pill. "Not current" with no explanation is a bug.

## Multi-jurisdiction UX

- Totals, flight entry and dashboard render in the **primary** jurisdiction only.
- A flight whose derived values differ under a secondary licence gets a badge opening a
  side-by-side comparison. Do not render both columns everywhere; do not use a global toggle
  that silently changes what the numbers mean.
- Currency is the exception: show all held licences grouped, always.
- Export asks which jurisdiction explicitly. Never infer it.
- Adding a licence triggers a recompute plus a **"N past flights need more information" queue**.
  Never guess a missing discriminator, never silently default it.

## Import / export

- **ForeFlight**: `logbook_template.csv` — one CSV containing two tables (Aircraft, then
  Flights) plus typed custom fields in the form `[Hours]FieldName`. Column order and header
  names are load-bearing. Importing the same file twice creates duplicates in ForeFlight, so
  exports must be range-scoped.
- **Garmin Pilot**: CSV logbook export. Distinct from G1000/G3X SD-card *data logs*.
- Adapters map into the canonical internal model. Never let a vendor's field naming past `io/`.
  Vendor CSVs carry *derived* columns (e.g. a single "PIC" figure); import must reconstruct raw
  facts where possible and flag the flight for review where it cannot.
- Every import is a transaction with a preview step and a full undo. Never partially apply.
- Expect messy input: decimal hours vs `HH:MM`, ambiguous date formats, non-ICAO type codes.
  Reject with a clear per-row error rather than silently coercing.

## Printable logbook export

An electronic logbook is generally accepted provided it can be printed, signed and dated. Use
the `pdf` package, landscape A4.

Layout is **per profile**, not global — EASA uses the AMC1 FCL.050 twelve column groups; FAA
output is a different sheet. Treat the layout as a field of the jurisdiction profile.

Easy to get wrong:
- Running totals per page: *brought forward*, *this page*, *total to date*. These must reconcile
  exactly; test the arithmetic across a multi-page export.
- Signature and certification blocks must be present even when empty.
- Output must be deterministic — same input, byte-identical PDF — so it can be tested.

## Conventions

- Riverpod for state, `freezed` for models with several fields, `drift` for the database.
  Small single-value types are hand-written; `freezed` earns its place once a model has enough
  fields that a hand-written `==` would be easy to get wrong.
- Run `dart format .`, `flutter analyze` and `flutter test` before committing; all must be clean.
- `flutter` and `dart` are puro shims that work under PowerShell only, not Git Bash. Locally,
  code generation is `flutter pub run build_runner build --delete-conflicting-outputs` — plain
  `dart run build_runner` cannot find the Flutter SDK.
- Domain logic needs unit tests. Where two jurisdictions disagree, test both sides of the
  disagreement against the same input.
- Prefer adding a fixture to `test/fixtures/` over inventing test data inline.
- Cite the specific rule (e.g. `§61.51(e)(1)(i)`) in a comment where a line of code depends on
  it. Skip it where it would just be noise.
- Conventional commits (`feat:`, `fix:`, `refactor:`).
- Ask before adding a dependency. Prefer the standard library and packages already present.
- No cloud backend, account system or analytics without being asked. This is personal data
  under GDPR and the scope decision is deliberate.

## Deliberately out of scope for now

Flight recording (background GPS), cloud sync, instructor countersignature *workflow* (the data
model must still carry countersignature state — see rule 2), multi-user.
