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
import 'package:easa_digital_log/domain/primitives/faa_cross_country_time.dart';
import 'package:flutter_test/flutter_test.dart';

/// Equatorial points give exact, round distances (60.04 nm per degree of
/// longitude) — the same trick used throughout the cross-country test
/// files.
GeoCoordinate _eq(double lonDegrees) =>
    GeoCoordinate(latitude: 0, longitude: lonDegrees);

final _aerodromes = AerodromeDirectory([
  Aerodrome(icaoCode: 'DEP', name: 'Departure', position: _eq(0)),
  // ~18nm from DEP — over the 15nm powered-parachute bar, under the 25nm
  // sport-pilot/rotorcraft one.
  Aerodrome(icaoCode: 'P18', name: '18nm out', position: _eq(0.3)),
  // ~27nm from DEP — over the 25nm sport-pilot/rotorcraft bar, under the
  // 50nm general one.
  Aerodrome(icaoCode: 'R27', name: '27nm out', position: _eq(0.45)),
  // ~30nm from DEP — the first leg of the multi-leg case.
  Aerodrome(icaoCode: 'MID30', name: '30nm out', position: _eq(0.5)),
  // ~72nm from DEP, but only ~42nm from MID30 — the point that proves
  // distance must be measured from the original departure, not leg by leg.
  Aerodrome(icaoCode: 'FAR72', name: '72nm out', position: _eq(1.2)),
  // ~60nm from DEP — comfortably over every threshold at once.
  Aerodrome(icaoCode: 'F60', name: '60nm out', position: _eq(1)),
]);

Aircraft _aircraft(AircraftCategory category) => Aircraft(
  registration: 'N12345',
  manufacturer: 'Test',
  model: 'Test',
  category: category,
  engineType: EngineType.piston,
  engineCount: 1,
  operatingSurface: OperatingSurface.land,
  requiresMultiCrew: false,
);

Flight _flight(List<String> route) => Flight(
  aircraftRegistration: 'N12345',
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
  group('faaCrossCountryTime — the general (i) definition', () {
    test('a local out-and-back is not cross-country at all', () {
      final result = faaCrossCountryTime(
        _flight(const ['DEP', 'DEP']),
        _aircraft(AircraftCategory.aeroplane),
        _aerodromes,
      );
      expect(result['crossCountry']?.value, FlightDuration.zero);
      // Every credit test must give the same reason — "not cross-country
      // at all" — rather than silently falling through to "too short" with
      // a distance figure that happens to also be zero.
      expect(
        result['crossCountryPrivateCommercialInstrument']?.explanation,
        contains('not cross-country time at all'),
      );
    });

    test(
      'any landing away from departure is cross-country, no minimum distance',
      () {
        final result = faaCrossCountryTime(
          _flight(const ['DEP', 'P18']),
          _aircraft(AircraftCategory.aeroplane),
          _aerodromes,
        );
        expect(result['crossCountry']?.value, const FlightDuration(120));
        expect(result['crossCountry']?.explanation, contains('§61.1(b)(3)(i)'));
      },
    );
  });

  group('faaCrossCountryTime — all seven quantities for one aeroplane flight '
      'well past every threshold', () {
    final result = faaCrossCountryTime(
      _flight(const ['DEP', 'F60']),
      _aircraft(AircraftCategory.aeroplane),
      _aerodromes,
    );

    test('the general definition and every non-excluded credit test pass', () {
      expect(result['crossCountry']?.creditable, isTrue);
      expect(result['crossCountry']?.value, isNot(FlightDuration.zero));
      expect(
        result['crossCountryPrivateCommercialInstrument']?.value,
        isNot(FlightDuration.zero),
      );
      expect(
        result['crossCountrySportPilot']?.value,
        isNot(FlightDuration.zero),
      );
      expect(
        result['crossCountryAirlineTransportPilot']?.value,
        isNot(FlightDuration.zero),
      );
      expect(result['crossCountryMilitary']?.value, isNot(FlightDuration.zero));
    });

    test('the powered-parachute and rotorcraft tests do not apply to an '
        'aeroplane, regardless of distance', () {
      expect(
        result['crossCountryPoweredParachute']?.value,
        FlightDuration.zero,
      );
      expect(
        result['crossCountryPoweredParachute']?.explanation,
        contains('does not apply'),
      );
      expect(result['crossCountryRotorcraft']?.value, FlightDuration.zero);
      expect(
        result['crossCountryRotorcraft']?.explanation,
        contains('does not apply'),
      );
    });
  });

  group('faaCrossCountryTime — multi-leg, from the original departure', () {
    test(
      'each leg under 50nm, but the furthest point from departure exceeds it',
      () {
        // DEP -> MID30 (30nm) -> FAR72 (42nm from MID30, 72nm from DEP).
        final result = faaCrossCountryTime(
          _flight(const ['DEP', 'MID30', 'FAR72']),
          _aircraft(AircraftCategory.aeroplane),
          _aerodromes,
        );

        expect(
          result['crossCountryPrivateCommercialInstrument']?.value,
          isNot(FlightDuration.zero),
          reason:
              '72nm from the original departure, even though no single '
              'leg reaches 50nm',
        );
      },
    );

    test('the reverse: returns to land at departure, but a landing along the '
        'way was over the threshold', () {
      // DEP -> FAR72 (72nm) -> DEP: the final leg's distance from
      // departure is zero, but FAR72 was still landed at.
      final result = faaCrossCountryTime(
        _flight(const ['DEP', 'FAR72', 'DEP']),
        _aircraft(AircraftCategory.aeroplane),
        _aerodromes,
      );

      expect(
        result['crossCountryPrivateCommercialInstrument']?.value,
        isNot(FlightDuration.zero),
        reason: 'the furthest landing point matters, not the final one',
      );
    });
  });

  group('faaCrossCountryTime — rotorcraft, the 25nm test', () {
    // 27nm: over the rotorcraft/sport-pilot 25nm bar, under the general
    // 50nm one — the case the general 50nm test alone would miss entirely.
    final result = faaCrossCountryTime(
      _flight(const ['DEP', 'R27']),
      _aircraft(AircraftCategory.helicopter),
      _aerodromes,
    );

    test('qualifies under the rotorcraft 25nm test', () {
      expect(
        result['crossCountryRotorcraft']?.value,
        isNot(FlightDuration.zero),
      );
      expect(
        result['crossCountryRotorcraft']?.explanation,
        contains('§61.1(b)(3)(v)'),
      );
    });

    test('does not qualify under the general 50nm test', () {
      expect(
        result['crossCountryPrivateCommercialInstrument']?.value,
        FlightDuration.zero,
      );
      expect(
        result['crossCountryPrivateCommercialInstrument']?.explanation,
        contains('needs more than 50'),
      );
    });

    test('the ATP and military tests do not apply to rotorcraft', () {
      expect(
        result['crossCountryAirlineTransportPilot']?.value,
        FlightDuration.zero,
      );
      expect(
        result['crossCountryAirlineTransportPilot']?.explanation,
        contains('does not apply'),
      );
      expect(result['crossCountryMilitary']?.value, FlightDuration.zero);
    });
  });

  group('faaCrossCountryTime — powered parachute, the 15nm test', () {
    // 18nm: over the powered-parachute 15nm bar, under everything else.
    final result = faaCrossCountryTime(
      _flight(const ['DEP', 'P18']),
      _aircraft(AircraftCategory.poweredParachute),
      _aerodromes,
    );

    test('qualifies under the powered-parachute 15nm test', () {
      expect(
        result['crossCountryPoweredParachute']?.value,
        isNot(FlightDuration.zero),
      );
      expect(
        result['crossCountryPoweredParachute']?.explanation,
        contains('§61.1(b)(3)(iv)'),
      );
    });

    test('the private/commercial/instrument and sport-pilot tests do not '
        'apply to a powered parachute', () {
      expect(
        result['crossCountryPrivateCommercialInstrument']?.value,
        FlightDuration.zero,
      );
      expect(
        result['crossCountryPrivateCommercialInstrument']?.explanation,
        contains('does not apply'),
      );
      expect(result['crossCountrySportPilot']?.value, FlightDuration.zero);
      expect(
        result['crossCountrySportPilot']?.explanation,
        contains('does not apply'),
      );
    });
  });

  group('faaCrossCountryTime — position resolution', () {
    test('an unresolvable route reports the distance tests as unknown', () {
      final result = faaCrossCountryTime(
        _flight(const ['DEP', 'ZZZZ']),
        _aircraft(AircraftCategory.aeroplane),
        _aerodromes,
      );

      expect(
        result['crossCountry']?.value,
        isNot(FlightDuration.zero),
        reason: 'the general definition needs no position at all',
      );
      expect(
        result['crossCountryPrivateCommercialInstrument']?.creditable,
        isFalse,
      );
    });
  });
}
