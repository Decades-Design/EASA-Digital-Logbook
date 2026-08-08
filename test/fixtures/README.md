# test/fixtures/

Fixture data for domain, projection and export tests. Loaded via
`loadFixture(category, name)` in `fixture_loader.dart`, which resolves
`test/fixtures/<category>/<name>.yaml` relative to the package root. M1 adds
typed per-model decoders on top of this loader; it does not replace it.

## Subdirectories

- `flights/` — raw-fact flight entries, one YAML file per flight. Every field
  is a fact the pilot could attest to at the time of flight — never a
  derived quantity. See "Rule 1" below.
- `capacities/` — `PilotCapacity` scenarios, one YAML file per operating
  arrangement, decoded by `decoders/pilot_capacity_fixture.dart`. Together they
  cover every case issue #13 requires the model to tell apart, and issues #18
  and #19 assert real PIC and dual values against them. Each file's expected
  projection outcomes live in its header comment, never as stored keys.
  `capacities/malformed/` holds fixtures that are deliberately broken, to prove
  the decoder fails loudly instead of substituting a default.
- `aircraft/` — aircraft definitions (registration, type, category/class,
  FSTD qualification level where relevant).
- `importers/` — real vendor CSV samples (ForeFlight `logbook_template.csv`,
  Garmin Pilot logbook exports) used to test `io/` adapters against actual
  export shapes, not hand-rolled approximations of them.
- `pdf/` — expected export output for golden tests against the printable
  logbook export (AMC1 FCL.050 layout and friends). Byte-identical output is
  part of the export's contract; these fixtures are what golden tests diff
  against.

## Provenance

Where a fixture in `importers/` or `pdf/` originated from a real ForeFlight
or Garmin Pilot export, the fixture (or a sibling `.provenance.md` file)
must say so, and must confirm that personal data — pilot name, licence
number, aircraft owner details, exact home-base coordinates — was scrubbed
or replaced with fictional-but-plausible values before the file was
committed. Do not commit an export "as downloaded."

## The YAML quoting caveat

Quote aerodrome identifiers and anything time-shaped.

Dart's `yaml` package (used by the loader) implements the YAML **1.2 core
schema**, not 1.1. That removes most of the classic YAML footguns: 1.1's
sexagesimal number form (`1:30` parsing as the integer 90) and the extended
`yes`/`no`/`on`/`off` boolean set are gone under 1.2 — only `true`/`false`
(and a couple of case variants) are booleans, and `1:30` is just a string.

That should make quoting optional. It doesn't, because a logbook fixture is
made almost entirely of the two shapes that *do* still collide:

- **Bare `NO`** — the ICAO/callsign-adjacent aerodrome code for Norway
  reads, in a YAML scanner's case-insensitive boolean set under some
  loaders and in any reader's mental model, as "no." Even where the 1.2
  core schema itself doesn't treat it as false, relying on that is relying
  on which schema variant a future loader or a copy-pasted snippet happens
  to implement.
- **Bare `1:30`** — hours-and-minutes duration notation, which is exactly
  the sexagesimal shape 1.1 would silently coerce to the integer 90. Some
  elapsed durations *are* raw facts and are stored: actual and simulated
  instrument time are attested by the pilot, not computed from anything
  else, and `docs/jurisdiction-matrix.md` §9 lists both among the facts a
  jurisdiction's numbers cannot be recovered without. What Rule 1 below
  forbids is storing a *derived* duration — PIC, night, cross-country and
  friends, which are projections of the raw facts, not facts. Either way,
  timestamps, remarks and free-text fields can also contain a `HH:MM`-shaped
  substring, and an unquoted scalar starting with digits and a colon is
  parsed as a plain string only by convention, not by guarantee across
  tooling. Store durations in unambiguous units (`_minutes`) and quote
  anything that reads as `HH:MM`.

So: quote every aerodrome identifier, every field that starts with digits
and a colon, and every field that could ever be typed as `NO`, `YES`, `ON`
or `OFF` by a human filling in the fixture. It costs nothing and removes an
entire class of "the fixture parsed to something other than what's on the
page" bugs.

## Rule 1 reminder: raw facts only

Per `CLAUDE.md` rule 1 and ADR-0001, a fixture stores raw facts — never a
derived quantity. Do not add `pic_time`, `dual_time`, `night_time`,
`cross_country_time`, `total_time`, or any other projection output as a
YAML field, even for convenience in eyeballing a fixture. Expected
projection outputs belong in one of two places:

1. A YAML comment directly above the discriminators that produce them
   (see `flights/faa_easa_divergence.yaml` for the pattern), or
2. The test that asserts the projection, once the projection engine exists.

Never as a stored field — a projection cannot be re-derived from a number
that overwrote the facts it came from.
