import '../../domain/model/aircraft.dart';
import '../icao_type_designator.dart';

/// One aircraft-table row mapped to this app's own [Aircraft] model, plus
/// any notes about assumptions the mapping had to make.
class ForeFlightAircraftMapping {
  const ForeFlightAircraftMapping({
    required this.aircraft,
    this.reviewNotes = const [],
  });

  final Aircraft aircraft;
  final List<String> reviewNotes;
}

const _easaJurisdictionId = 'eu.easa.part-fcl';
const _faaJurisdictionId = 'us.faa.part61';

/// Maps ForeFlight's `EngineType` column. Blank or unrecognised values fall
/// back to [EngineType.none] with a review note — never guessed as piston,
/// the common case, since a wrong engine type feeds directly into the EASA
/// class-rating suffix.
const Map<String, EngineType> _engineTypes = {
  'Piston': EngineType.piston,
  'Turboprop': EngineType.turboprop,
  'Turbojet': EngineType.turbojet,
  'Turbofan': EngineType.turbofan,
  'Electric': EngineType.electric,
};

/// Maps a ForeFlight `aircraftClass (FAA)` value (e.g.
/// `airplane_single_engine_land`) to this app's [AircraftCategory] and
/// [OperatingSurface] — the one column that carries both facts in a single
/// underscore-joined string.
class _ParsedAircraftClass {
  const _ParsedAircraftClass({
    required this.category,
    required this.operatingSurface,
    required this.isMultiEngine,
  });

  final AircraftCategory category;
  final OperatingSurface operatingSurface;
  final bool isMultiEngine;
}

_ParsedAircraftClass? _parseAircraftClass(String value) {
  final category = switch (value) {
    _ when value.startsWith('airplane_') => AircraftCategory.aeroplane,
    _ when value.startsWith('helicopter') => AircraftCategory.helicopter,
    _ when value.startsWith('glider') => AircraftCategory.glider,
    _ when value.startsWith('powered_lift') => AircraftCategory.poweredLift,
    _ when value.startsWith('lighter_than_air_airship') =>
      AircraftCategory.airship,
    _ when value.startsWith('lighter_than_air_balloon') =>
      AircraftCategory.balloon,
    _ => null,
  };
  if (category == null) return null;

  final operatingSurface = value.contains('amphibian')
      ? OperatingSurface.amphibian
      : value.contains('_sea')
      ? OperatingSurface.sea
      : OperatingSurface.land;

  return _ParsedAircraftClass(
    category: category,
    operatingSurface: operatingSurface,
    isMultiEngine: value.contains('multi_engine'),
  );
}

/// Whether ForeFlight's `GearType` column names a tailwheel arrangement —
/// `fixed_tailwheel` is the only value observed to; anything else (fixed or
/// retractable tricycle, floats) is not.
bool _isTailwheel(String gearType) => gearType.contains('tailwheel');

bool _isRetractable(String gearType) => gearType.startsWith('retractable');

/// Maps one aircraft-table [row] to a real [Aircraft], or returns `null`
/// when it has no canonical equivalent to map to at all:
///
/// - `equipType (FAA)` of `ftd` — a flight training device session, not an
///   aircraft. FSTD sessions are a separate form CLAUDE.md defers entirely
///   (`#58`'s dartdoc: "a different form, not built") — importing one as a
///   regular flight against a fabricated `Aircraft` would misrepresent
///   simulator time as aircraft time, a data-integrity violation this
///   adapter refuses to make.
/// - No `Make`/`Model` at all — ForeFlight's own aircraft table routinely
///   carries placeholder rows (a bare tail number with every other field
///   blank) for entries the pilot never filled in; there is nothing here
///   to construct a valid [Aircraft] from.
///
/// The caller (the flight mapper) is responsible for turning a `null` here
/// into a per-row [ImportRowError] for whichever flights reference this
/// registration — the gap is real and belongs in front of the pilot, not
/// silently dropped.
ForeFlightAircraftMapping? mapForeFlightAircraft(Map<String, String> row) {
  final registration = row['AircraftID'] ?? '';
  if (registration.isEmpty) return null;
  if (row['equipType (FAA)'] == 'ftd') return null;

  final manufacturer = row['Make'] ?? '';
  final model = row['Model'] ?? '';
  if (manufacturer.isEmpty && model.isEmpty) return null;

  final notes = <String>[];

  final parsedClass = _parseAircraftClass(row['aircraftClass (FAA)'] ?? '');
  final category = parsedClass?.category ?? AircraftCategory.aeroplane;
  if (parsedClass == null) {
    notes.add(
      'aircraftClass (FAA) was blank or unrecognised — category defaulted '
      'to aeroplane, verify.',
    );
  }
  final operatingSurface =
      parsedClass?.operatingSurface ?? OperatingSurface.land;

  final engineTypeRaw = row['EngineType'] ?? '';
  final engineType = _engineTypes[engineTypeRaw];
  if (engineType == null && engineTypeRaw.isNotEmpty) {
    notes.add(
      'EngineType "$engineTypeRaw" was not recognised — defaulted to none.',
    );
  }

  final engineCount = parsedClass?.isMultiEngine == true ? 2 : 1;
  if (parsedClass == null) {
    notes.add('Engine count defaulted to 1 — aircraftClass did not say.');
  }

  final gearType = row['GearType'] ?? '';
  final requiredQualifications = <String, Set<AircraftQualification>>{};

  final faaQualifications = <AircraftQualification>{
    if (row['complexAircraft (FAA)'] == 'TRUE')
      AircraftQualification.faaComplex,
    if (row['highPerformance (FAA)'] == 'TRUE')
      AircraftQualification.faaHighPerformance,
    if (_isTailwheel(gearType)) AircraftQualification.faaTailwheel,
  };
  if (faaQualifications.isNotEmpty) {
    requiredQualifications[_faaJurisdictionId] = faaQualifications;
  }

  final easaQualifications = <AircraftQualification>{
    if (_isTailwheel(gearType)) AircraftQualification.easaTailwheel,
    if (_isRetractable(gearType))
      AircraftQualification.easaRetractableUndercarriage,
  };
  if (easaQualifications.isNotEmpty) {
    requiredQualifications[_easaJurisdictionId] = easaQualifications;
  }

  for (final column in ['taa (FAA)', 'pressurized (FAA)']) {
    if (row[column] == 'TRUE') {
      notes.add(
        '$column is set but has no equivalent AircraftQualification — not '
        'recorded. Set it up manually in Aircraft management if it should '
        'gate a qualification.',
      );
    }
  }

  final typeCode = row['TypeCode'] ?? '';
  if (typeCode.isNotEmpty && !looksLikeIcaoTypeDesignator(typeCode)) {
    notes.add(
      'TypeCode "$typeCode" does not look like a real ICAO type designator '
      '— kept as entered, verify under Aircraft management.',
    );
  }

  return ForeFlightAircraftMapping(
    aircraft: Aircraft(
      registration: registration,
      manufacturer: manufacturer,
      model: model,
      icaoTypeDesignator: typeCode.isEmpty ? null : typeCode,
      category: category,
      engineType: engineType ?? EngineType.none,
      engineCount: engineCount,
      operatingSurface: operatingSurface,
      requiresMultiCrew: false,
      requiredQualifications: requiredQualifications,
    ),
    reviewNotes: notes,
  );
}
