import 'package:freezed_annotation/freezed_annotation.dart';

import 'flight_duration.dart';
import 'pilot_capacity.dart';
import 'utc_instant.dart';

part 'flight.freezed.dart';

/// A single flight, as raw facts only.
///
/// **ADR-0001 is the whole shape of this file.** A value like "PIC time" is
/// not a property of a flight — it is the output of applying one
/// authority's rule to the flight's raw circumstances, and those
/// circumstances (who was manipulating, who held command, who was aboard
/// and in what capacity) are gone forever the moment they are collapsed
/// into a single derived number for one jurisdiction. So `Flight` stores
/// none of `picTime`, `dualTime`, `nightTime`, `crossCountryTime`,
/// `totalTime`, `picusTime` or `spicTime` — see
/// `test/domain/model/flight_test.dart`, which fails the build if any of
/// them appears here. Every one of those is computed at read time by
/// `domain/projection/`, per jurisdiction, from the fields below.
///
/// Field-by-field justification lives in `docs/jurisdiction-matrix.md` §9
/// ("Raw facts this matrix implies") and CLAUDE.md rule 2 — read both before
/// adding, removing or renaming a field here. Every field is unbackfillable:
/// nobody can reconstruct in 2030 whether a 2024 flight's pilot held command
/// authority, so it must be captured now or never.
///
/// Most of "capacity" — command authority, sole manipulator, instructor
/// presence, countersignature, the other pilot's *role* — is
/// [PilotCapacity] (#13), embedded whole rather than flattened back out
/// here. [carryingPassengers] and the other pilot's *identity* are
/// deliberately **not** on [PilotCapacity]; see that class's dartdoc for
/// why they land here instead.
@freezed
abstract class Flight with _$Flight {
  const factory Flight({
    // ---- Aircraft and route.
    /// The aircraft's registration, e.g. `G-ABCD`. A plain reference by the
    /// same key `Aircraft` (#12) uses — there is no synthetic foreign key
    /// yet, because persistence identity is M2's concern, not the domain
    /// model's.
    required String aircraftRegistration,

    /// Departure, any intermediate stops, and destination, in order.
    /// Identifiers as entered — an ICAO code where one exists, otherwise
    /// whatever text the pilot used to identify a private strip or
    /// unlicensed field (#14: not every place a pilot flies from is in any
    /// database). Resolving a leg to full position/elevation via
    /// `AerodromeDirectory` is a projection-time concern, not this model's.
    ///
    /// Full route, never a precomputed `isCrossCountry` boolean or a single
    /// distance figure — `docs/jurisdiction-matrix.md` §3 "Cross-country,
    /// expanded" is explicit that the FAA alone needs several different
    /// distance thresholds evaluated against the same route.
    required List<String> route,

    /// Whether the flight was flown to a destination away from departure
    /// following a pre-planned route, using standard navigation procedures
    /// (dead reckoning, pilotage, or a nav aid) — `FCL.010`'s cross-country
    /// definition verbatim. This is *not* implied by [route]: `FCL.010`
    /// does not require the flight to land anywhere other than where it
    /// departed, so a solo navigation exercise that departs, flies a
    /// planned route out to a distant point, and returns to land back at
    /// the same aerodrome is cross-country under EASA even though [route]
    /// alone (departure, stops, destination — nowhere landed at but
    /// departure) is indistinguishable from a simple local flight.
    /// Unbackfillable: nobody can reconstruct in five years whether a
    /// given circuit-pattern-looking flight was actually flown as a
    /// planned navigation exercise. The FAA has no equivalent concept —
    /// `§61.1(b)(3)(i)` explicitly requires a landing away from departure,
    /// so `faa_cross_country_time.dart` never reads this field.
    required bool prePlannedNavigation,

    // ---- Times. All UTC — rule 3, ADR-0002.
    /// `AMC1 FCL.050(g)(1)`: first movement for the purpose of taking off.
    /// `§1.1`: movement under its own power for the purpose of flight. The
    /// narrow divergence (pushback/tow) is a per-profile primitive, not a
    /// second field — `docs/entry-form.md` §2.
    required UtcInstant offBlocks,

    /// Finally comes to rest. Paired with [offBlocks]; block time itself is
    /// not stored — it is `onBlocks.difference(offBlocks)`, computed on
    /// read, since storing it would duplicate two fields already here.
    required UtcInstant onBlocks,

    /// Air time is a first-class *optional* fact, not the legal total for
    /// either jurisdiction — `docs/entry-form.md` §2. Null until entered;
    /// needed for airborne time and for night computation, which cares when
    /// the aircraft was actually in the air, not when it was taxiing.
    UtcInstant? takeoff,
    UtcInstant? landing,

    // ---- This pilot's capacity, and the other pilot's identity.
    /// This pilot's command authority, manipulation, instructor presence,
    /// countersignature and the other pilot's *role* — see [PilotCapacity].
    required PilotCapacity capacity,

    /// The other pilot's name, when [PilotCapacity.otherPilotRole] is set.
    /// Kept off [PilotCapacity] deliberately: it is a fact about who else
    /// was on the flight, not about this pilot's own standing on it. Needed
    /// for PICUS countersignature and, when the role is
    /// [OtherPilotRole.safetyPilot], required by `§61.51(b)(1)(v)`.
    String? otherPilotName,

    /// The other pilot's licence or certificate number. Needed alongside
    /// [otherPilotName] for a PICUS countersignature.
    String? otherPilotCredentialNumber,

    /// Whether passengers were aboard. `docs/entry-form.md` §4: a role, not
    /// a headcount — no jurisdiction derives a logged quantity from how
    /// many people were aboard, only from whether anyone was. Feeds
    /// `FCL.060(b)(1)`/(b)(3) and `§61.57(a)`/(b) passenger-carrying
    /// recency, evaluated by the currency engine, never computed here.
    required bool carryingPassengers,

    // ---- Take-offs and landings. Four counts each, never one derived from
    // the other and never combined into a single figure —
    // `docs/jurisdiction-matrix.md` §9, `docs/entry-form.md` §5. A pilot who
    // took over in flight has zero take-offs and one landing.
    required CircuitCounts takeoffs,
    required CircuitCounts landings,

    // ---- IFR / instrument facts.
    /// Whether an IFR flight plan was filed. `AMC1 FCL.050` column 9 — an
    /// operational condition, independent of actual meteorological
    /// conditions and of [actualInstrumentTime]. A flight conducted under
    /// IFR entirely in VMC produces full EASA IFR time and zero FAA
    /// instrument time; conflating the two loses that.
    required bool ifrFlightPlanFiled,

    /// Time solely by reference to instruments in actual conditions.
    /// `§61.51(g)(1)`. Zero, not null, when none — this is a duration that
    /// happened or did not, unlike a fact nobody asked about.
    required FlightDuration actualInstrumentTime,

    /// As [actualInstrumentTime], but simulated (a hood, foggles, or a
    /// view-limiting device). `§61.51(b)(3)(iii)`. Reveals the safety-pilot
    /// field in `docs/entry-form.md` §4C when greater than zero.
    required FlightDuration simulatedInstrumentTime,

    /// Instrument approaches flown. FAA-only — `AMC1 FCL.050` has no
    /// approach column and EASA IR revalidation is by proficiency check, not
    /// by counting approaches (`docs/jurisdiction-matrix.md` §9). Empty, not
    /// null, when none. `§61.51(g)(3)` requires type and location per
    /// approach for `§61.57(c)` currency — a bare count is not enough.
    ///
    /// One entry per distinct procedure, not per approach flown: two ILS
    /// approaches to runway 36 at the same aerodrome are one [Approach] with
    /// [Approach.count] 2, not two identical list entries. A flight with
    /// "2x ILS 36 LIML + 1 LOC 27 LIMG" is a two-element list.
    required List<Approach> approaches,

    /// Number of holding patterns flown. `§61.57(c)`. A count, not a bool —
    /// unlike [trackingPerformed], holding is naturally repeatable within
    /// one flight and the number matters for the pilot's own proficiency
    /// tracking beyond the bare currency minimum.
    required int holdingProceduresCount,

    /// Whether intercepting and tracking a course through the use of an
    /// electronic navigation system was performed. `§61.57(c)`;
    /// `docs/jurisdiction-matrix.md` §9 notes this whole area is "often
    /// forgotten" precisely because most logbook software has nowhere to
    /// put it.
    required bool trackingPerformed,

    // ---- Facts unbackfillable if omitted, from jurisdiction-matrix.md §9.
    /// The EASA "flights of short duration" 30-minute rule lets a series of
    /// consecutive short flights — repeated circuits at one aerodrome, for
    /// instance — be logged as one combined entry rather than one row per
    /// landing. Flights sharing this key belong to one series; null when a
    /// flight is not part of one. Nobody can retroactively know which
    /// historical flights were grouped if this is not captured at entry
    /// time, which is why it exists even though nothing yet reads it — no
    /// projection or export issue currently consumes it.
    String? seriesGroupId,

    /// `§61.51(j)`: which of the four categories of aircraft qualify for
    /// FAA-loggable flight time by registry and airworthiness basis. Null
    /// when not recorded — irrelevant to an EASA-only pilot, and the
    /// overwhelming majority of FAA-relevant GA flying falls under
    /// [AirworthinessBasis.usRegistryStandardOrSpecial] regardless.
    AirworthinessBasis? airworthinessBasis,

    // ---- Free text.
    /// `AMC1 FCL.050` column 12. Required content for a skill test,
    /// proficiency check, or SEP/TMG revalidation refresher — see
    /// `docs/entry-form.md` §4B. Empty string, not null, when there is
    /// nothing to say.
    required String remarks,
  }) = _Flight;
}

/// Take-off or landing counts, split the two ways both authorities need:
/// day versus night, and full-stop versus touch-and-go. Four independent
/// counts, never one derived from another —
/// `docs/jurisdiction-matrix.md` §9.
@freezed
abstract class CircuitCounts with _$CircuitCounts {
  const factory CircuitCounts({
    @Default(0) int dayFullStop,
    @Default(0) int dayTouchAndGo,
    @Default(0) int nightFullStop,
    @Default(0) int nightTouchAndGo,
  }) = _CircuitCounts;
}

/// One distinct instrument approach procedure flown, and how many times.
/// `§61.51(g)(3)` requires type and location to be recorded, not just a
/// count, for `§61.57(c)` currency — this carries a runway too, since two
/// approaches to the same aerodrome by different runways are different
/// procedures.
///
/// One [Approach] per distinct procedure, not per approach flown — see
/// [Flight.approaches].
@freezed
abstract class Approach with _$Approach {
  const factory Approach({
    required ApproachType type,

    /// ICAO identifier of the aerodrome the approach was flown to. Always a
    /// real ICAO code, unlike [Flight.route]: an instrument approach only
    /// exists at an aerodrome with a published procedure, which rules out
    /// the private-strip case that makes `route` free text. The entry form
    /// pre-fills this from the flight's destination aerodrome — it is not
    /// necessarily the same one, since an approach can be flown at an
    /// alternate or a training stop that isn't where the flight ended.
    required String aerodromeIcao,

    /// Runway designator, e.g. `09`, `27L`, `36C` — the two-digit heading
    /// number, optionally followed by `L`/`C`/`R` for parallel runways. A
    /// string, not an int: the L/C/R suffix is not decoration, it is which
    /// physical runway was used at an airport with parallel pairs or
    /// triples, and a bare 1-36 number cannot express it.
    required String runway,

    /// How many times this exact procedure — same [type], [aerodromeIcao]
    /// and [runway] — was flown on this flight. "2x ILS 36 LIML" is
    /// `count: 2`, not two separate list entries.
    @Default(1) int count,
  }) = _Approach;
}

/// Instrument approach procedure types, ordered roughly most to least
/// common in current use — not alphabetical, not the order a pilot would
/// necessarily type them in, but the order that puts the frequent choices
/// (ILS, RNAV/GPS) at the top of a picker.
enum ApproachType {
  ils,
  rnav,
  gps,
  vor,
  loc,

  /// Non-directional beacon.
  ndb,

  /// Back-course localizer.
  backCourse,

  /// Localizer-type directional aid.
  lda,

  /// Simplified directional facility.
  sdf,

  /// Tactical air navigation — mostly military/international, though some
  /// U.S. VORTACs support civil TACAN approaches.
  tacan,

  /// Precision approach radar — chiefly military.
  par,

  /// Airport surveillance radar approach.
  asr,

  /// Microwave landing system — essentially obsolete, kept for completeness
  /// and for reading historical entries.
  mls,
}

/// Which of `§61.51(j)`'s four categories an aircraft's registry and
/// airworthiness basis fall under, on the date of the flight. A per-flight
/// fact rather than one carried on `Aircraft` (#12): airworthiness basis can
/// change over an aircraft's life (re-categorisation, a lapsed foreign
/// certificate), and `Aircraft` is a current, editable reference record — if
/// this lived there instead, editing it could silently change whether a
/// historical flight's FAA time was ever loggable in the first place.
enum AirworthinessBasis {
  /// `§61.51(j)(1)`: U.S. registry, standard or special airworthiness
  /// certificate. Covers ordinary FAA GA flying, including amateur-built
  /// aircraft under a special airworthiness certificate.
  usRegistryStandardOrSpecial,

  /// `§61.51(j)(2)`: foreign registry, with an airworthiness certificate
  /// approved by the aviation authority of an ICAO Member State.
  foreignRegistryIcaoMemberApproved,

  /// `§61.51(j)(3)`: a military aircraft under the direct operational
  /// control of the U.S. Armed Forces.
  usMilitary,

  /// `§61.51(j)(4)`: a public aircraft operation under 49 U.S.C.
  /// 40102(a)(41) and 40125.
  publicAircraftOperation,
}
