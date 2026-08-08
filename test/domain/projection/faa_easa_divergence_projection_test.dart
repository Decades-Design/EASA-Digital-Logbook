// flutter_test re-exports test/group/expect from package:test_api, so plain
// Dart tests need no separate package:test dependency.
import 'dart:io';

import 'package:easa_digital_log/domain/jurisdiction/jurisdiction_profile.dart';
import 'package:easa_digital_log/domain/jurisdiction/jurisdiction_registry.dart';
import 'package:easa_digital_log/domain/model/aircraft.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
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

JurisdictionRegistry _registryFromShippedProfiles() {
  final profiles = [
    'assets/jurisdictions/eu.easa.part-fcl.yaml',
    'assets/jurisdictions/us.faa.part61.yaml',
  ].map((path) => parseJurisdictionProfileYaml(File(path).readAsStringSync()));
  return JurisdictionRegistry(profiles);
}

/// #18's own acceptance criterion: "An explicit test asserting that
/// sole-manipulator-under-instruction yields dual under EASA and PIC under
/// FAA." This is that test, run through the real shipped profiles and the
/// real registered primitives — not a copy of either, and not the
/// primitives called directly — so it fails if the wiring between #17,
/// #18 and #19 is wrong even when each piece's own unit tests pass.
void main() {
  test('the same flight gives dual under EASA and PIC under FAA', () {
    final registry = _registryFromShippedProfiles();
    final flight = flightFromFixture('faa_easa_divergence');
    final aircraft = _aircraft();

    final easa = JurisdictionProjection(
      registry: registry,
      primitives: defaultPrimitives,
      jurisdictionId: 'eu.easa.part-fcl',
    ).project(flight, aircraft);

    final faa = JurisdictionProjection(
      registry: registry,
      primitives: defaultPrimitives,
      jurisdictionId: 'us.faa.part61',
    ).project(flight, aircraft);

    // EASA: no general sole-manipulator concept. The instructor held
    // command, so this pilot logs dual, not PIC.
    expect(easa['pic']?.value, FlightDuration.zero);
    expect(easa['dual']?.value, isNot(FlightDuration.zero));

    // FAA: §61.51(e)(1)(i) grants PIC to the sole manipulator regardless of
    // who held command.
    expect(faa['loggedPic']?.value, isNot(FlightDuration.zero));

    // The two disagree about PIC for the identical flight, and both are
    // correct under their own rules — that disagreement is the entire
    // reason this codebase exists rather than storing one number.
    expect(easa['pic']?.value, isNot(faa['loggedPic']?.value));
  });
}
