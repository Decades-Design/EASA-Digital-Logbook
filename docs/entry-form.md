---
paths: ["lib/ui/entry/**", "lib/ui/flight_form/**"]
---

# Flight entry form

Design rules for the single most-used screen in the app. The governing principle:

> **The pilot describes the flight. The app derives the logbook.**

Never make the entry form mirror the AMC1 FCL.050 column layout. That layout is an *output*
format. Asking the pilot to fill in "PIC time" and "dual time" makes them do the jurisdiction
arithmetic the projection layer exists to do, and guarantees the two jurisdictions disagree with
each other in the stored data.

Equally: the pilot is the legal record-keeper, not the app. Every derived value must be
directly overridable without hunting for the control. Inference is a convenience, never a lock.

---

## 1. Field order

Aircraft first. It determines the shape of everything below.

1. **Aircraft** — registration only
2. **Date and route**
3. **Times**
4. **Crew** — the four-way selector, §4
5. **Take-offs and landings**
6. **Conditions**
7. **Remarks and endorsements**

Entering a registration resolves type, ICAO designator, class (SE/ME), SP/MP, category, engine
type, and the FAA complex / high-performance / tailwheel flags from the aircraft record. A C152
entry must never render a co-pilot field; an A320 entry must never render a solo field.

---

## 2. Times

### Block time is the legal figure under both EASA and FAA

Do not build an air-time-primary mode for the FAA profile. This is a common misconception and
the regulations do not support it:

- **EASA** (FCL.010, AMC1 FCL.050(g)(1)): aeroplanes and TMGs, from the moment the aircraft
  *first moves* for the purpose of taking off until it finally comes to rest.
- **FAA** (§1.1): from the moment the aircraft *moves under its own power* for the purpose of
  flight until it comes to rest after landing.

The genuine divergence is narrow: EASA includes movement under tow or pushback, the FAA does
not. It is nil for GA and material for airline operations. Model it as a per-profile primitive
(`block_start: easa.first_movement` vs `faa.own_power`) rather than two different time fields,
and only surface the distinction when the aircraft record indicates pushback operations.

### Field labels vary by aircraft category

Read the labels from the aircraft record, because EASA defines the boundaries differently per
category:

| Category | Start label | End label |
|---|---|---|
| Aeroplane / TMG / powered-lift | Off blocks | On blocks |
| Helicopter | Rotors start | Rotors stop |
| Airship | Released from mast | Secured on mast |

### Layout

```
Off blocks  [ 09:15 ]      On blocks  [ 10:45 ]        1:30
            0815Z                     0945Z            block

▸ Air time                                             (collapsed)
```

- Local entry with a persistent UTC echo beneath, or the inverse — driven by a user preference,
  not by jurisdiction. GA pilots think local; airline pilots think UTC. **UTC is what is
  stored**, always, per AMC1 FCL.050.
- Total block time computes live and is itself editable. If the pilot overrides it, store the
  override alongside the raw times; never silently rewrite the times to match.
- **Air time is a first-class optional field**, expandable inline. It carries take-off and
  landing times. It is not the legal total for either jurisdiction, but it is genuinely useful
  for maintenance reconciliation, rental billing, and Hobbs cross-checks — and some authorities
  outside the current three do use airborne time, so capturing it protects future profiles.
- Air time never feeds `totalTime` for the EASA or FAA profiles. It is stored, displayed,
  exportable, and otherwise inert.

---

## 3. Draft state

A flight can always be saved incomplete.

- **Save draft** is a peer of **Save**, not a hidden option.
- Drafts appear in the flight list with a distinct marker and are excluded from all totals,
  currency evaluation and exports.
- A drafts badge on the logbook screen shows the outstanding count.
- Validation runs on blur and annotates fields; it never blocks the save button. Someone logging
  a flight while walking back to the car must be able to get it down and finish later.
- A draft that has been open beyond a configurable period prompts once, then stops nagging.

---

## 4. Crew — the four-way selector

One question: **who else was on board?**

```
[ Just me ]  [ With an instructor ]  [ With another pilot ]  [ With passengers ]
```

Each selection expands inline. The expanded contents below are the complete field sets. Every
one of these fields exists to resolve a discriminator in `docs/jurisdiction-matrix.md` §9 — none
is decorative, and none can be inferred later if omitted now.

**Passengers are never counted.** No jurisdiction derives a logged quantity from the number of
people on board — only from whether anyone else was aboard at all. FAA solo
time requires sole occupancy (§61.51(d)), as does student PIC logging (§61.51(e)(4)), and
both tests are binary. The only place a headcount carries regulatory weight is the six-occupant
limit on cost-shared flights, which is an operational-legality question and not a logbook
parameter. A stepper here would be input effort that feeds nothing.

So the model is boolean throughout:

- **4A asserts sole occupancy.** Selecting it *is* the statement that nobody else was aboard.
  No control appears.
- **4D asserts passengers.** Selecting it *is* the toggle. No control appears.
- **4B and 4C carry a passengers-on-board toggle**, because another pilot or an instructor can
  be aboard alongside passengers.

`soleOccupant`, `carryingPassengers` and the occupant roles are derived from the selection, not
entered. Note that "passenger" is a role, not a headcount: an instructor or
examiner on board is not a passenger for FCL.060(b)(1) purposes, and neither is required
crew under the FAA. Deriving from roles makes that exclusion automatic rather than a special
case in every currency rule.

⚠️ Unresolved: whether a non-required second pilot in a single-pilot aeroplane counts as a
passenger under EASA. Store the role; do not force the question.

---

### 4A. Just me

The simplest path. Resolves sole occupancy, sole manipulator, and command in one tap. No fields
in the base case.

Derives: EASA PIC = block. FAA PIC = block (sole manipulator, rated). FAA solo = block.

**If the pilot's licence profile indicates student status**, add:

| Field | Type | Purpose |
|---|---|---|
| Solo endorsement held | toggle, default on | FAA §61.51(e)(4) requires a §61.87 endorsement for a student to log PIC |
| Endorsing instructor | autocomplete | Endorsement provenance |

---

### 4B. With an instructor

Second question, always shown, because it is the dual/SPIC discriminator:

```
What was the arrangement?
[ I was receiving instruction ]   [ I was in command, instructor observing only ]
```

The second option is only offered when the licence profile makes it available — SPIC applies to
student pilots under FCL.020, and the instructor must not have influenced or controlled the
flight. If the pilot picks it, show that condition as an explicit affirmation, not fine print.

**Fields shown for both arrangements:**

| Field | Type | Notes |
|---|---|---|
| Instructor name | autocomplete | Persisted; recent instructors pinned |
| Instructor licence / certificate number | text | Required for EASA countersignature and FAA endorsements |
| Certificate expiry | date | FAA §61.51(h)(2)(ii) requires expiry or recent-experience end date on endorsements. Not required by EASA — hide when no FAA licence is held |
| Purpose of flight | select | See list below. Drives the mandatory column 12 entries |
| I was sole manipulator | toggle, default on | FAA PIC hinges on this; the instructor may have flown part of the flight |
| Manipulation time | duration | Shown only when the toggle is off. Enables a partial FAA PIC claim |
| Passengers on board | toggle, default off | The instructor is not a passenger. ⚠️ No passengers may be aboard when flying under instructor supervision to regain FCL.060(b)(1) recency — warn, do not block |

**Purpose options** (each triggers its own downstream behaviour):

- Training — general
- Skill test → adds examiner number, result, and forces a remarks entry
- Proficiency check → same, plus rating affected
- SEP/TMG revalidation refresher → mandatory instructor name and signature in remarks per
  AMC1 FCL.050; also flags the entry to the SEP currency rule
- FAA flight review (§61.56)
- FAA IPC (§61.57(d))
- Instrument training toward a licence or rating → mandatory remarks entry per AMC1 FCL.050

**Countersignature block** — always present, never required to save:

| Field | Type | Notes |
|---|---|---|
| Signature | draw / defer | Deferred entries queue under "awaiting countersignature" |
| Signed at | timestamp | Captured automatically on signing |

Mark deferred entries visibly. Uncountersigned SPIC or PICUS time is not defensible as PIC time
under AMC1 FCL.050, so the projection must return it as *not creditable, with reason* — never
silently as zero, and never silently as valid.

Derives, for "receiving instruction": EASA dual = block, EASA PIC = 0. FAA dual received =
block, FAA PIC = manipulation time if rated. For "in command, observing only": EASA logs SPIC in
the PIC column pending countersignature; FAA logs PIC.

---

### 4C. With another pilot

The richest path, and the one that carries the FAA/EASA divergence most sharply. Two separate
questions — they are not the same question:

```
Who was in command?      [ Me ]  [ Other pilot ]
Who was flying?          [ Me ]  [ Other pilot ]  [ Both — split ]
```

| Field | Type | Notes |
|---|---|---|
| Other pilot name | autocomplete | Persisted |
| Other pilot licence number | text | Needed for PICUS countersignature |
| Multi-pilot operation | toggle | Pre-filled from the aircraft record; overridable for ops that require two pilots by regulation rather than by type certificate |
| My manipulation time | duration | Shown when "Both — split" is selected. **This is what makes a mid-flight takeover loggable** |
| Other pilot's role | select | Required crew / Not required crew / Safety pilot |
| Claim PICUS | toggle | Only offered when MP is on and command is "Other pilot" |
| PIC intervention was not required | affirmation | Shown when PICUS is claimed — this is the substantive condition |
| Safety pilot for my simulated instrument | toggle | Shown when simulated instrument time > 0. Records the name per §61.51(b)(1)(v) |
| Passengers on board | toggle, default off | Required crew are not passengers |

**Divergence warning.** When the combination produces materially different results, show it
inline rather than leaving the pilot to discover it in the totals:

> Single-pilot aircraft, another pilot in command, you not flying — EASA records no time for
> this flight. Your FAA licence may permit logging it.

This case is real and counterintuitive: a second pilot in a single-pilot aeroplane logs nothing
under EASA regardless of what they did.

**Safety pilot** deserves special note. Under the FAA, a safety pilot is a required crewmember
and may log PIC or SIC depending on who was acting as PIC. EASA has no equivalent category.
Capture the arrangement rather than the conclusion: who was acting PIC, and whether the safety
pilot was manipulating.

---

### 4D. With passengers

No fields. Selecting this path is the assertion that passengers were carried and that no other
pilot was aboard; command is self by definition.

Night passenger carriage is **derived**, not asked — passengers aboard plus night time greater
than zero. Do not add a toggle for something already implied by two values the form has. It
feeds FCL.060(b)(3) and §61.57(b), both of which the currency engine evaluates on its own.

**Soft currency check** — applies here and to 4B/4C whenever the passengers toggle is on. On
save, if the pilot was not passenger-current at the flight date,
show a non-blocking note: *"You may not have met FCL.060(b) passenger recency on this date."*
Never block the save and never alter the entry. The pilot's record is the pilot's record; the
app reports, it does not adjudicate. Link the note to the currency screen so the reasoning is
inspectable.

---

## 5. Take-offs and landings

**Take-offs and landings are separate counts.** Do not derive one from the other and do not
offer a single combined figure. A pilot who took over in flight has zero take-offs and one
landing; a safety pilot who handled only the departure has one take-off and zero landings. Both
are ordinary situations and both are currently mis-recorded by most logbook software.

They are separately required by FAA §61.57(a), which counts take-offs and landings, and by EASA
column 8, which counts landings as pilot flying by day and night.

```
Take-offs      Day [ − 1 + ]      Night [ − 0 + ]
Landings       Day [ − 1 + ]      Night [ − 0 + ]
  ▸ 1 full-stop                                    (shown when FAA licence held)
```

**No approach counter here.** AMC1 FCL.050 has no approach column, and EASA imposes no
obligation to record approaches. FCL.060(b)(1) is phrased as take-offs, approaches and landings,
but that is a recency condition, not a logging requirement — an approach is implicit in every
landing, so the landing count already satisfies it. Approach recording is an FAA instrument
concern and belongs in §6, gated accordingly.

- Values are **pre-filled** from the twilight computation against the route and block times, and
  are **immediately editable**. No condition gates the editability. No confirmation dialog. The
  steppers are the primary interface, not an override buried behind a disclosure triangle.
- Label them as the pilot's own — "your landings" — because AMC1 FCL.050 column 8 counts
  landings as pilot flying, not landings the aircraft made.
- Full-stop count appears as a sub-row when an FAA licence is held and night landings > 0, since
  FAA night currency requires full-stop landings specifically. Pre-fill with 1 (the final
  landing at the arrival aerodrome is necessarily full-stop) and let the pilot correct it.
- When the pilot edits a pre-filled value, store both the inferred and the entered value. The
  divergence is diagnostic information, not an error.

---

## 6. Conditions

Show only what the flight could plausibly have had, driven by aircraft equipment and the
licences held.

| Field | Shown when | Notes |
|---|---|---|
| Night time | Always | Pre-filled from twilight computation; editable |
| IFR time | EASA licence held | Operational condition — time under IFR, regardless of meteorological conditions |
| Actual instrument | FAA licence held | Time solely by reference to instruments, §61.51(g)(1) |
| Simulated instrument | FAA licence held | Separate condition; reveals the safety pilot field in 4C |
| Approaches flown | FAA IR held, or FAA IR training in progress | Count, plus type and location **per approach** — §61.51(g)(3) requires both to be recorded for §61.57(c) currency. Not shown to an EASA-only pilot |
| Holding / course tracking | FAA IR held, or FAA IR training in progress | §61.57(c) requires these alongside the six approaches and they are routinely forgotten |

**Approaches are an FAA-only field.** EASA IR revalidation is by annual proficiency check, not by
counting approaches, so an EASA-only pilot never needs the control. If an EASA pilot wants to
record approaches for their own purposes, that belongs in remarks — AMC1 FCL.050 permits column
12 to be used at the holder's discretion, and recent amendments reference recording PBN and RNP
APCH approaches there. Optional, free-text, never a structured requirement. ⚠️ Verify the
current AMC1 wording on this before implementing; the PBN remarks provision appeared in draft
amendment material and its status in the adopted text needs checking.

**Do not conflate IFR time with instrument time.** They are different quantities and a flight
conducted under IFR entirely in VMC produces full EASA IFR time and zero FAA instrument time.
Two fields, two primitives, never one field rendered twice.

---

## 7. Derivation strip

A single line above the save controls, showing what the entry will produce:

```
1:30 block  ·  EASA: Dual 1:30  ·  FAA: PIC 1:30, Dual 1:30
```

This is the accuracy mechanism. A pilot who expected PIC under both will see the discrepancy
before saving rather than three months later. It also teaches the divergence passively, which
matters for users who hold one licence and have never encountered the other system.

Tapping it expands to the full per-jurisdiction breakdown with, for each derived value, the rule
that produced it. Every number must be traceable to a named primitive.

---

## 8. Overrides

Any derived value may be overridden. This is not a concession — the pilot is legally responsible
for the accuracy of the record and the rules engine will sometimes be wrong.

Requirements:

- An override records a reason and lands in the revision history **as an override**, not as a
  raw value. The inferred value is retained.
- Overridden values render with a persistent marker on the flight and in the export.
- Overrides never propagate. Editing an override later creates a new revision.
- Never silently overwrite a pilot's entered value when a rule or profile is later updated.
  Recompute inferred values; leave overrides alone and flag them for review.

---

## 9. Speed

The interaction that matters most is **repeat last flight**, with the route optionally reversed.
Training and circuit flying are highly repetitive, and for a large share of entries the correct
experience is confirming five pre-filled fields and tapping save.

Secondary: recent aircraft, recent aerodromes and recent instructors pinned to the top of their
respective autocompletes, scoped per pilot rather than globally.