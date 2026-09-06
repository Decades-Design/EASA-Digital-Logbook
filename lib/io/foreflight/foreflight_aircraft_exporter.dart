import '../../domain/model/aircraft.dart';

const _easaJurisdictionId = 'eu.easa.part-fcl';
const _faaJurisdictionId = 'us.faa.part61';

/// Reverse of `foreflight_aircraft_mapper.dart`'s `_engineTypes` map.
/// [EngineType.none] has no ForeFlight string — the import side only ever
/// produces it as a fallback for an unrecognised value, so there is nothing
/// authentic to write back.
const Map<EngineType, String> _engineTypeStrings = {
  EngineType.piston: 'Piston',
  EngineType.turboprop: 'Turboprop',
  EngineType.turbojet: 'Turbojet',
  EngineType.turbofan: 'Turbofan',
  EngineType.electric: 'Electric',
};

bool _hasQualification(
  Aircraft aircraft,
  String jurisdictionId,
  AircraftQualification qualification,
) =>
    aircraft.requiredQualifications[jurisdictionId]?.contains(qualification) ??
    false;

/// Reverse of `foreflight_aircraft_mapper.dart`'s `_isTailwheel`/
/// `_isRetractable` string parsing — either jurisdiction recording tailwheel
/// is enough evidence to write it back; retractable gear has no FAA
/// qualification value in this app's model at all (`§61.31(e)`'s complex
/// endorsement folds it in with flaps and a controllable-pitch prop instead
/// of tracking it alone), so only the EASA flag is checked for it.
String _gearType(Aircraft aircraft) {
  final tailwheel =
      _hasQualification(
        aircraft,
        _faaJurisdictionId,
        AircraftQualification.faaTailwheel,
      ) ||
      _hasQualification(
        aircraft,
        _easaJurisdictionId,
        AircraftQualification.easaTailwheel,
      );
  final retractable = _hasQualification(
    aircraft,
    _easaJurisdictionId,
    AircraftQualification.easaRetractableUndercarriage,
  );

  return switch ((tailwheel, retractable)) {
    (true, true) => 'retractable_tailwheel',
    (true, false) => 'fixed_tailwheel',
    (false, true) => 'retractable_tricycle',
    (false, false) => 'fixed_tricycle',
  };
}

/// Reverse of `foreflight_aircraft_mapper.dart`'s `_parseAircraftClass` —
/// only reconstructed precisely enough for the import side's own
/// `startsWith`/`contains` checks to recover [Aircraft.category],
/// [Aircraft.engineCount] and [Aircraft.operatingSurface] correctly; the
/// exact string ForeFlight itself would have generated for helicopters,
/// gliders and lighter-than-air categories is not otherwise reconstructed
/// (this app has no more detail than the bare category for those).
String? _aircraftClass(Aircraft aircraft) {
  final surface = switch (aircraft.operatingSurface) {
    OperatingSurface.amphibian => 'amphibian',
    OperatingSurface.sea => 'sea',
    OperatingSurface.land => 'land',
  };
  final engineArity = aircraft.engineCount > 1
      ? 'multi_engine'
      : 'single_engine';

  return switch (aircraft.category) {
    AircraftCategory.aeroplane => 'airplane_${engineArity}_$surface',
    AircraftCategory.helicopter => 'helicopter',
    AircraftCategory.glider => 'glider',
    AircraftCategory.poweredLift => 'powered_lift',
    AircraftCategory.airship => 'lighter_than_air_airship',
    AircraftCategory.balloon => 'lighter_than_air_balloon',
    // touringMotorGlider/poweredParachute: no ForeFlight aircraftClass
    // string is known to correspond to either — left blank rather than
    // guessing one that its own importer wouldn't recognise anyway.
    AircraftCategory.touringMotorGlider ||
    AircraftCategory.poweredParachute => null,
  };
}

/// Maps [aircraft] to one row of ForeFlight's aircraft-table columns
/// (`AircraftID`..`pressurized (FAA)`), the reverse of
/// `foreflight_aircraft_mapper.dart`'s `mapForeFlightAircraft`.
///
/// `Year`, `taa (FAA)` and `pressurized (FAA)` are always blank — this
/// app's [Aircraft] carries no year-built field, and the import side's own
/// dartdoc already documents `taa`/`pressurized` as having no canonical
/// equivalent to read back from. `equipType (FAA)` is always `aircraft`:
/// this app never creates an [Aircraft] record for a simulator (FSTD
/// sessions are a separate, unbuilt form — CLAUDE.md), so there is never a
/// `ftd` row to write.
Map<String, String> exportForeFlightAircraftRow(Aircraft aircraft) => {
  'AircraftID': aircraft.registration,
  'TypeCode': aircraft.icaoTypeDesignator ?? '',
  'Year': '',
  'Make': aircraft.manufacturer,
  'Model': aircraft.model,
  'GearType': _gearType(aircraft),
  'EngineType': _engineTypeStrings[aircraft.engineType] ?? '',
  'equipType (FAA)': 'aircraft',
  'aircraftClass (FAA)': _aircraftClass(aircraft) ?? '',
  'complexAircraft (FAA)':
      _hasQualification(
        aircraft,
        _faaJurisdictionId,
        AircraftQualification.faaComplex,
      )
      ? 'TRUE'
      : '',
  'taa (FAA)': '',
  'highPerformance (FAA)':
      _hasQualification(
        aircraft,
        _faaJurisdictionId,
        AircraftQualification.faaHighPerformance,
      )
      ? 'TRUE'
      : '',
  'pressurized (FAA)': '',
};
