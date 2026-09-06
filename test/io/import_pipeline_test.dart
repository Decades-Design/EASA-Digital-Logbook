import 'package:drift/native.dart';
import 'package:easa_digital_log/data/database.dart';
import 'package:easa_digital_log/data/repositories/aircraft_repository.dart';
import 'package:easa_digital_log/data/repositories/flight_repository_drift.dart';
import 'package:easa_digital_log/domain/model/aircraft.dart';
import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:easa_digital_log/domain/repository/flight_read_repository.dart';
import 'package:easa_digital_log/io/canonical_import_row.dart';
import 'package:easa_digital_log/io/duplicate_matcher.dart';
import 'package:easa_digital_log/io/import_adapter.dart';
import 'package:easa_digital_log/io/import_pipeline.dart';
import 'package:flutter_test/flutter_test.dart';

const _capacity = PilotCapacity(
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

Flight _flight({String registration = 'N100AB', int hour = 10}) => Flight(
  aircraftRegistration: registration,
  route: const ['KABC', 'KDEF'],
  prePlannedNavigation: false,
  offBlocks: UtcInstant.utc(2026, 1, 1, hour),
  onBlocks: UtcInstant.utc(2026, 1, 1, hour + 1),
  capacity: _capacity,
  carryingPassengers: false,
  takeoffs: const CircuitCounts(dayFullStop: 1),
  landings: const CircuitCounts(dayFullStop: 1),
  ifrFlightPlanFiled: false,
  actualInstrumentTime: FlightDuration.zero,
  simulatedInstrumentTime: FlightDuration.zero,
  approaches: const [],
  holdingProceduresCount: 0,
  trackingPerformed: false,
  remarks: '',
);

const _importedAircraft = Aircraft(
  registration: 'N100AB',
  manufacturer: 'Cessna',
  model: '172',
  category: AircraftCategory.aeroplane,
  engineType: EngineType.piston,
  engineCount: 1,
  operatingSurface: OperatingSurface.land,
  requiresMultiCrew: false,
);

void main() {
  group('buildImportPreview', () {
    test('pairs every row with its duplicate verdict and passes errors '
        'through unchanged', () {
      final duplicateFlight = _flight(hour: 10);
      final newFlight = _flight(hour: 14);
      final existing = FlightRecord(
        id: 'existing-1',
        flight: duplicateFlight,
        aircraft: _importedAircraft,
      );

      final parseResult = ImportParseResult(
        rows: [
          CanonicalImportRow(
            sourceRowNumber: 2,
            flight: duplicateFlight,
            aircraft: _importedAircraft,
          ),
          CanonicalImportRow(
            sourceRowNumber: 3,
            flight: newFlight,
            aircraft: _importedAircraft,
          ),
        ],
        errors: const [ImportRowError(rowNumber: 4, message: 'bad row')],
      );

      final preview = buildImportPreview(
        parseResult: parseResult,
        existingFlights: [existing],
      );

      expect(preview.rows, hasLength(2));
      expect(preview.rows[0].duplicate?.confidence, DuplicateConfidence.exact);
      expect(preview.rows[1].duplicate, isNull);
      expect(preview.errors, parseResult.errors);
    });
  });

  group('applyImport', () {
    late AppDatabase db;
    late AircraftRepository aircraftRepository;
    late DriftFlightRepository flightRepository;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
      aircraftRepository = AircraftRepository(db);
      flightRepository = DriftFlightRepository(db);
    });

    tearDown(() => db.close());

    test(
      'a never-seen registration gets a new aircraft record created for it',
      () async {
        await applyImport(
          rows: [
            CanonicalImportRow(
              sourceRowNumber: 2,
              flight: _flight(),
              aircraft: _importedAircraft,
            ),
          ],
          sourceLabel: 'Test importer',
          aircraftRepository: aircraftRepository,
          flightRepository: flightRepository,
        );

        final storedAircraft = await db.select(db.aircraftsTable).get();
        expect(storedAircraft, hasLength(1));
        expect(storedAircraft.single.registration, 'N100AB');

        final storedFlights = await db.select(db.flightsTable).get();
        expect(storedFlights, hasLength(1));
        expect(storedFlights.single.aircraftId, storedAircraft.single.id);
      },
    );

    test('an existing registration reuses its stored aircraft id rather than '
        'overwriting it with the freshly-parsed aircraft', () async {
      final existingId = await aircraftRepository.upsert(
        const Aircraft(
          registration: 'N100AB',
          manufacturer: 'Cessna',
          model: '172 (hand-corrected)',
          category: AircraftCategory.aeroplane,
          engineType: EngineType.piston,
          engineCount: 1,
          operatingSurface: OperatingSurface.land,
          requiresMultiCrew: false,
        ),
      );

      await applyImport(
        rows: [
          CanonicalImportRow(
            sourceRowNumber: 2,
            flight: _flight(),
            // A freshly-parsed aircraft with different model text --
            // must not clobber the pilot's hand-corrected record.
            aircraft: _importedAircraft,
          ),
        ],
        sourceLabel: 'Test importer',
        aircraftRepository: aircraftRepository,
        flightRepository: flightRepository,
      );

      final storedAircraft = await db.select(db.aircraftsTable).get();
      expect(storedAircraft, hasLength(1));
      expect(storedAircraft.single.id, existingId);
      expect(storedAircraft.single.model, '172 (hand-corrected)');
    });

    test('two rows sharing a registration resolve to the same stored aircraft, '
        'created once', () async {
      await applyImport(
        rows: [
          CanonicalImportRow(
            sourceRowNumber: 2,
            flight: _flight(hour: 9),
            aircraft: _importedAircraft,
          ),
          CanonicalImportRow(
            sourceRowNumber: 3,
            flight: _flight(hour: 14),
            aircraft: _importedAircraft,
          ),
        ],
        sourceLabel: 'Test importer',
        aircraftRepository: aircraftRepository,
        flightRepository: flightRepository,
      );

      final storedAircraft = await db.select(db.aircraftsTable).get();
      expect(storedAircraft, hasLength(1));

      final storedFlights = await db.select(db.flightsTable).get();
      expect(storedFlights, hasLength(2));
      expect(
        storedFlights.every((f) => f.aircraftId == storedAircraft.single.id),
        isTrue,
      );
    });

    test(
      'the returned batch id is recorded and covers every imported row',
      () async {
        final batchId = await applyImport(
          rows: [
            CanonicalImportRow(
              sourceRowNumber: 2,
              flight: _flight(hour: 9),
              aircraft: _importedAircraft,
            ),
            CanonicalImportRow(
              sourceRowNumber: 3,
              flight: _flight(hour: 14),
              aircraft: _importedAircraft,
            ),
          ],
          sourceLabel: 'Test importer',
          aircraftRepository: aircraftRepository,
          flightRepository: flightRepository,
        );

        final batches = await flightRepository.listImportBatches();
        expect(batches.single.id, batchId);
        expect(batches.single.sourceLabel, 'Test importer');
        expect(batches.single.flightCount, 2);
      },
    );
  });
}
