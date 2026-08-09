import 'package:freezed_annotation/freezed_annotation.dart';

part 'aircraft.freezed.dart';

/// An aircraft the logbook holder has flown.
///
/// **The pilot declares what the aircraft requires; the app does not work it
/// out.** [requiredQualifications] is entered, not derived from physical
/// attributes. Three reasons, and the first is the decisive one:
///
/// 1. **Import round-trips.** ForeFlight and Garmin export aircraft profiles
///    carrying `complex` and `high performance` as flags. Physical attributes
///    cannot be reconstructed from a category flag, so a derived model could
///    never store what those files actually say.
/// 2. **The pilot already knows.** These come from an EFB and from training,
///    and setting up an aircraft is rare. Asking for the answer is less work
///    than asking for the six inputs a derivation would need.
/// 3. **Rules have exemptions a derivation cannot see** — the pre-1997
///    grandfathering on complex and high performance, permit aircraft, and
///    national variations. See `docs/ratings-and-endorsements.md` §3.
///
/// This is a deliberate departure from CLAUDE.md rule 1, and a narrow one.
/// Rule 1 protects *flights*, which are historical records: nobody can revisit
/// whether they held command in 2023. An aircraft is a current reference
/// record, editable whenever a rule changes, so nothing here is unrecoverable.
/// The fields below that are **not** qualifications — category, engine,
/// surface, multi-crew — remain plain facts because logging depends on them.
///
/// A simulator is not an aircraft with a flag set: see `fstd.dart`.
@freezed
abstract class Aircraft with _$Aircraft {
  const factory Aircraft({
    /// Registration as displayed, e.g. `G-ABCD`. `AMC1 FCL.050` column 4
    /// prints it verbatim.
    required String registration,

    /// Make and model as free text, e.g. `Cessna`, `152`. `AMC1 FCL.050`
    /// column 4 wants make, model and variant, and no controlled vocabulary
    /// covers the long tail of GA types.
    required String manufacturer,
    required String model,

    /// ICAO type designator, e.g. `C152`. Null for the many aircraft with
    /// none — homebuilts, microlights, vintage types.
    String? icaoTypeDesignator,

    /// Decides which flight-time definition applies: `FCL.010` measures an
    /// aeroplane from first movement and a helicopter rotor-start to
    /// rotor-stop. A fact about the machine, not a qualification.
    required AircraftCategory category,

    /// With [engineCount] and [operatingSurface], what shows the EASA class
    /// rating — SEP(land), MEP(sea) and so on — and what `AMC1 FCL.050`
    /// column 5 needs to split SE from ME.
    required EngineType engineType,
    required int engineCount,
    required OperatingSurface operatingSurface,

    /// Whether the aircraft's certification requires more than one pilot.
    /// `§61.51(f)` gates SIC time on it and `AMC1 FCL.050` column 5 splits
    /// single-pilot from multi-pilot time. A logging discriminator, not a
    /// qualification.
    required bool requiresMultiCrew,

    /// The type rating identifier where one applies, e.g. `A320`. Null means
    /// class-rated.
    ///
    /// One field rather than a boolean beside it: set *is* "a type rating is
    /// required", so the two states that could contradict each other — true
    /// with no identifier, false with one — cannot be expressed.
    ///
    /// This is the join. Several registrations sharing an identifier share one
    /// type rating, so two A32N airframes resolve to the same `A320` rating
    /// the pilot holds, with one validity date. Revalidating updates one
    /// record rather than one per aeroplane. The validity itself lives with
    /// the pilot's held rating, never here — an aircraft has no expiry.
    String? typeRatingDesignator,

    /// What the pilot must hold to fly this aircraft, per authority.
    ///
    /// Keyed by jurisdiction profile id (`eu.easa.part-fcl`, `us.faa.part61`).
    /// A **missing key** means the aircraft has not been set up for that
    /// authority yet; a **present but empty** set means it has, and nothing is
    /// required. Those are different answers and the UI must not conflate
    /// them.
    ///
    /// Per authority because the two systems are not translations of each
    /// other (`docs/ratings-and-endorsements.md` §3): a 180 hp Arrow is
    /// complex but not high performance under the FAA, and needs variable
    /// pitch plus retractable under EASA. A 300 hp fixed-gear 206 is the
    /// reverse.
    @Default(<String, Set<AircraftQualification>>{})
    Map<String, Set<AircraftQualification>> requiredQualifications,
  }) = _Aircraft;
}

/// The broad kind of aircraft.
enum AircraftCategory {
  aeroplane,
  helicopter,
  poweredLift,
  glider,

  /// Touring motor glider — a separate EASA class rating with its own
  /// revalidation rules under `FCL.740.A`, not simply a glider.
  touringMotorGlider,

  airship,
  balloon,

  /// `§61.1(b)(3)(iv)`/`(vi)` name this category explicitly to carve it out
  /// of the FAA's private/commercial and sport-pilot cross-country distance
  /// tests and give it its own, shorter one — see `cross_country_time.dart`
  /// (#24). No EASA analogue; Part-FCL has no powered-parachute category.
  poweredParachute,
}

enum EngineType { none, piston, turboprop, turbojet, turbofan, electric }

/// Where the aircraft operates from. With engine type and count this gives the
/// EASA class rating suffix — (land) or (sea).
enum OperatingSurface { land, sea, amphibian }

/// A qualification an aircraft can require.
///
/// One list covering both authorities, because [Aircraft.requiredQualifications]
/// is keyed by authority and each key's set draws only on its own values.
/// Putting an FAA endorsement in an EASA list is a data error, not a type
/// error — the app should not stop you recording something unusual.
///
/// Deliberately excludes everything `docs/ratings-and-endorsements.md` marks
/// ⚠️: no BIR, no IR(R), no NPPL SSEA items, no UK national licence classes.
/// Those rows are unverified, and half-encoding a regulation is worse than
/// leaving it out.
enum AircraftQualification {
  // ---- FAA §61.31 endorsements. Permanent once given; they never expire.
  /// `§61.31(e)` — retractable gear, flaps and a controllable-pitch propeller;
  /// for seaplanes, flaps and controllable-pitch propeller alone.
  faaComplex,

  /// `§61.31(f)` — an engine of more than 200 horsepower.
  faaHighPerformance,

  /// `§61.31(g)` — service ceiling or maximum operating altitude, whichever is
  /// lower, above 25,000 ft MSL. Not the same as being pressurised.
  faaHighAltitude,

  /// `§61.31(i)` — tailwheel-equipped aeroplanes.
  faaTailwheel,

  /// `§61.69` — glider or banner towing.
  faaTowing,

  // ---- EASA / UK differences training within a class. `GM1 FCL.700`, and the
  // EASA Class and Type Rating & Licence Endorsement List. Recorded in the
  // logbook and signed by an instructor; no licence reissue.
  /// Variable-pitch propellers (VP).
  easaVariablePitchPropeller,

  /// Retractable undercarriage (RU). Not applicable to seaplane classes.
  easaRetractableUndercarriage,

  /// Turbo- or super-charged engines (T).
  easaTurboOrSupercharged,

  /// Cabin pressurisation (P).
  easaCabinPressurisation,

  /// Tail wheels (TW). The one item that maps roughly one-to-one onto an FAA
  /// endorsement — see [faaTailwheel].
  easaTailwheel,

  /// Electronic flight instrument system (EFIS). Drawn differently from the
  /// FAA's technically-advanced test, which is why there is no shared value.
  easaElectronicFlightInstrumentSystem,

  /// Single lever power control (SLPC).
  easaSingleLeverPowerControl,

  /// Another type of engine, per Article 2(8c).
  easaOtherEngineType,
}
