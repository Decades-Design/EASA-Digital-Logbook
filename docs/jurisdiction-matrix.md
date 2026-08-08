# Jurisdiction Matrix — EASA / FAA / UK CAA

Quick-reference comparison of logging, definition and currency rules across the three
authorities this app must support. Written as a working reference for building the
`domain/jurisdiction/` profiles and `domain/primitives/` derivation functions.

> **Status: working summary, not legal advice.** Every row here needs verification against the
> current instrument before it becomes load-bearing in code. Regulations cited were checked in
> August 2026; the UK diverged again in October 2025. Treat this document as a map of *where to
> look*, not as the authority itself. Where a row is marked ⚠️ the rule is genuinely ambiguous
> or authority-dependent.
>
> The one exception is the column layout in §2, which is transcribed from the sheet EASA
> publishes and lives in [`docs/amc1-fcl050-layout.md`](amc1-fcl050-layout.md). ⚠️ That sheet is
> marked **ED Decision 2020/005/R**, not the 2022/014/R or 2025/002/R this document previously
> cited for it — confirm which decision governs before M6 hardens the printed layout.

---

## 1. Regulatory architecture

| | EASA | FAA | UK CAA |
|---|---|---|---|
| Primary instrument | Reg. (EU) 1178/2011 Annex I (Part-FCL) | 14 CFR Part 61 | UK Reg. 1178/2011 (retained), UK Part-FCL |
| Logging requirement | FCL.050 | §61.51 | UK FCL.050 |
| Prescribed format | Yes — AMC1 FCL.050, 12 column groups | **No** — format-neutral, content-prescribed | Yes — same AMC structure, CAA-published |
| Recency | FCL.060 | §61.57 | UK FCL.060 |
| Definitions | FCL.010 | §1.1 and §61.1 | UK FCL.010 |
| Relationship | Baseline | Independent | **Fork of EASA**, diverging since 2021 |

The regulation itself is short. FCL.050 says only that the pilot must keep a reliable record of all flights flown in a form and manner established by the competent authority — the substance lives in AMC1 FCL.050, which is not legally binding in the same way but defines the standard the national authority expects.

The UK retained EASA-derived rules as UK instruments the CAA amends on its own initiative, and the two rulebooks are diverging rather than moving in lockstep. Model UK as `extends: eu.easa.part-fcl` with explicit overrides.

**Within EASA, the competent authority still matters.** FCL.050 defers to the national
authority, so acceptance practice varies by member state. Known example: Ireland does not accept electronic logbooks for ATPL issue, requires all PICUS entries to be countersigned by the PIC including the PIC's licence number, does not accept electronic signatures for this, and treats unsigned PICUS time as unusable.

---

## 2. Mandatory logbook content

### EASA / UK — AMC1 FCL.050 column groups

**Twelve** groups, not thirteen. Transcribed in full — including the front matter, page totals
and certification block — in [`docs/amc1-fcl050-layout.md`](amc1-fcl050-layout.md), from the
EASA-published template (ED Decision 2020/005/R). That file is the authority for every
"column N" citation in this codebase; this table is a summary of it.

| # | Column group | Subfields |
|---|---|---|
| 1 | Date | dd/mm/yy, date flight commences |
| 2 | Departure | Place, time (UTC) |
| 3 | Arrival | Place, time (UTC) |
| 4 | Aircraft | Make, model, variant; registration |
| 5 | Single-pilot time / multi-pilot time | SE / ME for single-pilot; multi-pilot undivided |
| 6 | Total time of flight | Hours+minutes or decimal |
| 7 | Name(s) of PIC | Or "SELF" |
| 8 | Landings | Day / night, as pilot flying |
| 9 | Operational condition time | Night / IFR |
| 10 | Pilot function time | PIC / co-pilot / dual / instructor |
| 11 | FSTD session | Date, type, total session time |
| 12 | Remarks and endorsements | See §7 below |

⚠️ **This table was wrong until 2026-08-08** and is corrected here against the published sheet.
It previously listed thirteen groups, splitting single-pilot and multi-pilot time into 5 and 6.
They are one group, so everything from 5 onward was numbered one too high. Any external note or
older commit citing "column 11 pilot function time" or "column 13 remarks" is using the old,
wrong numbering.

Places may be entered in full or as the three- or four-letter designator, and all times should be in UTC. Column 5 indicates SP or MP, and for SP whether SE or ME. Column 8 takes the number of landings as pilot flying by day or night. Column 9 takes flight time at night or under IFR.

### FAA — §61.51(b)

Each entry must record: date; total flight or lesson time; departure and arrival location (or location of the lesson for FSTD/FTD/ATD); type and identification of aircraft or device; and the name of a safety pilot where §91.109 requires one. Type of pilot experience must be recorded as solo, PIC, SIC, flight and ground training received from an authorised instructor, or training received in an FFS/FTD/ATD. Conditions of flight must be recorded as day or night, actual instrument, simulated instrument, and night vision goggle use.

**Structural difference:** the FAA prescribes *content*, not *layout*. EASA prescribes both. A
single canonical model satisfies both, but the print/export layouts must be per profile.

---

## 3. Time definitions

| Concept | EASA / UK | FAA | Divergence impact |
|---|---|---|---|
| **Flight time (aeroplane)** | From when the aircraft **first moves** for the purpose of taking off until it finally comes to rest (FCL.010; AMC1 FCL.050(g)(1)) | From when the aircraft **moves under its own power** for the purpose of flight until it comes to rest after landing (§1.1) | Pushback/tow counts under EASA, not FAA. Material for airline ops, negligible for GA. |
| **Flight time (helicopter)** | Rotor start to rotor stop | Same practical effect via §1.1 | Aligned |
| **Night (logging)** | End of evening civil twilight to beginning of morning civil twilight | Same — §1.1 defines night by the sun's position, not a fixed clock time | **Aligned for logging** |
| **Night (currency)** | Same civil-twilight window (FCL.060) | 1 hour after sunset to 1 hour before sunrise (§61.57(b)) | **Two different night windows under FAA alone.** A landing can be night-for-logging but not night-for-currency. |
| **Cross-country** | Single definition: flight time navigating to a destination away from the departure aerodrome following a pre-planned route using standard navigation procedures — no minimum distance in the definition itself; specific distances sit in the individual experience requirements | A general logging definition with no minimum distance (§61.1(b)(3)(i)), plus six purpose-specific credit tests at 50, 25 or 15 nm depending on the certificate or rating being credited (§61.1(b)(3)(ii)–(vii)) | **Largest divergence.** Store the route; never store an `isCrossCountry` boolean — FAA alone needs several simultaneously live answers per flight. |
| **Instrument time** | Column 9 records **IFR time** — an operational condition | Only time operating the aircraft solely by reference to instruments under actual or simulated instrument conditions (§61.51(g)(1)) | An IFR flight entirely in VMC = full EASA IFR time, **zero** FAA instrument time. |
| **Simulated instrument** | Not separately columned | Separate condition (§61.51(b)(3)(iii)) | FAA needs actual/simulated split; EASA does not |
| **FSTD time** | Column 11, separated from flight time (group 6) | Logged, but not flight time | Aligned in principle |

### Cross-country, expanded

**FAA — §61.1(b)(3).** Seven sub-paragraphs, not one. (i) is what cross-country *time* actually
is — no minimum distance — and is what gets logged as such; (ii)–(vii) are purpose-specific
*credit* tests layered on top, each gating whether a cross-country flight counts toward one
particular certificate or rating's aeronautical experience requirement.

| § | Applies to | Minimum landing distance | Notes |
|---|---|---|---|
| (i) | General definition — any certificated pilot, any aircraft | None | A landing anywhere other than the point of departure, navigated to by dead reckoning, pilotage, or an electronic/radio/other nav system. This is the loggable definition, not a credit test. |
| (ii) | Private (except powered-parachute rating), commercial, instrument rating; recreational privileges except rotorcraft | > 50 nm straight-line | The threshold most people mean by "the 50 nm rule" |
| (iii) | Sport pilot, except powered-parachute privileges | > 25 nm straight-line | |
| (iv) | Sport pilot with powered-parachute privileges; private pilot with powered-parachute category rating | > 15 nm straight-line | |
| (v) | Any certificate with rotorcraft category rating; instrument–helicopter rating; recreational privileges in a rotorcraft | > 25 nm straight-line | Rotorcraft takes the sport-pilot distance, not the private-pilot one |
| (vi) | Airline transport pilot, except rotorcraft category rating | > 50 nm straight-line | |
| (vii) | Military pilot qualifying for a commercial certificate under §61.73, except rotorcraft | > 50 nm straight-line | |

**Consequence for the model:** a single flight can be cross-country under the general definition
(i) — and loggable as such — while failing every credit test that applies to the certificate the
pilot is actually pursuing, or passing some and not others if the pilot is working toward more
than one. Which threshold applies is a function of *which certificate or rating's credit is being
evaluated* and *the aircraft's category* (rotorcraft vs. not; powered-parachute vs. not — see
`AircraftCategory` in `lib/domain/model/aircraft.dart`), never a single number. #24's projection
needs to answer "is this cross-country toward a private certificate" and "is this cross-country
toward a rotorcraft rating" as two different questions over the same flight and the same stored
route.

**EASA / UK.** The definition does not require the arrival point to differ from departure, so a
pre-planned navigation exercise returning to the origin can qualify. This is contested in practice
and interpretation varies by competent authority. ATPL credit differs again.

**Implication:** cross-country is not one field. It is a per-profile, per-purpose predicate
evaluated over the stored route.

---

## 4. Pilot roles and function time

| Role | EASA / UK | FAA | Notes |
|---|---|---|---|
| **PIC (command)** | Designated before flight by the operator; may delegate conduct of the flight to another qualified pilot | Acting PIC under §91.3 — final authority and responsibility | Concept aligned |
| **PIC (logging)** | Only where command authority is held, plus the specific cases below | Sole manipulator of the controls of an aircraft for which the pilot is rated; or sole occupant; or acting PIC of an aircraft requiring more than one pilot; or performing PIC duties under an approved supervised programme (§61.51(e)) | **The core divergence.** FAA separates *logging* PIC from *acting* PIC; EASA does not. |
| **SPIC** | A student pilot acting as PIC on a flight with an instructor where the instructor only observes and does not influence or control the flight | **No analogue** | Closest FAA concept is §61.87 solo, which is a different situation. Logged in the PIC column, countersigned. |
| **PICUS** | A co-pilot performing, under supervision of the PIC, the duties and functions of a PIC; logged as PIC provided the PIC's intervention in the interest of safety was not required, and countersigned by the PIC | **No analogue** | Up to 500 hours creditable toward the ATPL(A) PIC requirement under FCL.510(a)(2). |
| **Co-pilot** | Column 10 co-pilot time; multi-pilot operations only | SIC — requires §61.55 qualification and a crewmember station in an aircraft requiring more than one pilot by type certificate, or equivalent under §135.99(c) | ⚠️ Second pilot in a single-pilot aeroplane logs **nothing** under EASA |
| **Dual instruction** | Flight time during which a person is receiving flight instruction from a properly authorised instructor | Training received from an authorised instructor | SPIC and dual are mutually exclusive under FCL.010 — they cannot be recorded concurrently. |
| **Instructor** | Recorded as instructor time and also entered as PIC | A CFI may log PIC for all time serving as the authorised instructor if rated to act as PIC of that aircraft (§61.51(e)(3)) | Broadly aligned |
| **Safety pilot** | No defined category ⚠️ | Name must be recorded when required by §91.109; logs PIC or SIC depending on the arrangement | FAA-only field. Store it anyway. |
| **Solo** | Logged as PIC | Only time when the pilot is the sole occupant (§61.51(d)) | Aligned |
| **Student PIC** | SPIC (above) | Only when sole occupant, holding a §61.87 solo endorsement, and undergoing training (§61.51(e)(4)) | Different mechanisms, similar effect |

### The canonical divergence case

**Rated private pilot, sole manipulator, instructor aboard, dual instruction being given.**

| | FAA | EASA / UK |
|---|---|---|
| PIC | Full flight time | 0 |
| Dual | Full flight time | Full flight time |
| Instructor's PIC | Full (if rated to act as PIC) | Full |

Under EASA the same hand-flying hour does not automatically become PIC time; there is no general sole-manipulator concept. Both pilots logging PIC simultaneously is normal
and correct under the FAA, and impossible under EASA.

**Test fixture requirement:** this exact flight must appear in `test/fixtures/` and produce
different `picTime` under each profile.

---

## 5. Recency and currency

| Requirement | EASA | UK CAA | FAA |
|---|---|---|---|
| **Passenger carrying** | 3 take-offs, approaches and landings in preceding 90 days, in same type or class or an FFS representing it (FCL.060(b)(1)) | Same, FCL.060(b)(2) — sole manipulator, same class or type | 3 take-offs and landings in preceding 90 days, same category/class/type (§61.57(a)) |
| Landings must be full-stop? | No | No | No by day; **yes** at night |
| **Night passenger** | ⚠️ 1 take-off and landing at night in 90 days unless IR held (FCL.060(b)(3)) | Same — one night take-off and landing in the 90-day window unless holding a valid IR | 3 take-offs and 3 landings **to a full stop**, in the 90 days, in the 1-hour-after-sunset to 1-hour-before-sunrise window, as sole manipulator (§61.57(b)) |
| **Instrument** | IR revalidation by proficiency check, annually | Same structure | 6 approaches, holding, and intercepting/tracking courses within preceding 6 calendar months (§61.57(c)) |
| **Periodic check** | Class/type rating revalidation | Same | Flight review every 24 calendar months, minimum 1 hour ground + 1 hour flight (§61.56) |
| **SEP revalidation** | Proficiency check within 3 months preceding expiry; **or** within the **12 months preceding expiry**, 12 hours in the class including 6 hours PIC, 12 take-offs and 12 landings, and ≥1 hour refresher training with an FI or CRI (FCL.740.A(b)(1)) | **Diverged.** 12 hours across the **whole 2-year validity period**, of which 6 hours in the 12 months preceding expiry; 12 take-offs and landings; ≥1 hour refresher training | No direct equivalent — flight review serves the role |

### Notable UK-specific divergences

- Since the October 2025 licensing changes, up to 6 of the 12 required SEP hours may be flown in the first year of validity, the 12 take-offs and landings requirement is unchanged, and PPL training and SEP revalidation may include hours flown in a three-axis microlight.
- UK FCL.060(a) is marked as repealed before the document was retained — the UK
  provision is not a straight copy. Verify sub-paragraph numbering before implementing.
- The refresher training flight cannot be conducted in a microlight of any configuration, per
  CAA guidance, despite microlight hours counting toward the 12.

### Currency arithmetic traps

- FAA windows are frequently **calendar months** (flight review, instrument), not rolling days.
  EASA passenger recency is rolling 90 days. Do not implement one window type.
- For FCL.060(b)(1), an instructor or examiner on board is not counted as a passenger, and if flying under instructor supervision to regain the three take-offs, approaches and landings, no passengers may be on board.
- FAA night currency and FAA night logging use **different definitions of night**. Two
  primitives, not one.

---

## 6. Series-of-flights and entry granularity

**EASA:** A number of flights on the same day, each returning to the same place of departure, with no more than 30 minutes between successive flights, may be recorded as a single entry.

**FAA:** no equivalent provision.

**Implication for the data model:** a "flight" row cannot assume 1:1 with a take-off. Either
store legs and aggregate for EASA display, or store the aggregate and flag it. Storing legs is
the only version that satisfies both — consistent with the raw-facts rule.

---

## 7. Certification, countersignature and signatures

| | EASA / UK | FAA |
|---|---|---|
| Entry timing | As soon as practicable after the flight | Not specified |
| Paper medium | Ink or indelible pencil | Not specified |
| Page totals | Accumulated time entered per page and certified by the pilot in the remarks column | Not required |
| SPIC / PICUS | Countersigned by the aircraft PIC or FI in column 12 | N/A |
| Instruction received | Each flight certified by the instructor responsible for the flight (AMC1 FCL.050(b)(1)(ii)) | Endorsed legibly by the instructor, with description of training, lesson length, signature, certificate number and expiry (§61.51(h)) |
| Always-required remarks | Instrument flight time as part of licence/rating training; details of all skill tests and proficiency checks; name and signature of PIC for SPIC or PICUS; name and signature of instructor for an SEP or TMG revalidation flight | N/A |

**FAA instructor endorsements carry expiry-dated credentials.** The EASA countersignature model
is a signature plus licence number. These are different data shapes — store signatory identity,
credential number, credential expiry, and signature timestamp as a structured object.

---

## 8. Electronic logbook acceptability

| | Position |
|---|---|
| EASA | Electronic records are acceptable provided they are readily available on request by a competent authority, contain all the required items, are certified by the pilot, and are in a format acceptable to that authority. In practice: acceptable for applications provided they have been printed, signed and dated. |
| Digital-records guidance | EASA's May 2023 guidelines on electronic documents, records and signatures reference eIDAS (EU 910/2014) and expect audit trails, user authentication and correction tracking. |
| "Certification" | Contested. One view: no such certification exists — logbooks are either compliant or not. Another: certification results from an audit by a Member State competent authority. |
| UK CAA | Electronic records must be readily available at CAA request, contain all required items, be certified by the pilot, and be in a format acceptable to the CAA. |
| FAA | Format-neutral — any manner acceptable to the Administrator |
| ⚠️ National exception | Ireland: electronic logbooks not acceptable for ATPL issue. |

---

## 9. Raw facts this matrix implies

Discriminators that must exist in `Flight` for **any** of the above to be computable. Absence of
any of these makes a jurisdiction's numbers unrecoverable for historical flights.

| Fact | Needed by | Why |
|---|---|---|
| Command authority held (bool) | EASA PIC | Independent of who was manipulating |
| Sole manipulator (bool, or time split) | FAA PIC | §61.51(e)(1)(i) |
| Sole occupant (bool) | Both, solo | §61.51(d) |
| Instructor aboard + capacity | Both | Dual vs SPIC vs nothing |
| Instructor actually influenced the flight (bool) | EASA | SPIC requires that they did not |
| Multi-pilot operation (bool) | EASA co-pilot, FAA SIC | Column 5, §61.51(f) |
| Aircraft requires >1 pilot by TC (bool) | FAA | §61.51(e)(1)(iii), (f) |
| Safety pilot identity | FAA | §61.51(b)(1)(v) |
| Full route with waypoints | Cross-country, all profiles | Distance thresholds differ |
| Take-offs and landings, split full-stop / touch-and-go **and** day / night | FAA night currency, EASA column 8 | Four counts, not one |
| Timestamps precise enough to resolve civil twilight and sunset±1h | Both night definitions | Two windows |
| IFR flight plan filed (bool) | EASA column 9 | Distinct from actual conditions |
| Actual instrument time | FAA | §61.51(g)(1) |
| Simulated instrument time | FAA | §61.51(b)(3)(iii) |
| Approach type, aerodrome, runway and count per procedure | FAA §61.57(c) only | §61.51(g)(3) requires type and location per approach; runway distinguishes two procedures at the same aerodrome. **No EASA equivalent** — AMC1 FCL.050 has no approach column and FCL.060's "approaches" wording is a recency condition, not a logging obligation |
| Holding procedures performed (count) | FAA §61.57(c) | A count, not a bool — holding is naturally repeatable within one flight |
| Intercepting and tracking a course via a nav system (bool) | FAA §61.57(c) | A single yes/no fact, independent of the holding count. Both often forgotten |
| FSTD identity and qualification level | Both | Column 11; FFS vs FTD vs ATD matters to FAA |
| Countersignature: signatory, credential no., expiry, timestamp | EASA SPIC/PICUS, FAA instruction | Uncountersigned PICUS is not creditable |
| Series-of-flights grouping key | EASA | 30-minute rule |
| Aircraft registry state and airworthiness basis | FAA | §61.51(j) restricts which aircraft time may be logged in |

---

## 10. Open questions to resolve before implementing

1. Exact current wording of UK FCL.060 sub-paragraphs post-repeal of (a).
2. Whether EASA's cross-country definition permits same-aerodrome return in your competent
   authority's interpretation — this materially changes IR/CPL hour credit.
3. AMC1 FCL.050 as amended by ED Decision 2025/002/R — this document reflects the 2022/014/R
   column structure; confirm no columns were added or renumbered.
4. Cruise-relief co-pilot handling (called out separately in recent AMC1 FCL.050 amendments).
5. Whether the app should attempt FAA §61.57(c) approach logging at all in v1, given it needs
   approach type and location per approach.

---

## Sources

Primary: 14 CFR §1.1, §61.1, §61.51, §61.57 (eCFR, current to 30 July 2026); Reg. (EU)
1178/2011 Annex I Part-FCL FCL.010, FCL.050, FCL.060, FCL.740.A; AMC1 FCL.050 (ED Decision
2022/014/R, amended 2025/002/R); UK Part-FCL via CAA Regulatory Library and CAA GA licensing
pages; CAP3155 (UK licensing changes, October 2025).

Secondary and interpretive: EASA Brexit FAQ; Irish Aviation Authority logbook FAQ and PLAM 024;
capzlog.aero regulatory academy; FAA Airplane Flying Handbook Ch. 11.