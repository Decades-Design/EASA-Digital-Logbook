// #39: development-only seed data. This is a `tool/` script, never compiled
// into the app — that alone satisfies "never available in release builds".
// Reads no assets and touches no `lib/ui/`, so it can run standalone:
//
//   dart run tool/seed_dev_data.dart <path-to-db-file> [--flights=300] [--years=3] [--seed=1234]
//
// Deletes and recreates the target file. FSTD sessions are not seeded —
// there is no persistence model for them yet (M2 design spec, "Non-goals").

import 'dart:io';
import 'dart:math';

import 'package:drift/native.dart';
import 'package:easa_digital_log/data/database.dart';
import 'package:easa_digital_log/data/repositories/aircraft_repository.dart';
import 'package:easa_digital_log/data/repositories/flight_repository_drift.dart';
import 'package:easa_digital_log/domain/model/aircraft.dart';
import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/instructor_presence.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.first.startsWith('-')) {
    stderr.writeln(
      'Usage: dart run tool/seed_dev_data.dart <path-to-db-file> '
      '[--flights=300] [--years=3] [--seed=1234]',
    );
    exit(64);
  }

  final dbPath = args.first;
  final options = <String, String>{
    for (final arg in args.skip(1))
      if (arg.startsWith('--') && arg.contains('='))
        arg.substring(2).split('=').first: arg.substring(2).split('=').last,
  };
  final flightCount = int.parse(options['flights'] ?? '300');
  final years = int.parse(options['years'] ?? '3');
  final seed = int.parse(
    options['seed'] ?? DateTime.now().millisecondsSinceEpoch.toString(),
  );
  final random = Random(seed);

  final dbFile = File(dbPath);
  if (await dbFile.exists()) {
    await dbFile.delete();
  }
  await dbFile.parent.create(recursive: true);

  final db = AppDatabase(NativeDatabase(dbFile));
  await db.customStatement('SELECT 1');
  final aircraftRepo = AircraftRepository(db);
  final flightRepo = DriftFlightRepository(db);

  final aircraftIds = <String>[];
  final registrationsById = <String, String>{};
  for (final aircraft in _seedAircraft) {
    final id = await aircraftRepo.upsert(aircraft);
    aircraftIds.add(id);
    registrationsById[id] = aircraft.registration;
  }

  final now = DateTime.now().toUtc();
  final earliest = DateTime.utc(now.year - years, now.month, now.day);
  final spanDays = now.difference(earliest).inDays;

  var committed = 0;
  var tombstoned = 0;
  var revised = 0;

  for (var i = 0; i < flightCount; i++) {
    final aircraftId = aircraftIds[random.nextInt(aircraftIds.length)];
    final offBlocks = earliest.add(
      Duration(
        days: random.nextInt(spanDays + 1),
        hours: random.nextInt(24),
        minutes: random.nextInt(60),
      ),
    );
    final flight = _randomFlight(
      random,
      offBlocks,
      registrationsById[aircraftId]!,
    );
    final id = await flightRepo.createDraft(flight, aircraftId: aircraftId);

    // Roughly two thirds of seeded flights are committed (exported at least
    // once), matching a logbook that is mostly historical with a handful of
    // recent drafts still being filled in.
    if (random.nextDouble() < 0.65) {
      await flightRepo.commit(id);
      committed++;

      // A slice of committed flights pick up a correction, to exercise
      // revision history.
      if (random.nextDouble() < 0.1) {
        await flightRepo.updateCommitted(
          id,
          flight.copyWith(remarks: '${flight.remarks} (corrected)'.trim()),
          reason: 'Seed data: simulated post-export correction',
        );
        revised++;
      }

      // A small slice are deleted-but-retained, to exercise tombstoning.
      if (random.nextDouble() < 0.03) {
        await flightRepo.tombstone(id, reason: 'Seed data: simulated void');
        tombstoned++;
      }
    }
  }

  await db.close();

  stdout.writeln(
    'Seeded $flightCount flights across ${aircraftIds.length} aircraft '
    'into $dbPath (seed=$seed): $committed committed, $revised revised, '
    '$tombstoned tombstoned.',
  );
}

const _capacityBase = PilotCapacity(
  commandAuthority: true,
  soleManipulator: true,
  soleOccupant: true,
  multiPilotOperation: false,
  additionalCrewRequiredByRule: false,
  actingAsInstructor: false,
  actingAsExaminer: false,
  picusClaimed: false,
  picInterventionNotRequired: false,
);

/// One of a handful of realistic flight shapes, picked at random per flight.
/// Not exhaustive of every `PilotCapacity` combination — just enough
/// variety to exercise night, IFR, multi-leg, instruction and PICUS
/// projections and currency rules downstream.
Flight _randomFlight(
  Random random,
  DateTime offBlocksUtc,
  String aircraftRegistration,
) {
  final archetype = random.nextInt(7);
  final durationMinutes = 30 + random.nextInt(150);
  final offBlocks = UtcInstant.fromDateTime(offBlocksUtc);
  final onBlocks = offBlocks.add(Duration(minutes: durationMinutes));
  final isNight = offBlocksUtc.hour >= 20 || offBlocksUtc.hour < 6;

  final route = archetype == 2
      ? _multiLegRoute(random)
      : [_randomIcao(random), _randomIcao(random)];

  final takeoffs = isNight
      ? const CircuitCounts(nightFullStop: 1)
      : const CircuitCounts(dayFullStop: 1);
  final landings = isNight
      ? const CircuitCounts(nightFullStop: 1)
      : const CircuitCounts(dayFullStop: 1);

  var capacity = _capacityBase;
  var ifrFlightPlanFiled = false;
  var actualInstrumentTime = FlightDuration.zero;
  var simulatedInstrumentTime = FlightDuration.zero;
  var approaches = const <Approach>[];
  var holdingProceduresCount = 0;
  var otherPilotName = '';
  var otherPilotCredentialNumber = '';

  switch (archetype) {
    case 0: // Ordinary solo PIC, VFR local.
      break;
    case 1: // Dual instruction received.
      capacity = capacity.copyWith(
        commandAuthority: false,
        soleOccupant: false,
        instructor: const InstructorPresence(
          capacity: InstructorCapacity.flightInstructor,
          influencedFlight: true,
          name: 'J. Reilly',
          credentialNumber: 'CFI-4471',
        ),
      );
      break;
    case 2: // Multi-leg cross-country, PIC.
      break;
    case 3: // Instruction given, as instructor.
      capacity = capacity.copyWith(
        soleOccupant: false,
        actingAsInstructor: true,
      );
      break;
    case 4: // PICUS under supervision.
      capacity = capacity.copyWith(
        commandAuthority: false,
        soleOccupant: false,
        soleManipulator: false,
        picusClaimed: true,
        picInterventionNotRequired: true,
        instructor: const InstructorPresence(
          capacity: InstructorCapacity.flightInstructor,
          influencedFlight: false,
          name: 'M. Okafor',
          credentialNumber: 'CFI-2290',
        ),
      );
      break;
    case 5: // IFR, actual instrument, with an approach and a hold.
      ifrFlightPlanFiled = true;
      actualInstrumentTime = FlightDuration(20 + random.nextInt(40));
      approaches = [
        Approach(
          type: ApproachType.ils,
          aerodromeIcao: route.last,
          runway: '${(random.nextInt(18) + 1) * 2}',
          count: 1 + random.nextInt(2),
        ),
      ];
      holdingProceduresCount = random.nextInt(2);
      break;
    case 6: // Simulated instrument under the hood, with a safety pilot.
      simulatedInstrumentTime = FlightDuration(15 + random.nextInt(30));
      capacity = capacity.copyWith(otherPilotRole: OtherPilotRole.safetyPilot);
      otherPilotName = 'S. Delacroix';
      otherPilotCredentialNumber = 'PPL-88214';
      break;
  }

  return Flight(
    aircraftRegistration: aircraftRegistration,
    route: route,
    prePlannedNavigation: route.length > 2,
    offBlocks: offBlocks,
    onBlocks: onBlocks,
    takeoff: offBlocks.add(const Duration(minutes: 5)),
    landing: onBlocks.subtract(const Duration(minutes: 5)),
    capacity: capacity,
    otherPilotName: otherPilotName.isEmpty ? null : otherPilotName,
    otherPilotCredentialNumber: otherPilotCredentialNumber.isEmpty
        ? null
        : otherPilotCredentialNumber,
    carryingPassengers: random.nextDouble() < 0.2,
    takeoffs: takeoffs,
    landings: landings,
    ifrFlightPlanFiled: ifrFlightPlanFiled,
    actualInstrumentTime: actualInstrumentTime,
    simulatedInstrumentTime: simulatedInstrumentTime,
    approaches: approaches,
    holdingProceduresCount: holdingProceduresCount,
    trackingPerformed: archetype == 5 || archetype == 6,
    remarks: archetype == 4 ? 'PICUS sector, supervised' : '',
  );
}

const _icaoCandidates = [
  'EGKA',
  'EGKB',
  'EGHH',
  'EGLF',
  'EGTB',
  'EGSS',
  'EGNX',
  'EGBJ',
];

String _randomIcao(Random random) =>
    _icaoCandidates[random.nextInt(_icaoCandidates.length)];

List<String> _multiLegRoute(Random random) {
  final legCount = 3 + random.nextInt(2);
  return List.generate(legCount, (_) => _randomIcao(random));
}

final _seedAircraft = [
  const Aircraft(
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
  const Aircraft(
    registration: 'G-ARRW',
    manufacturer: 'Piper',
    model: 'Arrow',
    icaoTypeDesignator: 'PA28',
    category: AircraftCategory.aeroplane,
    engineType: EngineType.piston,
    engineCount: 1,
    operatingSurface: OperatingSurface.land,
    requiresMultiCrew: false,
    requiredQualifications: {
      'us.faa.part61': {AircraftQualification.faaComplex},
      'eu.easa.part-fcl': {
        AircraftQualification.easaVariablePitchPropeller,
        AircraftQualification.easaRetractableUndercarriage,
      },
    },
  ),
  const Aircraft(
    registration: 'N456BD',
    manufacturer: 'Cessna',
    model: '206',
    icaoTypeDesignator: 'C206',
    category: AircraftCategory.aeroplane,
    engineType: EngineType.piston,
    engineCount: 1,
    operatingSurface: OperatingSurface.land,
    requiresMultiCrew: false,
    requiredQualifications: {
      'us.faa.part61': {AircraftQualification.faaHighPerformance},
    },
  ),
  const Aircraft(
    registration: 'G-MULTI',
    manufacturer: 'Beechcraft',
    model: 'Baron 58',
    icaoTypeDesignator: 'BE58',
    category: AircraftCategory.aeroplane,
    engineType: EngineType.piston,
    engineCount: 2,
    operatingSurface: OperatingSurface.land,
    requiresMultiCrew: false,
  ),
];
