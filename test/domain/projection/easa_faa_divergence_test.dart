// flutter_test re-exports test/group/expect from package:test_api, so plain
// Dart tests need no separate package:test dependency.
import 'dart:io';

import 'package:easa_digital_log/domain/jurisdiction/jurisdiction_profile.dart';
import 'package:easa_digital_log/domain/jurisdiction/jurisdiction_registry.dart';
import 'package:easa_digital_log/domain/model/aerodrome.dart';
import 'package:easa_digital_log/domain/model/aerodrome_directory.dart';
import 'package:easa_digital_log/domain/model/aircraft.dart';
import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/geo_coordinate.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:easa_digital_log/domain/primitives/default_primitives.dart';
import 'package:easa_digital_log/domain/projection/jurisdiction_projection.dart';
import 'package:easa_digital_log/domain/projection/projection_result.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/decoders/aircraft_fixture.dart';
import '../../fixtures/decoders/flight_fixture.dart';
import '../../fixtures/decoders/pilot_capacity_fixture.dart';

/// #30: the integration point for M1. One row per scenario, the same
/// [Flight] and [Aircraft] evaluated under both the real shipped EASA and
/// FAA profiles — not a copy of either jurisdiction's own unit tests, and
/// not the primitives called directly, so this fails if the wiring between
/// a jurisdiction profile and its primitives is wrong even when every
/// primitive's own tests pass. If a future change makes two rows agree
/// where this file expects a divergence, that is a regression: the
/// `isNot`/exact-value assertions below exist to say so, not merely to
/// describe today's behaviour.
typedef _Scenario = ({
  String description,
  Flight flight,
  Aircraft aircraft,
  AerodromeDirectory aerodromes,
  void Function(ProjectionResult easa, ProjectionResult faa) verify,
});

JurisdictionRegistry _registryFromShippedProfiles() {
  final profiles = [
    'assets/jurisdictions/eu.easa.part-fcl.yaml',
    'assets/jurisdictions/us.faa.part61.yaml',
  ].map((path) => parseJurisdictionProfileYaml(File(path).readAsStringSync()));
  return JurisdictionRegistry(profiles);
}

/// Equatorial points give exact, round distances (60.04 nm per degree of
/// longitude) — the same trick `faa_cross_country_time_test.dart` uses.
GeoCoordinate _eq(double lonDegrees) =>
    GeoCoordinate(latitude: 0, longitude: lonDegrees);

/// DEP -> MID30 (30nm) -> FAR72 (42nm from MID30, 72nm from DEP): the same
/// geometry `faa_cross_country_time_test.dart`'s own multi-leg case uses,
/// where every leg is under 50nm but the point furthest from the original
/// departure is over it.
final _multiLegAerodromes = AerodromeDirectory([
  Aerodrome(icaoCode: 'DEP', name: 'Departure', position: _eq(0)),
  Aerodrome(icaoCode: 'MID30', name: '30nm out', position: _eq(0.5)),
  Aerodrome(icaoCode: 'FAR72', name: '72nm out', position: _eq(1.2)),
]);

/// London, validated against the US Naval Observatory in
/// `solar_position_test.dart`: civil twilight on 2024-06-21 ends 21:09Z and
/// begins again 02:55Z, so 10:00Z-11:30Z is wholly inside civil daylight.
final _london = GeoCoordinate(latitude: 51.5074, longitude: -0.1278);

Flight _multiLegFlight() => Flight(
  aircraftRegistration: 'G-ABCD',
  route: const ['DEP', 'MID30', 'FAR72'],
  prePlannedNavigation: false,
  offBlocks: UtcInstant.utc(2026, 3, 1, 9, 0),
  onBlocks: UtcInstant.utc(2026, 3, 1, 11, 0),
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
  takeoffs: const CircuitCounts(dayFullStop: 2),
  landings: const CircuitCounts(dayFullStop: 2),
  ifrFlightPlanFiled: false,
  actualInstrumentTime: FlightDuration.zero,
  simulatedInstrumentTime: FlightDuration.zero,
  approaches: const [],
  holdingProceduresCount: 0,
  trackingPerformed: false,
  remarks: 'Triangular navigation exercise: DEP-MID30-FAR72.',
);

/// A PICUS sector, identical in every fact except [capacityFixture] — the
/// same pairing `picus_pending.yaml`/`picus_countersigned.yaml` document in
/// their own header comments as "the concrete proof that PICUS cannot be a
/// stored role."
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

List<_Scenario> _scenarios() => [
  (
    description:
        'sole manipulator receiving instruction: EASA logs dual, FAA logs '
        'PIC, for the identical flight',
    flight: flightFromFixture('faa_easa_divergence'),
    aircraft: aircraftFromFixture('g_abcd'),
    aerodromes: AerodromeDirectory(const []),
    verify: (easa, faa) {
      // EASA FCL.010: no general sole-manipulator concept. The instructor
      // held command, so this pilot logs dual, not PIC.
      expect(easa['pic']?.value, FlightDuration.zero);
      expect(easa['dual']?.value, isNot(FlightDuration.zero));
      // FAA §61.51(e)(1)(i): PIC accrues to the sole manipulator
      // regardless of who held command.
      expect(faa['loggedPic']?.value, isNot(FlightDuration.zero));
      expect(easa['pic']?.value, isNot(faa['loggedPic']?.value));
    },
  ),
  (
    description:
        'an IFR flight plan filed but flown in VMC: full EASA IFR time, '
        'zero FAA instrument time',
    flight: flightFromFixture('vmc_ifr_flight'),
    aircraft: aircraftFromFixture('g_abcd'),
    aerodromes: AerodromeDirectory(const []),
    verify: (easa, faa) {
      // AMC1 FCL.050 column 9: IFR is an operational condition,
      // independent of meteorological conditions.
      expect(easa['ifr']?.value, const FlightDuration(90));
      expect(easa['ifr']?.creditable, isTrue);
      // §61.51(g)(1)/(b)(3)(iii): only actual or simulated instrument
      // conditions count; the FAA has no "flew under an IFR flight plan"
      // quantity at all.
      expect(faa['actualInstrument']?.value, FlightDuration.zero);
      expect(faa['simulatedInstrument']?.value, FlightDuration.zero);
    },
  ),
  (
    description:
        'a multi-leg flight, each leg under 50nm but the furthest point '
        'over it: FAA credits the 50nm test, EASA does not qualify for '
        'licence issue',
    flight: _multiLegFlight(),
    aircraft: aircraftFromFixture('g_abcd'),
    aerodromes: _multiLegAerodromes,
    verify: (easa, faa) {
      // AMC1 FCL.210 needs >= 150NM *total route distance* (30 + 42 =
      // 72NM here) and full-stop landings at two other aerodromes. Two
      // aerodromes, but nowhere near 150NM, so this does not qualify for
      // licence issue — reliably computed and reliably zero, not merely
      // "unable to compute."
      expect(easa['qualifyingCrossCountry']?.value, FlightDuration.zero);
      expect(easa['qualifyingCrossCountry']?.creditable, isTrue);
      // §61.1(b)(3)(ii) needs the *furthest point from the original
      // departure* over 50NM — FAR72 is 72NM from DEP, even though
      // neither individual leg (30NM, then 42NM) exceeds 50NM alone.
      expect(
        faa['crossCountryPrivateCommercialInstrument']?.value,
        isNot(FlightDuration.zero),
      );
    },
  ),
  (
    description:
        'a landing logged as night for currency, on a flight that never '
        'left daylight by either jurisdiction\'s twilight definition',
    flight: flightFromFixture('night_landing_day_flight'),
    aircraft: aircraftFromFixture('g_abcd'),
    aerodromes: AerodromeDirectory([
      Aerodrome(icaoCode: 'EGXX', name: 'EGXX', position: _london),
    ]),
    verify: (easa, faa) {
      // FCL.010 'night' and §1.1 'night' are aligned for *logging*
      // (jurisdiction-matrix.md §3) and both compute zero here — the
      // divergence this row proves is between the raw, pilot-attested
      // night-landing count (Flight.landings.nightFullStop) and either
      // jurisdiction's computed quantity, not between the jurisdictions
      // themselves: neither primitive reads Flight.landings at all.
      expect(easa['night']?.value, FlightDuration.zero);
      expect(faa['nightFlightTime']?.value, FlightDuration.zero);
    },
  ),
  (
    description:
        'PICUS before countersignature: not creditable under EASA; full '
        'PIC under FAA regardless',
    flight: _picusFlight('picus_pending'),
    aircraft: aircraftFromFixture('g_abcd'),
    aerodromes: AerodromeDirectory(const []),
    verify: (easa, faa) {
      // FCL.010 / AMC1 FCL.050: PICUS claimed but not yet countersigned
      // is a real, non-zero figure that is not creditable — never
      // silently 0, never silently valid.
      expect(easa['picus']?.creditable, isFalse);
      expect(easa['picus']?.value, const FlightDuration(120));
      // §61.51(e)(1)(i): the FAA has no countersignature requirement at
      // all — sole manipulator logs full PIC unconditionally.
      expect(faa['loggedPic']?.value, const FlightDuration(120));
      expect(faa['loggedPic']?.creditable, isTrue);
    },
  ),
  (
    description:
        'PICUS after countersignature: creditable under EASA; unchanged '
        '(already full) under FAA',
    flight: _picusFlight('picus_countersigned'),
    aircraft: aircraftFromFixture('g_abcd'),
    aerodromes: AerodromeDirectory(const []),
    verify: (easa, faa) {
      expect(easa['picus']?.creditable, isTrue);
      expect(easa['picus']?.value, const FlightDuration(120));
      expect(faa['loggedPic']?.value, const FlightDuration(120));
      expect(faa['loggedPic']?.creditable, isTrue);
    },
  ),
];

void main() {
  final registry = _registryFromShippedProfiles();

  for (final scenario in _scenarios()) {
    test(scenario.description, () {
      final easa = JurisdictionProjection(
        registry: registry,
        primitives: defaultPrimitives,
        aerodromes: scenario.aerodromes,
        jurisdictionId: 'eu.easa.part-fcl',
      ).project(scenario.flight, scenario.aircraft);

      final faa = JurisdictionProjection(
        registry: registry,
        primitives: defaultPrimitives,
        aerodromes: scenario.aerodromes,
        jurisdictionId: 'us.faa.part61',
      ).project(scenario.flight, scenario.aircraft);

      scenario.verify(easa, faa);
    });
  }
}
