import 'package:easa_digital_log/io/foreflight/foreflight_aircraft_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, String> _row({String typeCode = ''}) => {
  'AircraftID': 'G-ABCD',
  'TypeCode': typeCode,
  'Make': 'Cessna',
  'Model': '152',
  'GearType': 'fixed_tricycle',
  'EngineType': 'Piston',
  'equipType (FAA)': 'aircraft',
  'aircraftClass (FAA)': 'airplane_single_engine_land',
  'complexAircraft (FAA)': 'FALSE',
  'taa (FAA)': 'FALSE',
  'highPerformance (FAA)': 'FALSE',
  'pressurized (FAA)': 'FALSE',
};

void main() {
  test('a real ICAO-shaped TypeCode is kept with no review note', () {
    final mapping = mapForeFlightAircraft(_row(typeCode: 'C152'))!;

    expect(mapping.aircraft.icaoTypeDesignator, 'C152');
    expect(mapping.reviewNotes, isEmpty);
  });

  test('a TypeCode that is not ICAO-shaped is kept as entered but flagged '
      '(#74: never invent, never silently trust)', () {
    final mapping = mapForeFlightAircraft(
      _row(typeCode: 'Cessna 152 (Aerobat)'),
    )!;

    expect(
      mapping.aircraft.icaoTypeDesignator,
      'Cessna 152 (Aerobat)',
      reason: "the pilot's own raw value is preserved, never dropped",
    );
    expect(
      mapping.reviewNotes,
      contains(contains('does not look like a real ICAO type designator')),
    );
  });

  test('a blank TypeCode leaves icaoTypeDesignator null with no note', () {
    final mapping = mapForeFlightAircraft(_row())!;

    expect(mapping.aircraft.icaoTypeDesignator, isNull);
    expect(mapping.reviewNotes, isEmpty);
  });
}
