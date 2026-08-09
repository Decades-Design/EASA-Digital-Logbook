# EASA Digital Logbook

A Flutter (iOS + Android) pilot logbook and currency tracker, built for a pilot holding licences
under **more than one authority** — today EASA (primary) and FAA (secondary), with UK CAA
planned. The app is the pilot's legal record of flight time, so data integrity is treated as a
hard requirement throughout.

> **Not yet a substitute for a compliant paper or electronic logbook.** The printed EASA export
> (AMC1 FCL.050 layout) has not been validated end to end and this app has had no regulatory
> audit. Do not rely on it as your sole record until the PDF export milestone (M6) is complete
> and you have verified it against your own requirements.

## What it does

- Stores every flight as **raw facts only** — who was flying, in what capacity, under what
  conditions — never a precomputed "PIC time" or "night time" column. Every derived quantity
  (PIC, dual, SPIC, PICUS, night, cross-country, instrument, single/multi-pilot time) is computed
  at read time, per jurisdiction, from those facts.
- Supports EASA/UK Part-FCL and FAA Part 61 today, added as **declarative profiles** rather than
  hardcoded logic, so a third authority (Transport Canada, CASA, ...) is a new YAML file and at
  most one new primitive function, not a rewrite.
- Surfaces every jurisdiction's currency status side by side, with an explanation of which
  flights satisfy each rule — never a bare red or green pill.
- Exports a printable EASA logbook (AMC1 FCL.050, twelve column groups, landscape A4) once M6
  lands, with running totals that reconcile exactly across pages.

## Why it's built this way

The full reasoning lives in [`CLAUDE.md`](CLAUDE.md) and the [architecture decision
records](docs/adr/) — this is the short version:

- **Raw facts only, never a derived quantity** ([ADR-0001](docs/adr/0001-raw-facts-only.md)). A
  flight row cannot express "PIC time" because whether time counts as PIC depends on which
  authority is asking. Store the discriminators (command authority, sole manipulator, instructor
  presence and capacity, countersignature state, ...); derive the number per jurisdiction, per
  read.
- **All stored times are UTC** ([ADR-0002](docs/adr/0002-utc-only.md)), enforced by a dedicated
  `UtcInstant` type — a naive local `DateTime` cannot be constructed in the domain layer at all.
- **Entries are drafts until exported, then immutable**
  ([ADR-0003](docs/adr/0003-draft-until-exported.md)). A flight is freely editable until it is
  first included in a generated PDF; after that, every change appends a retained revision rather
  than overwriting the record.
- **Currency rules are versioned data, not Dart logic**
  ([ADR-0004](docs/adr/0004-rules-as-data.md)), evaluated by one generic engine against named,
  tested primitive functions.
- **Jurisdictions are profiles, not an enum.** They form a lineage — UK Part-FCL is retained EU
  law the CAA amends independently, modelled as `extends: eu.easa.part-fcl` with overrides —
  rather than a flat set of hardcoded cases.

See `docs/jurisdiction-matrix.md` for the rule-by-rule EASA/FAA/UK CAA comparison this is built
against, and `docs/amc1-fcl050-layout.md` for the printed logbook sheet the export reproduces.

## Deliberately out of scope (for now)

Background flight recording (GPS-based), cloud sync, an account system, analytics, and
instructor countersignature *workflow* (the data model carries countersignature state; routing a
signature request to an instructor does not exist yet). None of these are rejected outright —
they're just not being built until there's a reason to. Triage a feature request against this
list and against the milestone plan before assuming it's missing by oversight.

## Building and running

This is a solo project built with [puro](https://puro.dev/) rather than a bare Flutter SDK
install, and the `flutter`/`dart` shims it installs work under **PowerShell only** — not Git
Bash, not cmd.exe.

```powershell
flutter pub get

# Code generation (freezed models). Run this after pulling changes that touch
# lib/domain/model/, and after editing any @freezed class yourself.
flutter pub run build_runner build

# Format, analyze, and the two custom architecture guards — all four also run in CI.
dart format --set-exit-if-changed .
flutter analyze --fatal-infos
dart run tool/check_layering.dart      # lib/domain/ must be pure Dart, no Flutter imports
dart run tool/check_domain_types.dart  # lib/domain/ must never construct a naive DateTime

flutter test
```

An optional pre-commit hook mirrors the fast checks above (not the full test suite) so failures
surface before you push rather than after — see [`tool/hooks/`](tool/hooks/) to install it. It is
opt-in; nothing breaks if you skip it, since CI runs the same checks regardless.

A new contributor should be able to clone the repo, run the commands above, and have a clean,
fully tested build using only this README.

## Project layout

```
lib/
  domain/   Pure Dart. No Flutter imports, no I/O. Unit tested. See CLAUDE.md.
  data/     Drift/SQLite persistence, repositories, revision history.
  io/       Import/export adapters (ForeFlight, Garmin, CSV).
  export/   PDF generation (AMC1 FCL.050 layout).
  ui/       Flutter widgets, Riverpod providers.
```

`docs/adr/` records decisions that were genuinely hard to reverse; a decision that can live in a
code comment usually does instead — see `CLAUDE.md` for the full set of project conventions,
including the non-negotiable domain rules that govern anything under `lib/domain/`.
