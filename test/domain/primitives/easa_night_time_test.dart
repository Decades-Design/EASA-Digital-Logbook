// flutter_test re-exports test/group/expect from package:test_api, so plain
// Dart tests need no separate package:test dependency.
import 'package:easa_digital_log/domain/model/aerodrome.dart';
import 'package:easa_digital_log/domain/model/aerodrome_directory.dart';
import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/geo_coordinate.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:easa_digital_log/domain/primitives/easa_night_time.dart';
import 'package:flutter_test/flutter_test.dart';

/// London, used throughout because `test/domain/model/solar_position_test.dart`
/// already validates civil twilight for this exact position against the US
/// Naval Observatory: 2024-06-21 02:55Z-21:09Z, 2024-12-21 07:24Z-16:34Z.
final _london = GeoCoordinate(latitude: 51.5074, longitude: -0.1278);

AerodromeDirectory _directoryWith(Map<String, GeoCoordinate> aerodromes) =>
    AerodromeDirectory([
      for (final entry in aerodromes.entries)
        Aerodrome(icaoCode: entry.key, name: entry.key, position: entry.value),
    ]);

PilotCapacity _capacity() => const PilotCapacity(
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
  required List<String> route,
  required UtcInstant offBlocks,
  required UtcInstant onBlocks,
  UtcInstant? takeoff,
  UtcInstant? landing,
}) => Flight(
  aircraftRegistration: 'G-TEST',
  route: route,
  prePlannedNavigation: false,
  offBlocks: offBlocks,
  onBlocks: onBlocks,
  takeoff: takeoff,
  landing: landing,
  capacity: _capacity(),
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
    'easaNightTime — a stationary flight (departs and lands at London)',
    () {
      final aerodromes = _directoryWith({'EGXX': _london});

      test('wholly within daylight is zero night time', () {
        final flight = _flight(
          route: const ['EGXX', 'EGXX'],
          offBlocks: UtcInstant.utc(2024, 6, 21, 10, 0),
          onBlocks: UtcInstant.utc(2024, 6, 21, 11, 30),
        );

        final result = easaNightTime(flight, aerodromes);

        expect(result['night']?.value, FlightDuration.zero);
        expect(result['night']?.creditable, isTrue);
      });

      test('wholly within night is the full flight duration', () {
        // Civil twilight ends 21:09Z and begins again 02:55Z on this date —
        // 22:00Z to 23:00Z is well inside the fully-dark window.
        final flight = _flight(
          route: const ['EGXX', 'EGXX'],
          offBlocks: UtcInstant.utc(2024, 6, 21, 22, 0),
          onBlocks: UtcInstant.utc(2024, 6, 21, 23, 0),
        );

        final result = easaNightTime(flight, aerodromes);

        expect(result['night']?.value, const FlightDuration(60));
      });

      test('a flight crossing evening civil twilight splits correctly', () {
        // Civil twilight ends 16:34Z on the December solstice. A flight
        // 16:00Z-17:00Z should show roughly the first 34 minutes as day and
        // the last 26 as night.
        final flight = _flight(
          route: const ['EGXX', 'EGXX'],
          offBlocks: UtcInstant.utc(2024, 12, 21, 16, 0),
          onBlocks: UtcInstant.utc(2024, 12, 21, 17, 0),
        );

        final result = easaNightTime(flight, aerodromes);

        expect(result['night']?.value, isNot(FlightDuration.zero));
        expect(result['night']?.value, isNot(const FlightDuration(60)));
        expect(
          result['night']?.value.inMinutes,
          closeTo(26, 2),
          reason:
              '60 minutes minus the ~34 minutes still before civil '
              'twilight ends at 16:34Z',
        );
      });

      test('a flight crossing morning civil twilight splits correctly', () {
        // Civil twilight begins 07:24Z on the December solstice. A flight
        // 07:00Z-08:00Z should show roughly the first 24 minutes as night and
        // the last 36 as day.
        final flight = _flight(
          route: const ['EGXX', 'EGXX'],
          offBlocks: UtcInstant.utc(2024, 12, 21, 7, 0),
          onBlocks: UtcInstant.utc(2024, 12, 21, 8, 0),
        );

        final result = easaNightTime(flight, aerodromes);

        expect(
          result['night']?.value.inMinutes,
          closeTo(24, 2),
          reason: 'the ~24 minutes before civil twilight begins at 07:24Z',
        );
      });

      test('uses takeoff/landing in preference to offBlocks/onBlocks', () {
        // Block times span the whole dark period; airborne times are wholly
        // inside the daylight that follows. Only the takeoff/landing window
        // should be used for night, not the wider block window.
        final flight = _flight(
          route: const ['EGXX', 'EGXX'],
          offBlocks: UtcInstant.utc(2024, 6, 21, 22, 0),
          onBlocks: UtcInstant.utc(2024, 6, 21, 23, 0),
          takeoff: UtcInstant.utc(2024, 6, 21, 22, 0),
          landing: UtcInstant.utc(2024, 6, 21, 22, 0),
        );

        final result = easaNightTime(flight, aerodromes);

        expect(
          result['night']?.value,
          FlightDuration.zero,
          reason: 'a zero-length airborne window has no night time at all',
        );
        expect(
          result['night']?.explanation,
          isNot(contains('were not recorded')),
          reason: 'real airborne instants were used, so no caveat is owed',
        );
      });

      // #27: a missing takeoff/landing must not be silently blended into a
      // reading that looks identical to one measured against real airborne
      // instants.
      test('discloses the block-time substitution when takeoff/landing are '
          'not recorded', () {
        final flight = _flight(
          route: const ['EGXX', 'EGXX'],
          offBlocks: UtcInstant.utc(2024, 6, 21, 22, 0),
          onBlocks: UtcInstant.utc(2024, 6, 21, 23, 0),
        );

        final result = easaNightTime(flight, aerodromes);

        expect(result['night']?.explanation, contains('were not recorded'));
      });
    },
  );

  group('easaNightTime — position resolution', () {
    test('an unresolvable route reports it rather than guessing', () {
      final flight = _flight(
        route: const ['ZZZZ', 'ZZZZ'],
        offBlocks: UtcInstant.utc(2024, 6, 21, 22, 0),
        onBlocks: UtcInstant.utc(2024, 6, 21, 23, 0),
      );

      final result = easaNightTime(flight, _directoryWith(const {}));

      expect(result['night']?.creditable, isFalse);
      expect(result['night']?.explanation, contains('cannot be computed'));
    });

    test('one resolvable endpoint is used for the whole flight', () {
      final aerodromes = _directoryWith({'EGXX': _london});
      final flight = _flight(
        route: const ['ZZZZ', 'EGXX'],
        offBlocks: UtcInstant.utc(2024, 6, 21, 10, 0),
        onBlocks: UtcInstant.utc(2024, 6, 21, 11, 0),
      );

      final result = easaNightTime(flight, aerodromes);

      expect(result['night']?.creditable, isTrue);
      expect(result['night']?.value, FlightDuration.zero);
    });

    test('position genuinely interpolates: a flight from an already-dark '
        'position toward a still-light one is neither wholly day nor '
        'wholly night', () {
      // Same latitude and date as the validated London figures, but 30
      // degrees of longitude either side — roughly two hours of local
      // solar time earlier (east) and later (west) than London.
      final east = GeoCoordinate(latitude: 51.5074, longitude: 30);
      final west = GeoCoordinate(latitude: 51.5074, longitude: -30);
      final aerodromes = _directoryWith({'EGEA': east, 'EGWE': west});

      // London's own civil twilight ends 21:09Z on this date; departing
      // from the east (already past its own, earlier twilight end) at
      // 20:00Z and arriving in the west (not yet at its own, later
      // twilight end) at 22:00Z should straddle the transition.
      final flight = _flight(
        route: const ['EGEA', 'EGWE'],
        offBlocks: UtcInstant.utc(2024, 6, 21, 20, 0),
        onBlocks: UtcInstant.utc(2024, 6, 21, 22, 0),
      );

      final result = easaNightTime(flight, aerodromes);

      expect(result['night']?.value, isNot(FlightDuration.zero));
      expect(result['night']?.value, isNot(const FlightDuration(120)));
    });
  });
}
