/// FAA aircraft categories, derived from an aircraft's physical facts.
///
/// `§61.31` defines complex, high-performance and technically advanced in
/// terms of what the aircraft carries. None of them is stored on [Aircraft] —
/// they are computed here, so that a change to a threshold recomputes every
/// historic record instead of silently invalidating it (CLAUDE.md rule 1,
/// ADR-0001).
///
/// These are the named primitives a jurisdiction profile will reference. They
/// take an [Aircraft] and nothing else: no clock, no I/O, no configuration.
library;

import '../model/aircraft.dart';
import '../model/mass.dart';

/// The FAA type-rating mass threshold: `§61.31(a)` reads "more than 12,500
/// pounds". Expressed in pounds because that is the unit the rule uses, and
/// 12,500 lb is a common certification limit chosen precisely because it is
/// the threshold — see [Mass].
const Mass faaTypeRatingMassThreshold = Mass.pounds(12500);

/// `§61.31(g)`: above 25,000 ft MSL.
const int highAltitudeThresholdFeet = 25000;

/// Whether the aircraft is **complex** under `§61.31(e)`.
///
/// An aeroplane with retractable landing gear, flaps and a controllable-pitch
/// propeller. For a seaplane the gear condition does not apply — the rule
/// reads "in the case of a seaplane, flaps and a controllable pitch
/// propeller" — because a floatplane has no retractable undercarriage to
/// speak of and would otherwise never qualify.
///
/// Turbine aeroplanes are outside this test: `§61.31(e)` is written for
/// propeller aircraft, and a jet's type rating covers the ground the complex
/// endorsement exists to cover.
bool isComplex(Aircraft aircraft) {
  if (aircraft.category != AircraftCategory.aeroplane) {
    return false;
  }

  final hasFlaps = aircraft.equipment.contains(AircraftEquipment.flaps);
  final hasVariablePitch = aircraft.equipment.contains(
    AircraftEquipment.variablePitchPropeller,
  );

  if (aircraft.operatingSurface == OperatingSurface.sea) {
    return hasFlaps && hasVariablePitch;
  }

  return hasFlaps &&
      hasVariablePitch &&
      aircraft.equipment.contains(AircraftEquipment.retractableUndercarriage);
}

/// Whether the aircraft is **high-performance** under `§61.31(f)`: an engine
/// of more than 200 horsepower.
///
/// Returns null when [Aircraft.horsepower] is unknown. Deliberately not
/// false — "we do not know" and "no" lead to different actions, and a silent
/// false would let an aircraft that needs the endorsement pass as one that
/// does not. CLAUDE.md: a wrong answer is worse than no answer.
bool? isHighPerformance(Aircraft aircraft) {
  final horsepower = aircraft.horsepower;
  if (horsepower == null) {
    return null;
  }
  return horsepower > 200;
}

/// Whether a **high-altitude endorsement** is required under `§61.31(g)`.
///
/// The rule compares the service ceiling *or* the maximum operating altitude,
/// **whichever is lower**, against 25,000 ft MSL. Taking the lower of the two
/// is the whole point: an aeroplane whose airframe could reach 30,000 ft but
/// which is limited to 24,000 ft in operation needs no endorsement.
///
/// Returns null when neither altitude is recorded — the question is then
/// unanswerable, and answering false would clear an aeroplane that may well
/// need the endorsement. Note this is **not** the same as being pressurised:
/// plenty of pressurised aeroplanes sit below the threshold, which is why
/// [AircraftEquipment.pressurised] is not consulted here.
bool? requiresHighAltitudeEndorsement(Aircraft aircraft) {
  final ceilings = <int>[
    if (aircraft.serviceCeilingFeet != null) aircraft.serviceCeilingFeet!,
    if (aircraft.maximumOperatingAltitudeFeet != null)
      aircraft.maximumOperatingAltitudeFeet!,
  ];
  if (ceilings.isEmpty) {
    return null;
  }
  return ceilings.reduce((a, b) => a < b ? a : b) > highAltitudeThresholdFeet;
}

/// Whether a **type rating** is required under FAA rules.
///
/// `§61.31(a)`: aeroplanes of more than 12,500 lb maximum certificated takeoff
/// weight, and turbojet-powered aeroplanes regardless of weight.
///
/// Returns null when the mass is unknown and the aircraft is not turbojet —
/// the weight limb cannot then be evaluated. A turbojet answers true
/// regardless of mass, so an unknown mass does not make it unanswerable.
///
/// Does **not** cover the third limb, "other aircraft specified by the
/// Administrator through aircraft type certificate procedures". That is a
/// lookup rather than a calculation, and lands on
/// [Aircraft.typeRatingDesignator] like the EASA rating-list case.
bool? requiresFaaTypeRating(Aircraft aircraft) {
  // "Turbojet-powered" covers turbofans. `docs/ratings-and-endorsements.md` §5
  // gives the Citation Mustang as the example that surprises people — it needs
  // a type rating at 8,645 lb, well under the weight limb, and its engines are
  // turbofans. Reading the limb narrowly would let every light jet through.
  if (aircraft.engineType == EngineType.turbojet ||
      aircraft.engineType == EngineType.turbofan) {
    return true;
  }

  final mass = aircraft.maximumTakeoffMass;
  if (mass == null) {
    return null;
  }
  return mass.exceeds(faaTypeRatingMassThreshold);
}

/// Whether the aircraft is **technically advanced** under `§61.129(j)`.
///
/// Requires all three of an electronic primary flight display, a multifunction
/// display showing a moving map with GPS, and a two-axis autopilot integrated
/// with navigation and heading guidance.
///
/// Note this is *not* the same test as EASA's EFIS differences-training item
/// under `GM1 FCL.700`, which is why
/// [AircraftEquipment.electronicFlightInstrumentSystem] is a separate fact and
/// is not consulted here. A glass panel can satisfy one and not the other.
bool isTechnicallyAdvanced(Aircraft aircraft) =>
    aircraft.equipment.contains(AircraftEquipment.primaryFlightDisplay) &&
    aircraft.equipment.contains(
      AircraftEquipment.multiFunctionDisplayWithMovingMap,
    ) &&
    aircraft.equipment.contains(AircraftEquipment.integratedAutopilot);
