import '../../domain/model/aircraft.dart';

/// One aircraft-*type* row from Garmin's separate aircraft-types export
/// mapped to this app's own [Aircraft] model, plus any notes about
/// assumptions the mapping had to make.
///
/// [Aircraft.registration] is left blank here — Garmin's aircraft-types
/// file (#71) is keyed by *type* (`Name`, e.g. `PA28-161`), not by tail
/// number, unlike ForeFlight's aircraft table which lists one row per
/// registration. The registration only appears on the flight-log rows
/// (`Aircraft ID`), paired with an `Aircraft Type` naming which row of this
/// file describes it. [GarminAdapter] does that join and stamps the real
/// registration on via `copyWith` once it is known.
class GarminAircraftMapping {
  const GarminAircraftMapping({
    required this.aircraft,
    this.reviewNotes = const [],
  });

  final Aircraft aircraft;
  final List<String> reviewNotes;
}

const _easaJurisdictionId = 'eu.easa.part-fcl';
const _faaJurisdictionId = 'us.faa.part61';

/// Maps Garmin's `Engine Type` column. Blank or unrecognised values fall
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

/// Category, preferring `EASA Category` over `FAA Category` when both are
/// present — Garmin populates EASA Category for every aircraft type in
/// practice, while FAA Category is often blank even for FAA-relevant
/// types. `null` means neither value was recognised.
AircraftCategory? _parseCategory(String easaCategory, String faaCategory) {
  final value = easaCategory.isNotEmpty ? easaCategory : faaCategory;
  return switch (value.toLowerCase()) {
    'aeroplane' || 'airplane' => AircraftCategory.aeroplane,
    'helicopter' || 'rotorcraft' => AircraftCategory.helicopter,
    'glider' => AircraftCategory.glider,
    'tmg' || 'touring motor glider' => AircraftCategory.touringMotorGlider,
    'airship' => AircraftCategory.airship,
    'balloon' => AircraftCategory.balloon,
    'powered-lift' || 'powered lift' => AircraftCategory.poweredLift,
    'powered parachute' => AircraftCategory.poweredParachute,
    _ => null,
  };
}

/// Land, sea or amphibian, from `EASA Class` (e.g. `SEP Land`) or, failing
/// that, the FAA's four-letter class code (`ASEL`, `ASES`, `AMEL`, `AMES`),
/// which spells the surface out in its last letter rather than a whole
/// word. Defaults to land — the common GA case — when neither says
/// anything.
OperatingSurface _parseOperatingSurface(String easaClass, String faaClass) {
  final value = easaClass.isNotEmpty ? easaClass : faaClass;
  final lower = value.toLowerCase();
  if (lower.contains('amphibian')) return OperatingSurface.amphibian;
  if (lower.contains('sea')) return OperatingSurface.sea;
  if (lower.contains('land')) return OperatingSurface.land;
  if (value.endsWith('S')) return OperatingSurface.sea;
  return OperatingSurface.land;
}

bool _bool(Map<String, String> row, String column) =>
    (row[column] ?? '').toLowerCase() == 'true';

/// Maps one aircraft-type [row] to a real [Aircraft], or returns `null`
/// when it represents a simulator/FTD device rather than a real aircraft
/// (`Simulator` == `true`) or is missing the bare minimum (`Name` and
/// `Manufacturer`) to construct one at all.
///
/// The caller ([GarminAdapter]) is responsible for turning a `null` here
/// into a per-row [ImportRowError] for whichever flights reference this
/// type — the gap is real and belongs in front of the pilot, not silently
/// dropped, the same policy `foreflight_aircraft_mapper.dart` documents for
/// ForeFlight's equivalent case.
GarminAircraftMapping? mapGarminAircraft(Map<String, String> row) {
  final name = row['Name'] ?? '';
  if (name.isEmpty) return null;
  if (_bool(row, 'Simulator')) return null;

  final manufacturer = row['Manufacturer'] ?? '';
  if (manufacturer.isEmpty) return null;

  final notes = <String>[];

  final category = _parseCategory(
    row['EASA Category'] ?? '',
    row['FAA Category'] ?? '',
  );
  if (category == null) {
    notes.add(
      'Neither EASA Category nor FAA Category was recognised — category '
      'defaulted to aeroplane, verify.',
    );
  }

  final operatingSurface = _parseOperatingSurface(
    row['EASA Class'] ?? '',
    row['FAA Class'] ?? '',
  );

  final engineTypeRaw = row['Engine Type'] ?? '';
  final engineType = _engineTypes[engineTypeRaw];
  if (engineType == null && engineTypeRaw.isNotEmpty) {
    notes.add(
      'Engine Type "$engineTypeRaw" was not recognised — defaulted to none.',
    );
  }

  final engineCount = int.tryParse(row['Engine Count'] ?? '');
  if (engineCount == null) {
    notes.add('Engine Count was blank or unparseable — defaulted to 1.');
  }

  final tailWheel = _bool(row, 'Tail Wheel');
  final retractable = _bool(row, 'Retractable Landing Gear');

  final faaQualifications = <AircraftQualification>{
    if (_bool(row, 'FAA Complex')) AircraftQualification.faaComplex,
    if (_bool(row, 'FAA High Performance'))
      AircraftQualification.faaHighPerformance,
    if (tailWheel) AircraftQualification.faaTailwheel,
  };

  final easaQualifications = <AircraftQualification>{
    if (tailWheel) AircraftQualification.easaTailwheel,
    if (retractable) AircraftQualification.easaRetractableUndercarriage,
    if (_bool(row, 'EFIS'))
      AircraftQualification.easaElectronicFlightInstrumentSystem,
    if (_bool(row, 'Pressurized'))
      AircraftQualification.easaCabinPressurisation,
  };

  final requiredQualifications = <String, Set<AircraftQualification>>{
    if (faaQualifications.isNotEmpty) _faaJurisdictionId: faaQualifications,
    if (easaQualifications.isNotEmpty) _easaJurisdictionId: easaQualifications,
  };

  // Garmin's own "EASA Complex"/"EASA High Performance" flags bucket
  // several distinct EASA differences (variable pitch prop, retractable
  // gear, turbo/supercharged...) into one combined complexity flag, unlike
  // the FAA columns which name a single §61.31 endorsement each. Nothing
  // in AircraftQualification models that combined concept, so it can only
  // be flagged, not recorded.
  if (_bool(row, 'EASA Complex') || _bool(row, 'EASA High Performance')) {
    notes.add(
      "Garmin's EASA Complex/High Performance flags have no single "
      'equivalent here — EASA differentiates by specific item (retractable '
      'gear, EFIS, pressurisation, etc.) rather than one combined '
      'complexity flag. Check Retractable Landing Gear, EFIS and '
      'Pressurized above, or set qualifications manually.',
    );
  }

  if (_bool(row, 'FAA Type Rating Required') ||
      _bool(row, 'EASA Type Rating Required')) {
    notes.add(
      'A type rating is flagged as required, but Garmin does not name '
      'which one — set Aircraft.typeRatingDesignator manually.',
    );
  }

  if (_bool(row, 'FAA Large')) {
    notes.add(
      'FAA Large is set but has no equivalent AircraftQualification — not '
      'recorded.',
    );
  }

  if (_bool(row, 'Military')) {
    notes.add(
      'Military is set but has no equivalent field on Aircraft — not recorded.',
    );
  }

  return GarminAircraftMapping(
    aircraft: Aircraft(
      registration: '',
      manufacturer: manufacturer,
      model: name,
      category: category ?? AircraftCategory.aeroplane,
      engineType: engineType ?? EngineType.none,
      engineCount: engineCount ?? 1,
      operatingSurface: operatingSurface,
      requiresMultiCrew: false,
      requiredQualifications: requiredQualifications,
    ),
    reviewNotes: notes,
  );
}
