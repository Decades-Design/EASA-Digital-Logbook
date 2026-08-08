// flutter_test re-exports test/group/expect from package:test_api, so plain
// Dart tests need no separate package:test dependency.
import 'dart:io';

import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/instructor_presence.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../tool/dart_source.dart';
import '../../fixtures/decoders/flight_fixture.dart';

/// The names issue #11 explicitly lists as forbidden — every one of them is
/// a projection output, not a raw fact, per ADR-0001.
///
/// Checked against `flight.dart`'s own source rather than added to
/// `tool/check_domain_types.dart`'s project-wide banned-identifiers list:
/// that guard runs over all of `lib/domain/`, including the future
/// `domain/projection/` layer whose entire job is to compute values named
/// exactly `picTime`, `totalTime` and so on. Banning these words
/// domain-wide would block the projection code that is supposed to produce
/// them. Scoping the check to this one file is what "the model exposes no
/// field..." (the actual acceptance criterion) asks for.
const List<String> _derivedQuantityNames = <String>[
  'picTime',
  'dualTime',
  'nightTime',
  'crossCountryTime',
  'totalTime',
  'picusTime',
  'spicTime',
];

void main() {
  test(
    'Flight exposes no field whose name matches a derived-quantity pattern',
    () {
      // stripComments first — the class dartdoc explains the ban by naming
      // the forbidden words, which would otherwise trip the check itself.
      final source = stripComments(
        File('lib/domain/model/flight.dart').readAsStringSync(),
      );

      for (final name in _derivedQuantityNames) {
        expect(
          RegExp('\\b$name\\b').hasMatch(source),
          isFalse,
          reason:
              '"$name" is a projection output (ADR-0001) and must never be a '
              'field on Flight',
        );
      }
    },
  );

  group('Flight construction', () {
    test('a minimal flight with no optional facts constructs', () {
      final flight = Flight(
        aircraftRegistration: 'G-ABCD',
        route: const ['EGKA', 'EGHR', 'EGKA'],
        offBlocks: UtcInstant.utc(2026, 3, 14, 9, 5),
        onBlocks: UtcInstant.utc(2026, 3, 14, 10, 51),
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
        holdingAndTrackingPerformed: false,
        remarks: '',
      );

      expect(flight.takeoff, isNull);
      expect(flight.landing, isNull);
      expect(flight.otherPilotName, isNull);
      expect(flight.seriesGroupId, isNull);
      expect(flight.airworthinessBasis, isNull);
    });
  });

  group('the FAA/EASA divergence fixture', () {
    test('decodes into a Flight with the capacity embedded', () {
      final flight = flightFromFixture('faa_easa_divergence');

      expect(flight.aircraftRegistration, 'G-ABCD');
      expect(flight.route, ['EGKA', 'EGHR', 'EGKA']);
      expect(flight.capacity.commandAuthority, isFalse);
      expect(flight.capacity.soleManipulator, isTrue);
      expect(
        flight.capacity.instructor?.capacity,
        InstructorCapacity.flightInstructor,
      );
      expect(flight.capacity.instructor?.influencedFlight, isTrue);
      expect(flight.takeoffs.dayTouchAndGo, 3);
      expect(flight.landings.dayFullStop, 1);
      expect(flight.approaches, isEmpty);
      expect(flight.seriesGroupId, isNull);
      expect(flight.airworthinessBasis, isNull);
    });
  });
}
