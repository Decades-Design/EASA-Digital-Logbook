import 'package:easa_digital_log/domain/model/aircraft.dart';
import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:easa_digital_log/domain/repository/flight_read_repository.dart';
import 'package:easa_digital_log/io/canonical_import_row.dart';
import 'package:easa_digital_log/io/duplicate_matcher.dart';
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

Flight _flight({
  String registration = 'N100AB',
  List<String> route = const ['KABC', 'KDEF'],
  required UtcInstant offBlocks,
  required UtcInstant onBlocks,
}) => Flight(
  aircraftRegistration: registration,
  route: route,
  prePlannedNavigation: false,
  offBlocks: offBlocks,
  onBlocks: onBlocks,
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

FlightRecord _record(String id, Flight flight) => FlightRecord(
  id: id,
  flight: flight,
  aircraft: Aircraft(
    registration: flight.aircraftRegistration,
    manufacturer: 'Unknown',
    model: 'Unknown',
    category: AircraftCategory.aeroplane,
    engineType: EngineType.piston,
    engineCount: 1,
    operatingSurface: OperatingSurface.land,
    requiresMultiCrew: false,
  ),
);

final _base = UtcInstant.utc(2026, 1, 1, 10, 0);

void main() {
  test('identical aircraft, route and block times is an exact duplicate', () {
    final existing = _record(
      'e1',
      _flight(
        offBlocks: _base,
        onBlocks: _base.add(const Duration(minutes: 90)),
      ),
    );
    final candidate = _flight(
      offBlocks: _base,
      onBlocks: _base.add(const Duration(minutes: 90)),
    );

    final match = findDuplicate(
      candidate: candidate,
      existingFlights: [existing],
    );

    expect(match?.confidence, DuplicateConfidence.exact);
    expect(match?.existingFlightId, 'e1');
  });

  test('the same flight logged a couple of minutes apart (rounding) is a '
      'likely duplicate, not exact', () {
    final existing = _record(
      'e1',
      _flight(
        offBlocks: _base,
        onBlocks: _base.add(const Duration(minutes: 90)),
      ),
    );
    final candidate = _flight(
      offBlocks: _base.add(const Duration(minutes: 2)),
      onBlocks: _base.add(const Duration(minutes: 92)),
    );

    final match = findDuplicate(
      candidate: candidate,
      existingFlights: [existing],
    );

    expect(match?.confidence, DuplicateConfidence.likely);
    expect(match?.existingFlightId, 'e1');
  });

  test('two identical circuits an hour apart are genuinely distinct flights, '
      'not duplicates', () {
    final existing = _record(
      'e1',
      _flight(
        offBlocks: _base,
        onBlocks: _base.add(const Duration(minutes: 90)),
      ),
    );
    final candidate = _flight(
      offBlocks: _base.add(const Duration(hours: 1)),
      onBlocks: _base.add(const Duration(hours: 1, minutes: 90)),
    );

    final match = findDuplicate(
      candidate: candidate,
      existingFlights: [existing],
    );

    expect(match, isNull);
  });

  test('a different aircraft flying the same route at the same time is not '
      'a duplicate', () {
    final existing = _record(
      'e1',
      _flight(
        registration: 'N100AB',
        offBlocks: _base,
        onBlocks: _base.add(const Duration(minutes: 90)),
      ),
    );
    final candidate = _flight(
      registration: 'N999ZZ',
      offBlocks: _base,
      onBlocks: _base.add(const Duration(minutes: 90)),
    );

    final match = findDuplicate(
      candidate: candidate,
      existingFlights: [existing],
    );

    expect(match, isNull);
  });

  test('the same aircraft at the same time but a different destination is '
      'not a duplicate', () {
    final existing = _record(
      'e1',
      _flight(
        route: const ['KABC', 'KDEF'],
        offBlocks: _base,
        onBlocks: _base.add(const Duration(minutes: 90)),
      ),
    );
    final candidate = _flight(
      route: const ['KABC', 'KXYZ'],
      offBlocks: _base,
      onBlocks: _base.add(const Duration(minutes: 90)),
    );

    final match = findDuplicate(
      candidate: candidate,
      existingFlights: [existing],
    );

    expect(match, isNull);
  });

  test('the tolerance boundary is inclusive at 5 minutes and exclusive just '
      'past it', () {
    final existing = _record(
      'e1',
      _flight(
        offBlocks: _base,
        onBlocks: _base.add(const Duration(minutes: 90)),
      ),
    );

    final atBoundary = _flight(
      offBlocks: _base.add(const Duration(minutes: 5)),
      onBlocks: _base.add(const Duration(minutes: 95)),
    );
    expect(
      findDuplicate(
        candidate: atBoundary,
        existingFlights: [existing],
      )?.confidence,
      DuplicateConfidence.likely,
    );

    final pastBoundary = _flight(
      offBlocks: _base.add(const Duration(minutes: 6)),
      onBlocks: _base.add(const Duration(minutes: 96)),
    );
    expect(
      findDuplicate(candidate: pastBoundary, existingFlights: [existing]),
      isNull,
    );
  });

  test(
    'aircraft registration matching is case- and whitespace-insensitive',
    () {
      final existing = _record(
        'e1',
        _flight(
          registration: 'N100AB',
          offBlocks: _base,
          onBlocks: _base.add(const Duration(minutes: 90)),
        ),
      );
      final candidate = _flight(
        registration: ' n100ab ',
        offBlocks: _base,
        onBlocks: _base.add(const Duration(minutes: 90)),
      );

      final match = findDuplicate(
        candidate: candidate,
        existingFlights: [existing],
      );

      expect(match?.confidence, DuplicateConfidence.exact);
    },
  );

  test('an exact match is preferred over a closer-in-list likely match', () {
    final likelyButFirst = _record(
      'likely',
      _flight(
        offBlocks: _base.add(const Duration(minutes: 1)),
        onBlocks: _base.add(const Duration(minutes: 91)),
      ),
    );
    final exactButSecond = _record(
      'exact',
      _flight(
        offBlocks: _base,
        onBlocks: _base.add(const Duration(minutes: 90)),
      ),
    );
    final candidate = _flight(
      offBlocks: _base,
      onBlocks: _base.add(const Duration(minutes: 90)),
    );

    final match = findDuplicate(
      candidate: candidate,
      existingFlights: [likelyButFirst, exactButSecond],
    );

    expect(match?.confidence, DuplicateConfidence.exact);
    expect(match?.existingFlightId, 'exact');
  });

  test('findDuplicates maps every row to its own verdict, in order', () {
    final existing = _record(
      'e1',
      _flight(
        offBlocks: _base,
        onBlocks: _base.add(const Duration(minutes: 90)),
      ),
    );
    final duplicateRow = CanonicalImportRow(
      sourceRowNumber: 2,
      flight: _flight(
        offBlocks: _base,
        onBlocks: _base.add(const Duration(minutes: 90)),
      ),
      aircraft: existing.aircraft,
    );
    final newRow = CanonicalImportRow(
      sourceRowNumber: 3,
      flight: _flight(
        offBlocks: _base.add(const Duration(hours: 1)),
        onBlocks: _base.add(const Duration(hours: 1, minutes: 90)),
      ),
      aircraft: existing.aircraft,
    );

    final matches = findDuplicates(
      incoming: [duplicateRow, newRow],
      existingFlights: [existing],
    );

    expect(matches, hasLength(2));
    expect(matches[0]?.confidence, DuplicateConfidence.exact);
    expect(matches[1], isNull);
  });
}
