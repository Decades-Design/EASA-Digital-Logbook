import 'dart:io';

import 'package:easa_digital_log/domain/jurisdiction/jurisdiction_profile.dart';
import 'package:easa_digital_log/domain/jurisdiction/jurisdiction_registry.dart';
import 'package:easa_digital_log/domain/model/aerodrome_directory.dart';
import 'package:easa_digital_log/domain/primitives/default_primitives.dart';
import 'package:easa_digital_log/domain/projection/jurisdiction_projection.dart';
import 'package:easa_digital_log/export/amc1_fcl050_row_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fixtures/decoders/aircraft_fixture.dart';
import '../fixtures/decoders/flight_fixture.dart';

/// Exercises `buildAmc1Fcl050Row` against the real shipped EASA profile
/// (`assets/jurisdictions/eu.easa.part-fcl.yaml`) and real domain fixtures
/// — the same combination `easa_projection_integration_test.dart` uses —
/// rather than a hand-rolled fake projection, since #76's whole point is
/// printing what the real rule engine actually derives.
void main() {
  late JurisdictionProjection easaProjection;

  setUpAll(() {
    final yaml = File(
      'assets/jurisdictions/eu.easa.part-fcl.yaml',
    ).readAsStringSync();
    easaProjection = JurisdictionProjection(
      registry: JurisdictionRegistry([parseJurisdictionProfileYaml(yaml)]),
      primitives: defaultPrimitives,
      aerodromes: AerodromeDirectory(const []),
      jurisdictionId: 'eu.easa.part-fcl',
    );
  });

  test('command authority prints "SELF" in group 7 and full time as PIC in '
      'group 10', () {
    final row = buildAmc1Fcl050Row(
      flight: flightFromFixture('vmc_ifr_flight'),
      aircraft: aircraftFromFixture('g_abcd'),
      easaProjection: easaProjection,
    );

    expect(row.namesPic, 'SELF');
    expect(row.pilotFunctionPic.inMinutes, 90);
    expect(row.pilotFunctionDual.inMinutes, 0);
    expect(row.operationalIfr.inMinutes, 90, reason: 'IFR plan filed');
    expect(row.departurePlace, 'EGKA');
    expect(row.arrivalPlace, 'EGKA');
    expect(row.aircraftRegistration, 'G-ABCD');
    expect(row.aircraftMakeModelVariant, 'Cessna 152');
  });

  test('dual received prints group 10 dual time, zero PIC, and group 7 blank '
      "when the fixture never names the instructor", () {
    final row = buildAmc1Fcl050Row(
      flight: flightFromFixture('faa_easa_divergence'),
      aircraft: aircraftFromFixture('g_abcd'),
      easaProjection: easaProjection,
    );

    expect(row.namesPic, isEmpty);
    expect(row.pilotFunctionPic.inMinutes, 0);
    expect(row.pilotFunctionDual.inMinutes, greaterThan(0));
  });

  test('landings are combined day/night, not split full-stop vs T&G', () {
    final row = buildAmc1Fcl050Row(
      flight: flightFromFixture('night_landing_day_flight'),
      aircraft: aircraftFromFixture('g_abcd'),
      easaProjection: easaProjection,
    );

    expect(row.landingsDay, 0);
    expect(row.landingsNight, 1);
  });

  test('remarks pass through verbatim', () {
    final row = buildAmc1Fcl050Row(
      flight: flightFromFixture('vmc_ifr_flight'),
      aircraft: aircraftFromFixture('g_abcd'),
      easaProjection: easaProjection,
    );

    expect(
      row.remarks,
      'IFR flight plan filed and flown throughout; VMC the entire route.',
    );
  });
}
