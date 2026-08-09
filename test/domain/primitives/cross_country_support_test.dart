// flutter_test re-exports test/group/expect from package:test_api, so plain
// Dart tests need no separate package:test dependency.
import 'package:easa_digital_log/domain/model/aerodrome.dart';
import 'package:easa_digital_log/domain/model/aerodrome_directory.dart';
import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/geo_coordinate.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:easa_digital_log/domain/primitives/cross_country_support.dart';
import 'package:flutter_test/flutter_test.dart';

/// Equatorial points, so `greatCircleDistanceNm` reduces to `60.04 nm` per
/// degree of longitude with no approximation — the same exact-distance
/// trick `geo_coordinate_test.dart` uses for its own quarter-of-the-equator
/// case, reused here so every distance in this file is a known, round
/// figure rather than an estimate.
GeoCoordinate _eq(double lonDegrees) =>
    GeoCoordinate(latitude: 0, longitude: lonDegrees);

AerodromeDirectory _aerodromes = AerodromeDirectory([
  Aerodrome(icaoCode: 'DEP', name: 'Departure', position: _eq(0)),
  Aerodrome(icaoCode: 'A60', name: 'A, 60nm out', position: _eq(1)),
  Aerodrome(icaoCode: 'B60', name: 'B, 60nm the other way', position: _eq(-1)),
  Aerodrome(icaoCode: 'F120', name: 'Far, 120nm out', position: _eq(2)),
]);

Flight _flight(List<String> route) => Flight(
  aircraftRegistration: 'G-TEST',
  route: route,
  prePlannedNavigation: false,
  offBlocks: UtcInstant.utc(2026, 1, 1, 9, 0),
  onBlocks: UtcInstant.utc(2026, 1, 1, 10, 30),
  capacity: const PilotCapacity(
    commandAuthority: true,
    soleManipulator: true,
    soleOccupant: true,
    multiPilotOperation: false,
    additionalCrewRequiredByRule: false,
    actingAsInstructor: false,
    actingAsExaminer: false,
    picusClaimed: false,
    picInterventionNotRequired: false,
  ),
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

void main() {
  group('landedAwayFromDeparture', () {
    test('false for a local out-and-back to the same aerodrome', () {
      expect(landedAwayFromDeparture(_flight(const ['DEP', 'DEP'])), isFalse);
    });

    test('true when any later waypoint differs from the departure', () {
      expect(landedAwayFromDeparture(_flight(const ['DEP', 'A60'])), isTrue);
    });

    test('is case-insensitive', () {
      expect(landedAwayFromDeparture(_flight(const ['dep', 'DEP'])), isFalse);
    });

    test('false for a route with no second waypoint at all', () {
      expect(landedAwayFromDeparture(_flight(const ['DEP'])), isFalse);
    });
  });

  group('aerodromesVisitedOtherThanDeparture', () {
    test('counts each distinct aerodrome once, departure excluded', () {
      final visited = aerodromesVisitedOtherThanDeparture(
        _flight(const ['DEP', 'A60', 'B60', 'DEP']),
      );
      expect(visited, {'A60', 'B60'});
    });

    test('a there-and-back-and-back-again route still counts A60 once', () {
      final visited = aerodromesVisitedOtherThanDeparture(
        _flight(const ['DEP', 'A60', 'DEP', 'A60', 'DEP']),
      );
      expect(visited, {'A60'});
    });
  });

  group('totalRouteDistanceNm', () {
    test('sums consecutive legs, not a single point-to-point figure', () {
      // DEP -> A60 (60.04) -> B60 (2 degrees = 120.08) -> DEP (60.04):
      // summing the legs gives roughly 240nm, far more than the ~0nm a
      // departure-to-final-destination reading would give for a route that
      // returns to its own start.
      final total = totalRouteDistanceNm(
        _flight(const ['DEP', 'A60', 'B60', 'DEP']),
        _aerodromes,
      );
      expect(total, isNotNull);
      expect(total, closeTo(240.16, 1));
    });

    test('null when fewer than two waypoints resolve', () {
      final total = totalRouteDistanceNm(
        _flight(const ['DEP', 'ZZZZ']),
        _aerodromes,
      );
      expect(total, isNull);
    });
  });

  group('furthestLandingDistanceFromDepartureNm', () {
    test('the furthest landing, not the final destination', () {
      // Goes out to F120 (120nm from DEP) then all the way back to DEP —
      // the final leg's distance is 0, but the flight plainly went 120nm
      // from its departure at some point.
      final furthest = furthestLandingDistanceFromDepartureNm(
        _flight(const ['DEP', 'F120', 'DEP']),
        _aerodromes,
      );
      expect(furthest, closeTo(120.08, 1));
    });

    test('null when the departure itself does not resolve', () {
      final furthest = furthestLandingDistanceFromDepartureNm(
        _flight(const ['ZZZZ', 'A60']),
        _aerodromes,
      );
      expect(furthest, isNull);
    });

    test('unresolvable intermediate waypoints are skipped, not fatal', () {
      final furthest = furthestLandingDistanceFromDepartureNm(
        _flight(const ['DEP', 'ZZZZ', 'F120']),
        _aerodromes,
      );
      expect(furthest, closeTo(120.08, 1));
    });
  });
}
