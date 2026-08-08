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
