// flutter_test re-exports test/group/expect from package:test_api, so plain
// Dart tests need no separate package:test dependency.
import 'package:easa_digital_log/domain/model/aerodrome.dart';
import 'package:easa_digital_log/domain/model/aerodrome_directory.dart';
import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/geo_coordinate.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:easa_digital_log/domain/primitives/faa_night_time.dart';
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
  CircuitCounts landings = const CircuitCounts(dayFullStop: 1),
}) => Flight(
  aircraftRegistration: 'N12345',
  route: route,
  prePlannedNavigation: false,
  offBlocks: offBlocks,
  onBlocks: onBlocks,
  takeoff: takeoff,
  landing: landing,
  capacity: _capacity(),
  carryingPassengers: false,
  takeoffs: const CircuitCounts(dayFullStop: 1),
  landings: landings,
  ifrFlightPlanFiled: false,
  actualInstrumentTime: FlightDuration.zero,
  simulatedInstrumentTime: FlightDuration.zero,
  approaches: const [],
  holdingProceduresCount: 0,
  trackingPerformed: false,
  remarks: '',
);

void main() {
  final aerodromes = _directoryWith({'KXXX': _london});

  group('faaNightTime', () {
    test('wholly within daylight is zero night flight time', () {
      final flight = _flight(
        route: const ['KXXX', 'KXXX'],
        offBlocks: UtcInstant.utc(2024, 6, 21, 10, 0),
        onBlocks: UtcInstant.utc(2024, 6, 21, 11, 30),
      );

      final result = faaNightTime(flight, aerodromes);

      expect(result['nightFlightTime']?.value, FlightDuration.zero);
      expect(result['nightFlightTime']?.creditable, isTrue);
    });

    test('wholly within night is the full flight duration', () {
      final flight = _flight(
        route: const ['KXXX', 'KXXX'],
        offBlocks: UtcInstant.utc(2024, 6, 21, 22, 0),
        onBlocks: UtcInstant.utc(2024, 6, 21, 23, 0),
      );

      final result = faaNightTime(flight, aerodromes);

      expect(result['nightFlightTime']?.value, const FlightDuration(60));
    });

    test('an unresolvable route reports it rather than guessing', () {
      final flight = _flight(
        route: const ['ZZZZ', 'ZZZZ'],
        offBlocks: UtcInstant.utc(2024, 6, 21, 22, 0),
        onBlocks: UtcInstant.utc(2024, 6, 21, 23, 0),
      );

      final result = faaNightTime(flight, _directoryWith(const {}));

      expect(result['nightFlightTime']?.creditable, isFalse);
      expect(
        result['nightFlightTime']?.explanation,
        contains('cannot be computed'),
      );
    });

    // #27: a missing takeoff/landing must not be silently blended into a
    // reading that looks identical to one measured against real airborne
    // instants.
    test('discloses the block-time substitution when takeoff/landing are not '
        'recorded', () {
      final flight = _flight(
        route: const ['KXXX', 'KXXX'],
        offBlocks: UtcInstant.utc(2024, 6, 21, 22, 0),
        onBlocks: UtcInstant.utc(2024, 6, 21, 23, 0),
      );

      final result = faaNightTime(flight, aerodromes);

      expect(
        result['nightFlightTime']?.explanation,
        contains('were not recorded'),
      );
    });

    test('no caveat when takeoff/landing are both recorded', () {
      final flight = _flight(
        route: const ['KXXX', 'KXXX'],
        offBlocks: UtcInstant.utc(2024, 6, 21, 22, 0),
        onBlocks: UtcInstant.utc(2024, 6, 21, 23, 0),
        takeoff: UtcInstant.utc(2024, 6, 21, 22, 5),
        landing: UtcInstant.utc(2024, 6, 21, 22, 55),
      );

      final result = faaNightTime(flight, aerodromes);

      expect(
        result['nightFlightTime']?.explanation,
        isNot(contains('were not recorded')),
      );
    });
  });

  group('the two FAA night windows do not get conflated', () {
    // docs/jurisdiction-matrix.md line 88: "A landing can be night-for-
    // logging but not night-for-currency" — and the reverse. Flight.landings
    // is a raw, pilot-entered fact (CLAUDE.md rule 2) that this primitive
    // never reads or reconciles against its own computed nightFlightTime.

    test('night landings recorded for currency, but zero computed night '
        'flight time', () {
      // The raw entry says a landing counted as night for the sunset+1h
      // currency window even though the flight itself, by the twilight
      // definition this primitive computes, never left daylight.
      final flight = _flight(
        route: const ['KXXX', 'KXXX'],
        offBlocks: UtcInstant.utc(2024, 6, 21, 10, 0),
        onBlocks: UtcInstant.utc(2024, 6, 21, 11, 0),
        landings: const CircuitCounts(nightFullStop: 1),
      );

      final result = faaNightTime(flight, aerodromes);

      expect(flight.landings.nightFullStop, 1);
      expect(result['nightFlightTime']?.value, FlightDuration.zero);
    });

    test('positive computed night flight time, but the landing was recorded '
        'as day for currency', () {
      // The flight is wholly inside the twilight-defined night window, so
      // nightFlightTime is the full duration — but the one landing was
      // entered as a day landing (as it would be if it fell after
      // twilight ended yet before the later sunset+1h currency window
      // began).
      final flight = _flight(
        route: const ['KXXX', 'KXXX'],
        offBlocks: UtcInstant.utc(2024, 6, 21, 22, 0),
        onBlocks: UtcInstant.utc(2024, 6, 21, 23, 0),
        landings: const CircuitCounts(dayFullStop: 1),
      );

      final result = faaNightTime(flight, aerodromes);

      expect(flight.landings.dayFullStop, 1);
      expect(flight.landings.nightFullStop, 0);
      expect(result['nightFlightTime']?.value, const FlightDuration(60));
    });
  });
}
