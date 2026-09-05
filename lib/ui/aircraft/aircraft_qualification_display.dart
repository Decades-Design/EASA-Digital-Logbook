/// Plain-language labels and short explanations for [AircraftQualification]
/// (#61) — the enum's own dartdoc in `domain/model/aircraft.dart` carries
/// the regulation citation for a developer; this is the same information
/// rephrased for a pilot filling in the aircraft form, drawing on
/// `docs/ratings-and-endorsements.md` §7's "what each qualification means"
/// reference table.
library;

import '../../domain/model/aircraft.dart';

class QualificationInfo {
  const QualificationInfo(this.label, this.explanation);
  final String label;
  final String explanation;
}

const Map<AircraftQualification, QualificationInfo> qualificationInfo = {
  AircraftQualification.faaComplex: QualificationInfo(
    'Complex',
    'Retractable landing gear, flaps, and a controllable-pitch propeller '
        '(§61.31(e)).',
  ),
  AircraftQualification.faaHighPerformance: QualificationInfo(
    'High performance',
    'An engine rated over 200 horsepower (§61.31(f)).',
  ),
  AircraftQualification.faaHighAltitude: QualificationInfo(
    'High altitude',
    'Service ceiling or maximum operating altitude above 25,000 ft MSL '
        '(§61.31(g)).',
  ),
  AircraftQualification.faaTailwheel: QualificationInfo(
    'Tailwheel',
    'Tailwheel-equipped aeroplane (§61.31(i)).',
  ),
  AircraftQualification.faaTowing: QualificationInfo(
    'Towing',
    'Glider or banner towing (§61.69).',
  ),
  AircraftQualification.easaVariablePitchPropeller: QualificationInfo(
    'Variable pitch propeller (VP)',
    'Fitted with a variable-pitch propeller.',
  ),
  AircraftQualification.easaRetractableUndercarriage: QualificationInfo(
    'Retractable undercarriage (RU)',
    'Retractable undercarriage — not applicable to seaplane classes.',
  ),
  AircraftQualification.easaTurboOrSupercharged: QualificationInfo(
    'Turbo/supercharged (T)',
    'Turbo- or super-charged engine.',
  ),
  AircraftQualification.easaCabinPressurisation: QualificationInfo(
    'Cabin pressurisation (P)',
    'Pressurised cabin.',
  ),
  AircraftQualification.easaTailwheel: QualificationInfo(
    'Tailwheel (TW)',
    'Tailwheel undercarriage.',
  ),
  AircraftQualification.easaElectronicFlightInstrumentSystem: QualificationInfo(
    'EFIS',
    'Electronic flight instrument system.',
  ),
  AircraftQualification.easaSingleLeverPowerControl: QualificationInfo(
    'Single lever power control (SLPC)',
    'A single lever controls power.',
  ),
  AircraftQualification.easaOtherEngineType: QualificationInfo(
    'Other engine type',
    'An engine type not otherwise listed here, per Article 2(8c).',
  ),
};

/// Which [AircraftQualification] values belong on which jurisdiction's
/// checklist — [Aircraft.requiredQualifications] is keyed by jurisdiction
/// id and each key's set only ever draws from its own family (`faa*` vs
/// `easa*`; see the enum's own dartdoc), so this is a fixed partition, not
/// something read from the jurisdiction registry.
const Map<String, List<AircraftQualification>> qualificationsByJurisdiction = {
  'us.faa.part61': [
    AircraftQualification.faaComplex,
    AircraftQualification.faaHighPerformance,
    AircraftQualification.faaHighAltitude,
    AircraftQualification.faaTailwheel,
    AircraftQualification.faaTowing,
  ],
  'eu.easa.part-fcl': [
    AircraftQualification.easaVariablePitchPropeller,
    AircraftQualification.easaRetractableUndercarriage,
    AircraftQualification.easaTurboOrSupercharged,
    AircraftQualification.easaCabinPressurisation,
    AircraftQualification.easaTailwheel,
    AircraftQualification.easaElectronicFlightInstrumentSystem,
    AircraftQualification.easaSingleLeverPowerControl,
    AircraftQualification.easaOtherEngineType,
  ],
};

const Map<String, String> qualificationJurisdictionLabels = {
  'eu.easa.part-fcl': 'EASA Part-FCL',
  'us.faa.part61': 'FAA Part 61',
};
