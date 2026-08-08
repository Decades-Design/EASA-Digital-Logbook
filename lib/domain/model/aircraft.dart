import 'package:freezed_annotation/freezed_annotation.dart';

part 'aircraft.freezed.dart';

/// An aircraft the logbook holder has flown.
///
/// **Physical facts only.** `complex`, `high-performance` and `technically
/// advanced` are FAA *categories* defined by `§61.31` in terms of what the
/// aircraft carries, and EASA differences training keys off an overlapping but
/// differently-drawn list. Both are read from [equipment] and [horsepower] by
/// `lib/domain/primitives/faa_aircraft_categories.dart` rather than stored —
/// CLAUDE.md rule 1. The two taxonomies "not aligning" is not a problem to
/// solve; they are two readings of one set of facts.
///
/// A simulator is **not** an aircraft with a flag set. See [Fstd] in
/// `fstd.dart`: `AMC1 FCL.050` column 11 gives a device session its own date
/// and keeps its total out of total time of flight, so the two are separate
/// types and simulator time cannot reach a flight total by accident.
@freezed
abstract class Aircraft with _$Aircraft {
  const factory Aircraft({
    /// Registration as displayed, e.g. `G-ABCD`, `N123AB`. The identifier the
    /// pilot actually types; `AMC1 FCL.050` column 4 prints it verbatim.
    required String registration,

    /// Manufacturer and model as free text, e.g. `Cessna`, `152`.
    /// `AMC1 FCL.050` column 4 wants make, model and variant, and no
    /// controlled vocabulary covers the long tail of GA types.
    required String manufacturer,
    required String model,

    /// ICAO type designator, e.g. `C152`. Null for the many aircraft that have
    /// none — homebuilts, microlights, vintage types. CLAUDE.md's import notes
    /// expect non-ICAO type codes in vendor CSVs, so this can never be
    /// required.
    String? icaoTypeDesignator,

    required AircraftCategory category,
    required EngineType engineType,

    /// Zero for a glider or balloon.
    required int engineCount,

    required OperatingSurface operatingSurface,

    /// Whether the aircraft needs a type rating rather than a class rating.
    ///
    /// A licensing fact, not a physical one: EASA maintains the list, and it
    /// cannot be derived from mass or engine count. Class ratings — SEP(land),
    /// MEP(sea) and so on — *are* derivable, from [engineType],
    /// [engineCount] and [operatingSurface].
    required bool requiresTypeRating,

    /// The type rating designator where one applies, e.g. `A320`. Null for a
    /// class-rated aircraft.
    String? typeRatingDesignator,

    /// Whether the aircraft's certification requires more than one pilot.
    /// `§61.51(e)(1)(iii)` and `§61.51(f)` both read this, and `AMC1 FCL.050`
    /// column 5 splits single-pilot from multi-pilot time.
    ///
    /// Pre-fills a flight's multi-pilot fact without replacing it — an
    /// operation can require two pilots by rule in a single-pilot aircraft.
    required bool requiresMultiCrew,

    /// Maximum continuous engine power, per engine, in horsepower.
    ///
    /// Stored because `§61.31(f)` draws the high-performance line at more than
    /// 200 hp. Null where unknown or not meaningful; a null makes the
    /// high-performance question unanswerable rather than answerable as false.
    int? horsepower,

    /// Everything the aircraft carries that any authority's rules turn on.
    ///
    /// A set rather than a row of booleans so a new attribute is one enum
    /// value, not a schema change — an explicit requirement of issue #12,
    /// and the reason this survives both authorities revising their lists.
    @Default(<AircraftEquipment>{}) Set<AircraftEquipment> equipment,
  }) = _Aircraft;
}

/// The broad kind of aircraft. Determines which time definition applies —
/// `FCL.010` measures aeroplane flight time from first movement and helicopter
/// time rotor-start to rotor-stop — and which labels the entry form shows.
enum AircraftCategory {
  aeroplane,
  helicopter,
  poweredLift,
  glider,

  /// Touring motor glider. A separate EASA class rating with its own
  /// revalidation rules under `FCL.740.A`, and not simply a glider.
  touringMotorGlider,

  airship,
  balloon,
}

enum EngineType { none, piston, turboprop, turbojet, turbofan, electric }

/// Where the aircraft operates from. With [Aircraft.engineType] and
/// [Aircraft.engineCount] this yields the EASA class rating — SEP(land),
/// MEP(sea) and so on — which is therefore never stored.
enum OperatingSurface { land, sea, amphibian }

/// Physical and avionic attributes that an authority's rules read.
///
/// EASA differences training (`GM1 FCL.700`) and FAA aircraft categories
/// (`§61.31`) draw different lines through this same list, which is why the
/// list holds facts and not either authority's conclusions.
enum AircraftEquipment {
  /// EASA differences training under `GM1 FCL.700`; also one of the three
  /// conditions for FAA complex under `§61.31(e)`.
  retractableUndercarriage,

  /// Variable- or controllable-pitch propeller. `GM1 FCL.700`; the second
  /// `§61.31(e)` condition.
  variablePitchPropeller,

  /// The third `§61.31(e)` condition. Recorded explicitly because a handful of
  /// types genuinely have none, and assuming flaps would make them complex.
  flaps,

  /// `GM1 FCL.700` treats turbocharging and supercharging as distinct
  /// differences-training items.
  turbocharged,
  supercharged,

  /// `GM1 FCL.700`.
  pressurised,

  /// Tailwheel undercarriage. `GM1 FCL.700`, and an FAA endorsement
  /// requirement under `§61.31(i)`.
  tailwheel,

  /// Electronic flight instrument system. The EASA differences item under
  /// `GM1 FCL.700`, drawn differently from the FAA's technically-advanced
  /// test — which is why both appear in this list rather than one standing in
  /// for the other.
  electronicFlightInstrumentSystem,

  /// Single lever power control. `GM1 FCL.700`.
  singleLeverPowerControl,

  /// Primary flight display. First condition of FAA technically advanced
  /// under `§61.129(j)`.
  primaryFlightDisplay,

  /// Multifunction display showing a moving map with GPS. Second `§61.129(j)`
  /// condition.
  multiFunctionDisplayWithMovingMap,

  /// Two-axis autopilot integrated with the navigation and heading guidance.
  /// Third `§61.129(j)` condition.
  integratedAutopilot,
}
