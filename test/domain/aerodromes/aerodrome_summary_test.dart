import 'package:easa_digital_log/domain/aerodromes/aerodrome_summary.dart';
import 'package:easa_digital_log/domain/model/aerodrome.dart';
import 'package:easa_digital_log/domain/model/aerodrome_directory.dart';
import 'package:easa_digital_log/domain/model/aircraft.dart';
import 'package:easa_digital_log/domain/model/calendar_date.dart';
import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/geo_coordinate.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:easa_digital_log/domain/repository/flight_read_repository.dart';
import 'package:flutter_test/flutter_test.dart';

const _picCapacity = PilotCapacity(
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

const _testAircraft = Aircraft(
  registration: 'G-TEST',
  manufacturer: 'Cessna',
  model: '152',
  category: AircraftCategory.aeroplane,
  engineType: EngineType.piston,
  engineCount: 1,
  operatingSurface: OperatingSurface.land,
  requiresMultiCrew: false,
);

Flight _flight({required CalendarDate date, required List<String> route}) {
  final offBlocks = UtcInstant.utc(date.year, date.month, date.day, 10);
  return Flight(
    aircraftRegistration: 'G-TEST',
    route: route,
    prePlannedNavigation: false,
    offBlocks: offBlocks,
    onBlocks: offBlocks.add(const Duration(hours: 1)),
    capacity: _picCapacity,
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
}

FlightRecord _record(String id, Flight flight) =>
    FlightRecord(id: id, flight: flight, aircraft: _testAircraft);

AerodromeDirectory _directory() => AerodromeDirectory([
  Aerodrome(
    icaoCode: 'EGKA',
    name: 'Shoreham',
    position: GeoCoordinate(latitude: 50.8356, longitude: -0.2971),
    isoCountry: 'GB',
  ),
  Aerodrome(
    icaoCode: 'EGHH',
    name: 'Bournemouth',
    position: GeoCoordinate(latitude: 50.78, longitude: -1.8425),
    isoCountry: 'GB',
  ),
  Aerodrome(
    icaoCode: 'LFAT',
    name: 'Le Touquet',
    position: GeoCoordinate(latitude: 50.5172, longitude: 1.6208),
    isoCountry: 'FR',
  ),
]);

void main() {
  group('rankAerodromesByVisits', () {
    test('ranks aerodromes by number of flights that touched them', () {
      final flights = [
        _record(
          'f1',
          _flight(
            date: const CalendarDate(2026, 1, 1),
            route: ['EGKA', 'EGHH', 'EGKA'],
          ),
        ),
        _record(
          'f2',
          _flight(
            date: const CalendarDate(2026, 1, 2),
            route: ['EGKA', 'EGKA'],
          ),
        ),
        _record(
          'f3',
          _flight(
            date: const CalendarDate(2026, 1, 3),
            route: ['EGKA', 'LFAT', 'EGKA'],
          ),
        ),
      ];

      final ranked = rankAerodromesByVisits(flights, _directory());

      expect(ranked.map((v) => v.icao).toList(), ['EGKA', 'EGHH', 'LFAT']);
      expect(ranked[0].visitCount, 3);
      expect(ranked[1].visitCount, 1);
      expect(ranked[2].visitCount, 1);
      expect(ranked[0].aerodrome?.name, 'Shoreham');
    });

    test(
      'a flight visiting the same aerodrome twice in one route counts once',
      () {
        final flights = [
          _record(
            'f1',
            _flight(
              date: const CalendarDate(2026, 1, 1),
              route: ['EGKA', 'EGKA', 'EGKA'],
            ),
          ),
        ];

        final ranked = rankAerodromesByVisits(flights, _directory());

        expect(ranked, hasLength(1));
        expect(ranked.single.visitCount, 1);
      },
    );

    test('an unresolved ICAO code still ranks, with a null aerodrome', () {
      final flights = [
        _record(
          'f1',
          _flight(
            date: const CalendarDate(2026, 1, 1),
            route: ['EGKA', 'PRIVATE-STRIP'],
          ),
        ),
      ];

      final ranked = rankAerodromesByVisits(flights, _directory());

      final unresolved = ranked.firstWhere((v) => v.icao == 'PRIVATE-STRIP');
      expect(unresolved.aerodrome, isNull);
    });

    test('ties break by ICAO code', () {
      final flights = [
        _record(
          'f1',
          _flight(date: const CalendarDate(2026, 1, 1), route: ['LFAT']),
        ),
        _record(
          'f2',
          _flight(date: const CalendarDate(2026, 1, 2), route: ['EGHH']),
        ),
      ];

      final ranked = rankAerodromesByVisits(flights, _directory());

      expect(ranked.map((v) => v.icao).toList(), ['EGHH', 'LFAT']);
    });

    test('an empty flight set ranks nothing', () {
      expect(rankAerodromesByVisits(const [], _directory()), isEmpty);
    });
  });

  group('furthestAerodrome', () {
    test('returns the furthest visited aerodrome from the home base', () {
      final flights = [
        _record(
          'f1',
          _flight(
            date: const CalendarDate(2026, 1, 1),
            route: ['EGKA', 'EGHH', 'EGKA'],
          ),
        ),
        _record(
          'f2',
          _flight(
            date: const CalendarDate(2026, 1, 2),
            route: ['EGKA', 'LFAT', 'EGKA'],
          ),
        ),
      ];

      final furthest = furthestAerodrome(flights, _directory(), 'EGKA');

      // LFAT (Le Touquet, France) is further from EGKA than EGHH
      // (Bournemouth) is.
      expect(furthest?.icao, 'LFAT');
      expect(furthest?.nm, greaterThan(0));
    });

    test('returns null when the home base does not resolve', () {
      final flights = [
        _record(
          'f1',
          _flight(
            date: const CalendarDate(2026, 1, 1),
            route: ['EGKA', 'EGHH'],
          ),
        ),
      ];

      expect(furthestAerodrome(flights, _directory(), 'UNKNOWN'), isNull);
    });

    test('returns null when nothing else has been visited', () {
      final flights = [
        _record(
          'f1',
          _flight(date: const CalendarDate(2026, 1, 1), route: ['EGKA']),
        ),
      ];

      expect(furthestAerodrome(flights, _directory(), 'EGKA'), isNull);
    });

    test('returns null for an empty flight set', () {
      expect(furthestAerodrome(const [], _directory(), 'EGKA'), isNull);
    });
  });

  group('newAerodromesThisYear', () {
    test('counts aerodromes first visited in the given year', () {
      final flights = [
        _record(
          'f1',
          _flight(date: const CalendarDate(2025, 6, 1), route: ['EGKA']),
        ),
        _record(
          'f2',
          _flight(date: const CalendarDate(2026, 3, 1), route: ['EGHH']),
        ),
        _record(
          'f3',
          _flight(date: const CalendarDate(2026, 4, 1), route: ['LFAT']),
        ),
        // A later flight back to an aerodrome first visited last year
        // doesn't make it "new" this year.
        _record(
          'f4',
          _flight(date: const CalendarDate(2026, 5, 1), route: ['EGKA']),
        ),
      ];

      final count = newAerodromesThisYear(
        flights,
        const CalendarDate(2026, 12, 31),
      );

      expect(count, 2); // EGHH and LFAT
    });

    test('an empty flight set has no new aerodromes', () {
      expect(
        newAerodromesThisYear(const [], const CalendarDate(2026, 1, 1)),
        0,
      );
    });
  });
}
