import '../../domain/model/aircraft.dart';

/// A pilot's own fleet — the aircraft they've flown before, offered first
/// when picking a registration (docs/entry-form.md §10: "recent aircraft
/// ... pinned to the top"). Static sample data, matching the convention
/// `lib/ui/logbook/sample_logbook_data.dart` already established: real data
/// is `AircraftRepository`, which has no `findAll`/search method yet (#56).
///
/// [displayChips] are short type-rating/class-rating tags shown next to the
/// registration — display sugar, not a domain field; the underlying
/// qualification facts live on [Aircraft.requiredQualifications].
class SampleFleetAircraft {
  const SampleFleetAircraft({
    required this.aircraft,
    required this.displayChips,
    required this.pushbackOperations,
  });

  final Aircraft aircraft;

  /// e.g. `['P28A', 'SEP land', 'SP']`.
  final List<String> displayChips;

  /// Whether this type routinely operates with a pushback/tow start —
  /// surfaces the EASA-first-movement-vs-FAA-own-power note
  /// (docs/entry-form.md §2). True only for the multi-pilot jet in this
  /// sample set.
  final bool pushbackOperations;

  String get registration => aircraft.registration;

  String get typeLabel => '${aircraft.manufacturer} ${aircraft.model}'.trim();
}

final List<SampleFleetAircraft> sampleFleet = [
  SampleFleetAircraft(
    aircraft: const Aircraft(
      registration: 'G-ARRW',
      manufacturer: 'Piper',
      model: 'PA-28-161 Warrior',
      icaoTypeDesignator: 'P28A',
      category: AircraftCategory.aeroplane,
      engineType: EngineType.piston,
      engineCount: 1,
      operatingSurface: OperatingSurface.land,
      requiresMultiCrew: false,
    ),
    displayChips: const ['P28A', 'SEP land', 'SP'],
    pushbackOperations: false,
  ),
  SampleFleetAircraft(
    aircraft: const Aircraft(
      registration: 'G-ABCD',
      manufacturer: 'Cessna',
      model: '152',
      icaoTypeDesignator: 'C152',
      category: AircraftCategory.aeroplane,
      engineType: EngineType.piston,
      engineCount: 1,
      operatingSurface: OperatingSurface.land,
      requiresMultiCrew: false,
    ),
    displayChips: const ['C152', 'SEP land', 'SP'],
    pushbackOperations: false,
  ),
  SampleFleetAircraft(
    aircraft: const Aircraft(
      registration: 'N456BD',
      manufacturer: 'Cirrus',
      model: 'SR22',
      icaoTypeDesignator: 'SR22',
      category: AircraftCategory.aeroplane,
      engineType: EngineType.piston,
      engineCount: 1,
      operatingSurface: OperatingSurface.land,
      requiresMultiCrew: false,
      requiredQualifications: {
        'us.faa.part61': {AircraftQualification.faaHighPerformance},
      },
    ),
    displayChips: const ['SR22', 'SEP land', 'SP', 'high-performance'],
    pushbackOperations: false,
  ),
  SampleFleetAircraft(
    aircraft: const Aircraft(
      registration: 'G-VMPS',
      manufacturer: 'Airbus',
      model: 'A320-214',
      icaoTypeDesignator: 'A320',
      category: AircraftCategory.aeroplane,
      engineType: EngineType.turbofan,
      engineCount: 2,
      operatingSurface: OperatingSurface.land,
      requiresMultiCrew: true,
      typeRatingDesignator: 'A320',
    ),
    displayChips: const ['A320', 'MET', 'MP', 'pushback ops'],
    pushbackOperations: true,
  ),
  SampleFleetAircraft(
    aircraft: const Aircraft(
      registration: 'G-HELI',
      manufacturer: 'Airbus',
      model: 'EC135 T2+',
      icaoTypeDesignator: 'EC35',
      category: AircraftCategory.helicopter,
      engineType: EngineType.turboprop,
      engineCount: 2,
      operatingSurface: OperatingSurface.land,
      requiresMultiCrew: false,
    ),
    displayChips: const ['EC35', 'SE helicopter', 'SP'],
    pushbackOperations: false,
  ),
];

/// Looks up a fleet entry by registration, case-insensitively. `null` when
/// [registration] doesn't match anything in [sampleFleet] — an unresolved
/// aircraft, never guessed (CLAUDE.md: "never guess a missing
/// discriminator").
SampleFleetAircraft? findFleetAircraft(String registration) {
  final needle = registration.trim().toUpperCase();
  if (needle.isEmpty) return null;
  for (final entry in sampleFleet) {
    if (entry.registration.toUpperCase() == needle) return entry;
  }
  return null;
}
