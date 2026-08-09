# Authoring a currency rule

#54. This is the artefact meant to survive contact with future-you at 11pm, trying to add a
rule and unsure what a field means. If something here goes stale, fix the doc in the same PR
that changes the shape it's describing — see `lib/domain/currency/currency_rule_yaml.dart` for
the parser this document is describing, and `assets/rules/schema/currency-rule.schema.json` for
the JSON Schema every file here is validated against (`dart run tool/check_currency_rules.dart`,
also run in CI).

**Why YAML at all.** CLAUDE.md's "currency rules are data" section is the reasoning: thresholds,
windows, counts and rule composition are data; deriving a quantity from raw facts is real logic
and belongs in Dart. A rule file should never need a matching change in
`currency_rule_evaluator.dart` — if it does, the schema is missing an expression, which is a
bigger conversation than adding one rule.

## Where a rule file lives

`assets/rules/<authority>/<short_name>.yaml`, e.g. `assets/rules/easa/fcl060_b1_passenger_recency.yaml`.
The filename is not load-bearing (nothing parses it), but keep it recognisably tied to the
citation so a directory listing is itself useful.

## Top-level fields

| Field | Required | Meaning |
|---|---|---|
| `id` | yes | Stable identity across every version of this rule, e.g. `easa.fcl060.b1_passenger_recency`. This is what `CurrencyRuleLoader.resolve` is called with — a caller asks for a rule by `id` and an evaluation date, never by filename. Never changes once a rule exists, even when the regulation is renumbered; add a comment noting the renumbering instead. |
| `jurisdiction` | yes | The jurisdiction profile id this rule belongs to, e.g. `eu.easa.part-fcl`, `us.faa.part61` — see `assets/jurisdictions/`. |
| `citation` | yes | The regulation this rule implements, e.g. `"FCL.740.A(b)(1)"`, `"§61.57(c)"`. Shown to the pilot alongside the result — see CLAUDE.md's citation convention. |
| `effective_from` | yes | `YYYY-MM-DD`. The date this *version* of the rule took effect. See "When a regulation changes" below. |
| `expires_on` | no | `YYYY-MM-DD`. The date this version was superseded. Omit while a version is still current. |
| `requirement` | yes | The rule's logic tree — see below. |

## The requirement tree

A `requirement` is one of five `kind`s. `flight_event_count`, `flight_event_hours` and
`held_record_currently_valid` are leaves; `all_of` and `any_of` compose other requirements
(including each other) to arbitrary depth.

### `flight_event_count` / `flight_event_hours`

"N of some countable thing, within a window, optionally narrowed by conditions."

```yaml
kind: flight_event_count   # or flight_event_hours
event: landings            # see the event list below
count: 3                   # flight_event_count only
hours: 6                   # flight_event_hours only — decimal, e.g. 6.5
window: { kind: rolling_days, days: 90 }
conditions:                # optional; omit entirely for "no narrowing"
  - kind: aircraft_match
    level: same_type_or_class
```

Events, exactly the ones a rule implemented so far needs — adding a new one is a schema change,
not something a rule author invents inline:

`landings`, `takeoffs`, `approaches`, `holding_procedures`, `tracking_performed`,
`faa_flight_review`, `faa_instrument_proficiency_check`, `easa_class_rating_proficiency_check`.

The last three are "alternative means of compliance" — a flight tagged as *being* a flight
review, an IPC, or a class-rating proficiency check (`Flight.alternativeComplianceEvents`),
rather than an ordinary count of landings or hours.

### `held_record_currently_valid`

"Is there a currently-valid held document of this kind." No window — validity is a range on the
held record itself (`HeldRecord.validFrom`/`validUntil`), not something the rule computes.

```yaml
kind: held_record_currently_valid
held_record_kind: medical_certificate.easaClass2
```

`held_record_kind` is a string key, not an enum — it has to match whatever the pilot-record
layer projects into a `HeldRecord.kind` (see `lib/domain/pilot_record/held_qualification_records.dart`
and `medical_certificate_validity.dart` for the projections currently in use). There is no
compile-time check that the string is spelled right; a typo here silently never matches anything,
which is why every rule needs a test asserting it against a held record of the right kind.

### `all_of` / `any_of`

Composition, matching plain English: every sub-requirement must hold, or at least one must.

```yaml
kind: any_of
of:
  - kind: flight_event_count
    event: landings
    count: 3
    window: { kind: rolling_days, days: 90 }
  - kind: held_record_currently_valid
    held_record_kind: proficiency_check
```

Nest freely — `assets/rules/easa/fcl740a_sep_land_revalidation.yaml` is `any_of` a five-way
`all_of` and a single leaf, and is the deepest example in the current rule set. When a
composite fails, `RuleResult.components` carries each sub-result, so a caller can point at
exactly which branch is missing something instead of showing one opaque "not current" — see
CLAUDE.md's "not current, with no explanation, is a bug."

## Windows

Two kinds, because "3 in the preceding 90 days" and "24 calendar months" are genuinely
different shapes, not the same thing spelled two ways:

```yaml
window: { kind: rolling_days, days: 90 }
```

```yaml
window:
  kind: calendar_months
  months: 24
  anchor: held_record_expiry          # optional; default is evaluation_date
  anchor_held_record_kind: eu.easa.sep_class_rating   # required when anchor is held_record_expiry
```

`calendar_months` runs to the end of a specific month regardless of which day of the month the
anchor fell on — 24 calendar months, not 730 days. Use it for anything the regulation states in
months (flight reviews, medical validity, rating revalidation); use `rolling_days` for anything
the regulation states as a day count (the 90-day passenger-carrying rules).

`anchor: held_record_expiry` is for a window that runs against a *document's* expiry rather
than against today — FCL.740.A(b)(1)'s "within the 12 months preceding the rating's expiry" is
the current example. This window does not slide as the evaluation date changes; it is fixed
once the anchoring record's expiry is known. Leave `anchor` off (or write
`evaluation_date` explicitly) for the ordinary case.

## Conditions

Narrow *which flights* count (`aircraft_match`, `capacity`, `instructor_aboard`) or *which part*
of a qualifying flight counts (`day_night`, `landing_type`). Optional; omit `conditions`
entirely for "every flight of the right event type, unnarrowed."

| `kind` | Field | Values | What it does |
|---|---|---|---|
| `aircraft_match` | `level` | `same_type`, `same_class`, `same_type_or_class`, `class_or_type_if_required` | Gates the flight against the aircraft the recency question is being asked about. `class_or_type_if_required` is `§61.57(a)`'s own wording — same class ordinarily, same *type* when the reference aircraft is itself type-rated. |
| `day_night` | `value` | `day`, `night` | Narrows a landings/takeoffs count to one half of `CircuitCounts`. |
| `landing_type` | `value` | `full_stop`, `touch_and_go` | As above, the other axis of `CircuitCounts`. |
| `capacity` | `value` | `command_authority` | Gates on a fact from `PilotCapacity` — currently only whether the pilot held command authority. |
| `instructor_aboard` | — | — | Gates on `PilotCapacity.instructor` being present, in any capacity. No value field: it is a pure presence check. |

A rule needing a new condition kind or a new `aircraft_match`/`capacity` value is a schema
change (`lib/domain/currency/flight_condition.dart`, the YAML parser, and the JSON Schema, in
that order), not something to approximate with an existing one.

## Worked example: citation to YAML

Starting point, `FCL.060(b)(1)`:

> A pilot shall not act as PIC or co-pilot of an aeroplane carrying passengers unless that pilot
> has carried out, in the preceding 90 days, at least 3 take-offs, approaches and landings, in
> an aeroplane of the same type or class.

Steps, in the order you'd actually do them:

1. **Pick the `id`.** `easa.fcl060.b1_passenger_recency` — jurisdiction, citation stub, plain
   English. Stable forever once chosen.
2. **Pick the `event`.** The regulation names three things (take-offs, approaches, landings),
   but `docs/entry-form.md` §5 is explicit this is a *recency condition*, not a logging
   requirement, and a landing implies the approach and take-off that produced it — so `landings`
   alone is the right event, not three separate counts. (Contrast `§61.57(a)`, which genuinely
   needs take-offs and landings counted independently, because a pilot who took over in flight
   has zero take-offs and one landing.) This judgement call is worth a comment in the file, not
   just in this doc — see the real file for the one actually written.
3. **Pick the `window`.** "Preceding 90 days" is `{ kind: rolling_days, days: 90 }` — a day
   count, not a month count.
4. **Pick the `conditions`.** "Same type or class" is `aircraft_match` at `same_type_or_class`.
5. **Assemble:**

```yaml
id: easa.fcl060.b1_passenger_recency
jurisdiction: eu.easa.part-fcl
citation: "FCL.060(b)(1)"
effective_from: 2011-11-08
requirement:
  kind: flight_event_count
  event: landings
  count: 3
  window:
    kind: rolling_days
    days: 90
  conditions:
    - kind: aircraft_match
      level: same_type_or_class
```

6. **Write the comment.** Every rule file in `assets/rules/` opens with a comment explaining any
   non-obvious modelling choice — why this event and not that one, what was deliberately scoped
   out, which other rule this one pairs with. The YAML says *what*; the comment says *why*, per
   CLAUDE.md's "put the reasoning in a comment beside the code it explains."
7. **Validate.** `dart run tool/check_currency_rules.dart` checks the file against both the
   schema and the Dart parser.
8. **Test it.** Every rule needs at least one test exercising it satisfied and one unsatisfied —
   see `test/domain/currency/golden_logbook_test.dart` (#53) for a shared fixture logbook that
   most new rules can be evaluated against directly, and any file under
   `test/domain/pilot_record/*_rules_test.dart` for a rule-specific example when the shared
   fixture doesn't fit (a rule needing its own held-record shape, for instance).

## When a regulation changes

**Add a new rule file — or a new document in the same file, if your loader path expects one
document per `id` per file, which this codebase's does not enforce either way — with a new
`effective_from`. Never edit an existing version's dates, and never delete a superseded
version.**

`CurrencyRuleLoader` groups every loaded rule by `id`, sorts by `effective_from`, and resolves
"the version in force on this date" per evaluation — so a flight from 2019 is always evaluated
against the rule that was actually in force in 2019, no matter how many times the regulation has
changed since (#41). That guarantee only holds if superseded versions stay loaded forever.

Concretely, when `FCL.060(b)(1)`'s 90-day figure changes to 60 days effective 2027-01-01:

1. Add `expires_on: 2026-12-31` to the *existing* file — it is not deleted, not edited beyond
   this one field.
2. Add a **new** file (or a new list entry, if this rule's versions are ever split across
   physical files — not yet the case for anything in this directory) with the same `id`, the new
   `effective_from: 2027-01-01`, and the new `days: 60`.
3. Both versions carry the citation — cite the specific sub-paragraph or amending instrument if
   the two versions read differently (`ED Decision .../.../R`, an amendment number), so a reader
   can tell at a glance why two files share an `id`.
4. Two versions of the same `id` may never share an `effective_from` — `CurrencyRuleLoader`'s
   constructor throws if they do, since nothing would then say which one governs.

The rule of thumb: a rule file, once it has ever been evaluated against a real flight, is as
immutable as the flight itself. Editing history out from under a past evaluation is exactly the
"derived quantity silently wrong with no way to recompute" failure CLAUDE.md rule 1 warns about
for flights — the same logic applies to the rules that read them.
