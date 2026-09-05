import 'dart:io';

import 'package:easa_digital_log/domain/jurisdiction/jurisdiction_profile.dart';
import 'package:easa_digital_log/domain/jurisdiction/jurisdiction_registry.dart';
import 'package:easa_digital_log/domain/model/aerodrome_directory.dart';
import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:easa_digital_log/domain/primitives/default_primitives.dart';
import 'package:easa_digital_log/domain/projection/command_time_divergence.dart';
import 'package:easa_digital_log/domain/projection/jurisdiction_projection.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/decoders/aircraft_fixture.dart';
import '../../fixtures/decoders/flight_fixture.dart';
import '../../fixtures/decoders/pilot_capacity_fixture.dart';

/// A PICUS sector — the same fixture pairing
/// `easa_faa_divergence_test.dart`'s own `_picusFlight` builds by hand,
/// since there's no full flight fixture for it, only a `PilotCapacity` one.
Flight _picusFlight(String capacityFixture) => Flight(
  aircraftRegistration: 'G-ABCD',
  route: const ['EGKA', 'EGHH', 'EGKA'],
  prePlannedNavigation: false,
  offBlocks: UtcInstant.utc(2026, 5, 10, 9, 0),
  onBlocks: UtcInstant.utc(2026, 5, 10, 11, 0),
  capacity: pilotCapacityFromFixture(capacityFixture),
  carryingPassengers: false,
  takeoffs: const CircuitCounts(dayFullStop: 1),
  landings: const CircuitCounts(dayFullStop: 1),
  ifrFlightPlanFiled: false,
  actualInstrumentTime: FlightDuration.zero,
  simulatedInstrumentTime: FlightDuration.zero,
  approaches: const [],
  holdingProceduresCount: 0,
  trackingPerformed: false,
  remarks: 'PICUS sector, multi-pilot operation.',
);

JurisdictionRegistry _registryFromShippedProfiles() {
  final profiles = [
    'assets/jurisdictions/eu.easa.part-fcl.yaml',
    'assets/jurisdictions/us.faa.part61.yaml',
  ].map((path) => parseJurisdictionProfileYaml(File(path).readAsStringSync()));
  return JurisdictionRegistry(profiles);
}

void main() {
  final registry = _registryFromShippedProfiles();
  final aerodromes = AerodromeDirectory(const []);
  final aircraft = aircraftFromFixture('g_abcd');

  JurisdictionProjection projectionFor(String jurisdictionId) =>
      JurisdictionProjection(
        registry: registry,
        primitives: defaultPrimitives,
        aerodromes: aerodromes,
        jurisdictionId: jurisdictionId,
      );

  test('sole manipulator receiving instruction diverges: FAA credits PIC, '
      'EASA credits none', () {
    final flight = flightFromFixture('faa_easa_divergence');
    final easa = projectionFor('eu.easa.part-fcl').project(flight, aircraft);
    final faa = projectionFor('us.faa.part61').project(flight, aircraft);

    expect(commandAuthorityTime(easa), FlightDuration.zero);
    expect(commandAuthorityTime(faa), isNot(FlightDuration.zero));
    expect(commandTimeDiverges([easa, faa]), isTrue);
  });

  test('an ordinary PIC-solo flight does not diverge', () {
    final flight = flightFromFixture('vmc_ifr_flight');
    final easa = projectionFor('eu.easa.part-fcl').project(flight, aircraft);
    final faa = projectionFor('us.faa.part61').project(flight, aircraft);

    expect(commandTimeDiverges([easa, faa]), isFalse);
  });

  test('a single jurisdiction never diverges from itself', () {
    final flight = flightFromFixture('faa_easa_divergence');
    final easa = projectionFor('eu.easa.part-fcl').project(flight, aircraft);

    expect(commandTimeDiverges([easa]), isFalse);
  });

  test('a non-creditable command-authority quantity (PICUS pending '
      'countersignature) does not count towards commandAuthorityTime', () {
    final flight = _picusFlight('picus_pending');
    final easa = projectionFor('eu.easa.part-fcl').project(flight, aircraft);
    final picus = easa['picus'];

    expect(picus, isNotNull);
    expect(picus!.creditable, isFalse);
    expect(picus.value, isNot(FlightDuration.zero));
    expect(commandAuthorityTime(easa), FlightDuration.zero);
  });
}
