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

/// An IFR flight plan filed, but flown entirely in clear air — no actual or
/// simulated instrument time recorded.
Flight _vmcIfrFlight() => Flight(
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
  ifrFlightPlanFiled: true,
  actualInstrumentTime: FlightDuration.zero,
  simulatedInstrumentTime: FlightDuration.zero,
  approaches: const [],
  holdingProceduresCount: 0,
  trackingPerformed: false,
  remarks: 'IFR flight plan, flown in VMC throughout.',
);

JurisdictionRegistry _registryFromShippedProfiles() {
  final profiles = [
    'assets/jurisdictions/eu.easa.part-fcl.yaml',
    'assets/jurisdictions/us.faa.part61.yaml',
  ].map((path) => parseJurisdictionProfileYaml(File(path).readAsStringSync()));
  return JurisdictionRegistry(profiles);
}

/// #25's own acceptance criterion: "A test showing a VMC IFR flight
/// yielding EASA IFR time but zero FAA actual instrument time." Run through
/// the real shipped profiles and the real registered primitives, as
/// `faa_easa_divergence_projection_test.dart` does for pilot function time,
/// so this fails if the wiring is wrong even when each primitive's own unit
/// tests pass.
void main() {
  test('an IFR flight plan filed but flown in VMC is full EASA IFR time and '
      'zero FAA instrument time', () {
    final registry = _registryFromShippedProfiles();
    final flight = _vmcIfrFlight();
    final aircraft = _aircraft();
    final blockTime = const FlightDuration(90);

    final easa = JurisdictionProjection(
      registry: registry,
      primitives: defaultPrimitives,
      aerodromes: AerodromeDirectory(const []),
      jurisdictionId: 'eu.easa.part-fcl',
    ).project(flight, aircraft);

    final faa = JurisdictionProjection(
      registry: registry,
      primitives: defaultPrimitives,
      aerodromes: AerodromeDirectory(const []),
      jurisdictionId: 'us.faa.part61',
    ).project(flight, aircraft);

    expect(easa['ifr']?.value, blockTime);
    expect(easa['ifr']?.creditable, isTrue);

    expect(faa['actualInstrument']?.value, FlightDuration.zero);
    expect(faa['simulatedInstrument']?.value, FlightDuration.zero);
  });
}
