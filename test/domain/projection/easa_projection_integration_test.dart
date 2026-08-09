// flutter_test re-exports test/group/expect from package:test_api, so plain
// Dart tests need no separate package:test dependency.
import 'dart:io';

import 'package:easa_digital_log/domain/jurisdiction/jurisdiction_profile.dart';
import 'package:easa_digital_log/domain/jurisdiction/jurisdiction_registry.dart';
import 'package:easa_digital_log/domain/model/aerodrome_directory.dart';
import 'package:easa_digital_log/domain/model/aircraft.dart';
import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:easa_digital_log/domain/primitives/default_primitives.dart';
import 'package:easa_digital_log/domain/projection/jurisdiction_projection.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/decoders/flight_fixture.dart';

Aircraft _aircraft() => const Aircraft(
  registration: 'G-ABCD',
  manufacturer: 'Test',
  model: 'Test',
  category: AircraftCategory.aeroplane,
  engineType: EngineType.piston,
  engineCount: 1,
  operatingSurface: OperatingSurface.land,
  requiresMultiCrew: false,
);

/// Proves the actual shipped `assets/jurisdictions/eu.easa.part-fcl.yaml` —
/// not a copy, not a synthetic fixture — parses, resolves, and dispatches
/// through the real `defaultPrimitives` registry end to end. Everything
/// else in this test suite exercises the mechanism or the rule logic in
/// isolation; this is the one test that would fail if the two were wired
/// together wrong.
void main() {
  test(
    'the shipped EASA profile resolves and dispatches to the real primitive',
    () {
      final yaml = File(
        'assets/jurisdictions/eu.easa.part-fcl.yaml',
      ).readAsStringSync();
      final registry = JurisdictionRegistry([
        parseJurisdictionProfileYaml(yaml),
      ]);

      final projection = JurisdictionProjection(
        registry: registry,
        primitives: defaultPrimitives,
        aerodromes: AerodromeDirectory(const []),
        jurisdictionId: 'eu.easa.part-fcl',
      );

      final flight = Flight(
        aircraftRegistration: 'G-ABCD',
        route: const ['EGKA', 'EGKA'],
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

      final result = projection.project(flight, _aircraft());
      expect(result.jurisdictionId, 'eu.easa.part-fcl');
      expect(result['pic']?.value, const FlightDuration(90));
      expect(result['pic']?.creditable, isTrue);
    },
  );

  test('the divergence fixture resolves through the real EASA profile too', () {
    final yaml = File(
      'assets/jurisdictions/eu.easa.part-fcl.yaml',
    ).readAsStringSync();
    final registry = JurisdictionRegistry([parseJurisdictionProfileYaml(yaml)]);
    final projection = JurisdictionProjection(
      registry: registry,
      primitives: defaultPrimitives,
      aerodromes: AerodromeDirectory(const []),
      jurisdictionId: 'eu.easa.part-fcl',
    );

    final flight = flightFromFixture('faa_easa_divergence');
    final result = projection.project(flight, _aircraft());

    expect(
      result['pic']?.value,
      FlightDuration.zero,
      reason: 'the instructor held command',
    );
    expect(result['dual']?.value, isNot(FlightDuration.zero));
  });
}
