import 'package:easa_digital_log/domain/model/aircraft.dart';
import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:easa_digital_log/io/canonical_import_row.dart';
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

const _aircraft = Aircraft(
  registration: 'N12345',
  manufacturer: 'Cessna',
  model: '172',
  category: AircraftCategory.aeroplane,
  engineType: EngineType.piston,
  engineCount: 1,
  operatingSurface: OperatingSurface.land,
  requiresMultiCrew: false,
);

Flight _flight({String remarks = ''}) {
  final off = UtcInstant.utc(2026, 1, 1, 9);
  return Flight(
    aircraftRegistration: _aircraft.registration,
    route: const ['KABC', 'KABC'],
    prePlannedNavigation: false,
    offBlocks: off,
    onBlocks: off.add(const Duration(hours: 1)),
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
    remarks: remarks,
  );
}

void main() {
  group('mergeUnmappedFieldsIntoRemarks', () {
    test('is a no-op with no unmapped fields', () {
      expect(
        mergeUnmappedFieldsIntoRemarks('Local flight', {}),
        'Local flight',
      );
    });

    test('is a no-op when every unmapped value is blank', () {
      expect(
        mergeUnmappedFieldsIntoRemarks('Local flight', {
          'Pilot Comments': '',
          'Instructor Comments': '   ',
        }),
        'Local flight',
      );
    });

    test('appends a single field to existing remarks', () {
      expect(
        mergeUnmappedFieldsIntoRemarks('Local flight', {
          'Pilot Comments': 'Great weather',
        }),
        'Local flight — Pilot Comments: Great weather',
      );
    });

    test('appends without a leading separator when remarks were empty', () {
      expect(
        mergeUnmappedFieldsIntoRemarks('', {'Pilot Comments': 'Great weather'}),
        'Pilot Comments: Great weather',
      );
    });

    test('joins several unmapped fields and drops the blank ones', () {
      expect(
        mergeUnmappedFieldsIntoRemarks('', {
          'Pilot Comments': 'Great weather',
          'Instructor Comments': '',
          'Route': 'Direct',
        }),
        'Pilot Comments: Great weather; Route: Direct',
      );
    });
  });

  test('CanonicalImportRow carries a full Flight and Aircraft unmodified', () {
    final flight = _flight(remarks: 'Great weather');
    final row = CanonicalImportRow(
      sourceRowNumber: 3,
      flight: flight,
      aircraft: _aircraft,
      unmappedFields: const {'Route': 'Direct'},
      reviewNotes: const ['Approach count guessed from a blank column'],
    );

    expect(row.sourceRowNumber, 3);
    expect(row.flight, flight);
    expect(row.aircraft, _aircraft);
    expect(row.unmappedFields, {'Route': 'Direct'});
    expect(row.reviewNotes, ['Approach count guessed from a blank column']);
  });
}
