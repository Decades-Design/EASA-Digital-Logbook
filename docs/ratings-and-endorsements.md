# Ratings, Class Ratings and Endorsements — EASA / FAA / UK CAA

Aeroplane category only. Licence level (PPL/CPL/ATPL) is irrelevant to everything below —
these are the qualifications that attach to the *aircraft* or to a *privilege*, not to the
licence tier.

Companion to `docs/jurisdiction-matrix.md`, which covers logging and currency. This document
covers what a pilot must hold in order to fly a given aeroplane, and what the app must model to
tell them whether they hold it.

> **Status: working summary, not legal advice.** Verified August 2026 against the EASA Class and
> Type Rating & Licence Endorsement List (12.02.2026 revision), 14 CFR Part 61, and CAA GA
> licensing pages. Rows marked ⚠️ need confirmation before becoming load-bearing.

---

## 1. The structural difference

This is the thing to get right before modelling anything:

| | EASA / UK | FAA |
|---|---|---|
| Where qualifications live | **On the licence** — printed, issued by the authority | **In the logbook** — an instructor's endorsement, nowhere on the certificate |
| Aircraft-feature qualification | "Differences training", recorded and signed in the logbook, no licence change | "Endorsement", signed in the logbook |
| Expiry | Class and type ratings **expire** (12 or 24 months) | Endorsements and ratings **never expire**; currency is separate |
| Who decides you're qualified | Examiner (rating) or instructor (differences) | Instructor, for endorsements |

Consequence for the data model: an EASA qualification is a record with an expiry date that feeds
the currency engine. An FAA endorsement is a permanent record with no expiry that feeds an
eligibility check only. Same table, two very different lifecycle behaviours — model expiry as
nullable rather than forcing a date.

---

## 2. Category and class ratings

### FAA — category/class on the certificate

| Rating | Abbreviation |
|---|---|
| Airplane Single-Engine Land | ASEL |
| Airplane Single-Engine Sea | ASES |
| Airplane Multi-Engine Land | AMEL |
| Airplane Multi-Engine Sea | AMES |

Engine type (piston vs turboprop) does **not** split the class. A single-engine turboprop is
still ASEL. Contrast with EASA, where SET is its own class rating.

Limitation worth modelling: *centerline thrust only*, which restricts an AMEL holder to
centreline-thrust twins. It is a limitation printed on the certificate, not a separate rating.

### EASA / UK — class ratings for single-pilot non-complex aeroplanes

From the EASA Class and Type Rating & Licence Endorsement List:

| Class rating | Covers |
|---|---|
| SEP (land) | Single-engine piston, landplane |
| SEP (sea) | Single-engine piston, seaplane |
| SET (land) | Single-engine turboprop, landplane |
| SET (sea) | Single-engine turboprop, seaplane |
| MEP (land) | Multi-engine piston, landplane |
| MEP (sea) | Multi-engine piston, seaplane |
| TMG | Touring motor glider — powered sailplanes with an integrally mounted, non-retractable engine and non-retractable propeller, capable of taking off and climbing under their own power |

Everything else is a type rating. There is no multi-engine turboprop class rating — those are
individually type rated.

**Aircraft within a class are not listed individually** unless specific provisions exist. But
note the asymmetry: SEP and MEP aircraft sit in the class by default, whereas all aircraft
within the SET class ratings require differences training unless the list says otherwise.

⚠️ MEP has a similar catch: the list states all aircraft within MEP require differences training
unless indicated otherwise. So moving between MEP types is not free the way moving between SEP
types often is.

### UK national licences

The UK retains national licences alongside UK Part-FCL, with their own class structure —
**SSEA** (Simple Single Engine Aeroplane) and **SLMG** (Self-Launching Motor Glider) on the
NPPL. Out of scope for a Part-FCL/FAA logbook, but relevant if the app ever supports UK national
licence holders. ⚠️ The October 2025 UK licensing changes also allow three-axis microlight hours
to count toward PPL training and SEP revalidation — a UK-only crossover with no EASA equivalent.

---

## 3. Aircraft-feature qualifications

This is the section the app actually needs, because these are derivable from aircraft
attributes.

### FAA — §61.31 endorsements

| Endorsement | Trigger | Reference |
|---|---|---|
| **Complex** | Retractable landing gear, flaps, **and** a controllable-pitch propeller. For seaplanes, flaps and controllable-pitch propeller (floats substitute for retractable gear) | §61.31(e) |
| **High performance** | Engine of more than 200 horsepower | §61.31(f) |
| **Pressurized / high altitude** | Service ceiling or maximum operating altitude, whichever is lower, above 25,000 ft MSL | §61.31(g) |
| **Tailwheel** | Tailwheel-equipped aeroplane | §61.31(i) |
| **Night vision goggles** | NVG operations | §61.31, ⚠️ confirm sub-paragraph |
| **Towing (glider or banner)** | Towing operations | §61.69 |

Three points that catch people out:

1. **Complex and high performance are separate endorsements.** They were a single concept before
   August 1997; today each operating privilege needs its own endorsement.
2. **The high-altitude endorsement is not required for every pressurised aircraft** — only those
   above the 25,000 ft threshold.
3. **Legacy exemptions exist.** The complex and high-performance endorsements aren't required if
   PIC time was logged in such an aeroplane before 4 August 1997; tailwheel and pressurised have
   an equivalent cutoff of 15 April 1991. If the app warns about missing endorsements it must
   allow a "grandfathered" flag rather than nagging permanently.

### EASA / UK — differences training endorsements within a class

Recorded in the logbook and signed by an instructor. No licence reissue. From the current
endorsement list:

| Endorsement | SEP (land) | SEP (sea) | MEP (land/sea) |
|---|---|---|---|
| Variable pitch propellers (VP) | ✅ | ✅ | — |
| Retractable undercarriage (RU) | ✅ | — | — |
| Turbo- / super-charged engines (T) | ✅ | ✅ | — |
| Cabin pressurisation (P) | ✅ | ✅ | — |
| Tail wheels (TW) | ✅ | — | — |
| Electronic flight instrument system (EFIS) | ✅ | ✅ | ✅ |
| Single lever power control (SLPC) | ✅ | ✅ | — |
| Another type of engine per Article 2(8c) | ✅ | ✅ | — |

Seaplane variants omit retractable undercarriage and tailwheel for obvious reasons. MEP lists
only EFIS explicitly, but differences training is required between MEP aircraft generally.

⚠️ For UK NPPL SSEA holders the list differs: SLPC and EFIS reportedly aren't required, while a
cruise speed above 140 kt is an SSEA-only differences item. Secondary source — verify against
current CAA guidance before implementing.

### The mapping problem

The two systems are not translations of each other:

- A retractable-gear, constant-speed, 180 hp Arrow is **complex** but **not high performance**
  under the FAA, and needs **VP + RU** differences training under EASA.
- A fixed-gear, constant-speed 300 hp Cessna 206 is **high performance** but **not complex**
  under the FAA, and needs only **VP** under EASA.
- Tailwheel is an FAA endorsement and an EASA differences item, so it maps roughly one-to-one —
  the only clean correspondence in the table.

Store the aircraft's **physical attributes**, then let each jurisdiction profile derive its own
required-qualification list. Never store "complex: true" as an aircraft property.

---

## 4. Privilege ratings

| Privilege | EASA | UK CAA | FAA |
|---|---|---|---|
| **Instrument** | IR(A); CB-IR route | UK IR(A) | Instrument Rating — Airplane |
| **Restricted instrument** | BIR (FCL.835) — replaced the EIR, which was removed by Reg. (EU) 2020/359 | **IR(R)** — UK-only, formerly the IMC rating. Valid in UK airspace only, all classes except A/B/C. Cannot be added to a LAPL | None |
| **Night** | Night rating, FCL.810 | Night rating | **No such rating** — night privileges are inherent in the certificate |
| **Aerobatic** | Aerobatic rating, FCL.800 | Aerobatic rating — endorsed on NPPL, Part-FCL and ANO licences | No rating required |
| **Sailplane / banner towing** | Towing rating, FCL.805 | Banner Towing / Sailplane Towing rating | Logbook endorsement, §61.69 |
| **Mountain** | Mountain rating, FCL.815 | Mountain rating | No equivalent |
| **Flight test** | Flight test rating, FCL.820 | Flight Test rating (categories 1–4) | No equivalent; separate FAA mechanisms |

**Divergences worth encoding:**

- **Night is a rating under EASA/UK and not a thing at all under the FAA.** An EASA pilot without
  a night rating cannot fly at night; an FAA private pilot can, subject only to §61.57(b)
  currency. This is the single most likely source of a false "you're not qualified" warning for
  a dual-licence holder.
- **Aerobatics require a rating under EASA/UK and nothing under the FAA.**
- **IR(R) has no analogue anywhere else** and is geographically restricted to UK airspace.
- ⚠️ Whether the UK adopted the BIR needs checking. Reg. (EU) 2020/359 predates the end of the
  transition period, so it was plausibly retained, but the UK's own GA licensing review has moved
  separately. The IR(R) covers much of the same ground for UK pilots regardless.

---

## 5. Type ratings

| | EASA / UK | FAA |
|---|---|---|
| Required when | Multi-pilot aeroplanes; single-pilot high-performance aeroplanes (SP HPA); anything individually listed in the EASA Class and Type Rating List | Aircraft over 12,500 lb maximum certificated takeoff weight; turbojet-powered aeroplanes regardless of weight; other aircraft specified by type certificate |
| Example that surprises people | — | Citation Mustang needs a type rating despite being light — turbojet propulsion, not weight, is the trigger |
| Expiry | 12 months | Does not expire |

⚠️ The EASA SP HPA threshold (MMO above Mach 0.6, or maximum ceiling above 25,000 ft) needs
verification against the current FCL.010 definition — I have not confirmed the exact wording.

Note that "complex motor-powered aeroplane" is a **separate EASA concept** from high performance,
used in Air Ops rather than licensing, and the two are frequently conflated. The rating list
carries both a `Complex` and an `SP HPA / MP` column for this reason.

---

## 6. Validity — what the currency engine needs

| Qualification | EASA / UK validity | FAA |
|---|---|---|
| SEP / TMG class rating | 24 months | n/a — no class rating expiry |
| MEP class rating | 12 months | n/a |
| Type rating | 12 months | Does not expire |
| IR | 12 months | Does not expire; §61.57(c) currency instead |
| BIR | ⚠️ Verify — believed 12 months by proficiency check | n/a |
| IR(R) | n/a | n/a — 25 months, UK only ⚠️ verify |
| Night rating | Does not expire | n/a |
| Aerobatic / towing / flight test | Does not expire (CAA) | n/a |
| Mountain rating | 24 months | n/a |
| §61.31 endorsements | n/a | Never expire |
| Flight review | n/a | 24 calendar months |

The pattern: **EASA gates on rating validity, the FAA gates on recent experience.** An EASA pilot
with a lapsed SEP rating cannot fly at all until they revalidate. An FAA pilot's ratings never
lapse — only their currency does. Two genuinely different models of "am I legal today", and the
UI should not try to present them with one shared widget.

---

## 7. Aircraft attributes the data model must carry

Every qualification above must be derivable from these. Absence of any makes the
required-qualification check impossible for that jurisdiction.

| Attribute | Type | Drives |
|---|---|---|
| Engine count | int | Class rating (SE/ME) |
| Engine type | enum: piston / turboprop / turbojet / turbofan / electric / other | EASA SET vs SEP class; FAA type rating trigger |
| Land / sea / amphibian | enum | Class rating suffix; FAA complex seaplane variant |
| Retractable undercarriage | bool | FAA complex; EASA RU |
| Controllable / variable pitch propeller | bool | FAA complex; EASA VP |
| Flaps fitted | bool | FAA complex |
| Maximum engine horsepower | int | FAA high performance (>200 hp) |
| Turbocharged or supercharged | bool | EASA T |
| Cabin pressurisation | bool | EASA P |
| Service ceiling / max operating altitude | int (ft) | FAA high altitude (>25,000 ft) |
| Tailwheel | bool | FAA tailwheel; EASA TW |
| EFIS fitted | bool | EASA EFIS |
| Single lever power control | bool | EASA SLPC |
| MTOW | int (lb and kg) | FAA type rating (>12,500 lb); EASA complex thresholds |
| Multi-pilot by type certificate | bool | EASA type rating; FAA SIC logging |
| Cruise speed | int (kt) | ⚠️ UK NPPL SSEA differences only |

Derived per profile, never stored: `isComplex`, `isHighPerformance`, `requiresTypeRating`,
`requiresDifferencesTraining`.

---

## 8. Design implication

The qualification check is a **per-profile predicate over aircraft attributes**, exactly like
cross-country. Structure it as:

```
required_qualifications(aircraft, profile) -> [Qualification]
held_qualifications(pilot, profile, date)  -> [Qualification]
```

and surface the difference as a non-blocking warning at entry time. Never block the save — the
pilot may be logging a flight flown under a different licence, on a permit aircraft, or under an
exemption the app doesn't model.

Be especially careful with the night case: an EASA-primary pilot with an FAA certificate and no
EASA night rating is perfectly legal flying at night on the FAA ticket in an N-registered
aircraft. A naive check would flag it as an offence.

---

## 9. Open questions

1. Exact FCL.010 wording of "high performance aeroplane" for the SP HPA type rating threshold.
2. Whether UK Part-FCL adopted the BIR, and the current status of the EIR in UK law.
3. IR(R) validity period and revalidation mechanism under current UK rules.
4. The current NPPL SSEA differences training list, direct from CAA guidance.
5. Whether the app should model UK national licences (NPPL, SSEA, SLMG) at all, or restrict to
   Part-FCL and Part 61.
6. Sub-paragraph reference for the FAA NVG endorsement.

---

## Sources

EASA Class and Type Rating & Licence Endorsement List — Aeroplanes (12.02.2026); GM1 FCL.700;
Part-FCL FCL.700, FCL.705, FCL.710, FCL.800, FCL.805, FCL.810, FCL.815, FCL.820, FCL.835;
ED Decision 2020/018/R and Reg. (EU) 2020/359 (BIR, removal of EIR); 14 CFR §61.31, §61.69,
§1.1; CAA General Aviation pilot licence and additional ratings pages; AOPA endorsement guidance.
