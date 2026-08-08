// flutter_test re-exports test/group/expect from package:test_api, so plain
// Dart tests need no separate package:test dependency.
import 'package:easa_digital_log/domain/model/aerodrome.dart';
import 'package:easa_digital_log/domain/model/aerodrome_directory.dart';
import 'package:easa_digital_log/domain/model/aircraft.dart';
import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/geo_coordinate.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:easa_digital_log/domain/primitives/easa_cross_country_time.dart';
import 'package:flutter_test/flutter_test.dart';

/// Equatorial points give exact, round distances (60.04 nm per degree of
/// longitude) — the same trick `geo_coordinate_test.dart` and
/// `cross_country_support_test.dart` use.
GeoCoordinate _eq(double lonDegrees) =>
    GeoCoordinate(latitude: 0, longitude: lonDegrees);

final _aerodromes = AerodromeDirectory([
  Aerodrome(icaoCode: 'DEP', name: 'Departure', position: _eq(0)),
  // ~60nm from DEP.
  Aerodrome(icaoCode: 'A60', name: 'A, 60nm out', position: _eq(1)),
  // ~60nm from DEP the other way — combined with A60 on one route, this
  // gives a total flown distance (DEP-A60-B60-DEP) comfortably over the
  // 150nm/270km qualifying threshold even though neither leg alone is.
  Aerodrome(icaoCode: 'B60', name: 'B, 60nm the other way', position: _eq(-1)),
  // Two aerodromes a few nm from DEP — enough of them to satisfy the "two
  // other aerodromes" count, nowhere near enough distance.
  Aerodrome(icaoCode: 'N1', name: 'N1, ~3nm out', position: _eq(0.05)),
  Aerodrome(icaoCode: 'N2', name: 'N2, ~5nm out', position: _eq(0.08)),
]);

Aircraft _aircraft() => const Aircraft(
  registration: 'G-TEST',
  manufacturer: 'Test',
  model: 'Test',
  category: AircraftCategory.aeroplane,
  engineType: EngineType.piston,
  engineCount: 1,
  operatingSurface: OperatingSurface.land,
  requiresMultiCrew: false,
);

Flight _flight(List<String> route) => Flight(
  aircraftRegistration: 'G-TEST',
  route: route,
  offBlocks: UtcInstant.utc(2026, 1, 1, 9, 0),
  onBlocks: UtcInstant.utc(2026, 1, 1, 11, 0),
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
  group(
    'easaCrossCountryTime — a local flight (out and back, no landing elsewhere)',
    () {
      final flight = _flight(const ['DEP', 'DEP']);
      final result = easaCrossCountryTime(flight, _aircraft(), _aerodromes);

      test('is not cross-country at all', () {
        expect(result['crossCountry']?.value, FlightDuration.zero);
        expect(result['crossCountry']?.creditable, isTrue);
      });

      test('does not qualify for licence issue either', () {
        expect(result['qualifyingCrossCountry']?.value, FlightDuration.zero);
        expect(result['qualifyingCrossCountry']?.creditable, isTrue);
      });
    },
  );

  group(
    'easaCrossCountryTime — a short navigation flight (one other aerodrome)',
    () {
      final flight = _flight(const ['DEP', 'A60']);
      final result = easaCrossCountryTime(flight, _aircraft(), _aerodromes);

      test('is cross-country — it landed away from departure', () {
        expect(result['crossCountry']?.value, const FlightDuration(120));
        expect(result['crossCountry']?.creditable, isTrue);
      });

      test('does not qualify for licence issue — one other aerodrome and too '
          'short, not two aerodromes and 150 NM', () {
        expect(result['qualifyingCrossCountry']?.value, FlightDuration.zero);
        expect(result['qualifyingCrossCountry']?.creditable, isTrue);
      });
    },
  );

  group('easaCrossCountryTime — a qualifying cross-country flight', () {
    // DEP -> A60 -> B60 -> DEP: full-stop landings at two aerodromes other
    // than departure, roughly 240nm total (well past 150nm/270km).
    final flight = _flight(const ['DEP', 'A60', 'B60', 'DEP']);
    final result = easaCrossCountryTime(flight, _aircraft(), _aerodromes);

    test('is cross-country', () {
      expect(result['crossCountry']?.value, const FlightDuration(120));
    });

    test('qualifies for licence issue under AMC1 FCL.210', () {
      expect(
        result['qualifyingCrossCountry']?.value,
        const FlightDuration(120),
      );
      expect(result['qualifyingCrossCountry']?.creditable, isTrue);
      expect(
        result['qualifyingCrossCountry']?.explanation,
        contains('qualifying cross-country flight'),
      );
    });
  });

  group(
    'easaCrossCountryTime — distance and aerodrome count are both required',
    () {
      test(
        'enough total distance but only one other aerodrome does not qualify',
        () {
          // DEP -> A60 -> DEP -> A60: ~180nm total, but A60 is the only
          // distinct aerodrome other than departure.
          final flight = _flight(const ['DEP', 'A60', 'DEP', 'A60']);
          final result = easaCrossCountryTime(flight, _aircraft(), _aerodromes);

          expect(result['qualifyingCrossCountry']?.value, FlightDuration.zero);
          expect(result['qualifyingCrossCountry']?.creditable, isTrue);
        },
      );

      test('two other aerodromes but nowhere near enough distance does not '
          'qualify', () {
        // DEP -> N1 -> N2 -> DEP: two distinct other aerodromes, but well
        // under 10nm total.
        final flight = _flight(const ['DEP', 'N1', 'N2', 'DEP']);
        final result = easaCrossCountryTime(flight, _aircraft(), _aerodromes);

        expect(result['qualifyingCrossCountry']?.value, FlightDuration.zero);
        expect(result['qualifyingCrossCountry']?.creditable, isTrue);
      });
    },
  );

  group('easaCrossCountryTime — position resolution', () {
    test('an unresolvable route reports the qualifying flag as unknown, but '
        'the general definition still works from route identifiers alone', () {
      final flight = _flight(const ['DEP', 'ZZZZ']);
      final result = easaCrossCountryTime(flight, _aircraft(), _aerodromes);

      expect(
        result['crossCountry']?.value,
        isNot(FlightDuration.zero),
        reason: 'general cross-country needs no position at all',
      );
      expect(result['qualifyingCrossCountry']?.creditable, isFalse);
    });
  });
}
