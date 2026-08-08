// flutter_test re-exports test/group/expect from package:test_api, so plain
// Dart tests need no separate package:test dependency.
import 'package:easa_digital_log/domain/jurisdiction/jurisdiction_profile.dart';
import 'package:easa_digital_log/domain/jurisdiction/jurisdiction_registry.dart';
import 'package:easa_digital_log/domain/model/aircraft.dart';
import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:easa_digital_log/domain/primitives/pilot_function_time.dart';
import 'package:easa_digital_log/domain/projection/derived_quantity.dart';
import 'package:easa_digital_log/domain/projection/jurisdiction_projection.dart';
import 'package:flutter_test/flutter_test.dart';

/// A fake primitive, not EASA or FAA logic — #18/#19 own the real rules.
/// This proves the engine (profile resolution -> primitive dispatch ->
/// result) works in isolation, before any real regulatory logic exists to
/// entangle the two concerns.
Map<String, DerivedQuantity> _fakeRule(
  Flight flight,
  FlightDuration blockTime,
) => {
  'pic': flight.capacity.commandAuthority
      ? DerivedQuantity.creditable(blockTime, 'fake: command authority held')
      : DerivedQuantity.zero('fake: no command authority'),
};

Aircraft _aircraft() => const Aircraft(
  registration: 'G-TEST',
  manufacturer: 'Test',
  model: 'Test',
  category: AircraftCategory.aeroplane,
  engineType: EngineType.piston,
  engineCount: 1,
  operatingSurface: OperatingSurface.land,
  requiresMultiCrew: false,
);

Flight _flight({required bool commandAuthority}) => Flight(
  aircraftRegistration: 'G-TEST',
  route: const ['EGKA', 'EGKA'],
  offBlocks: UtcInstant.utc(2026, 1, 1, 9, 0),
  onBlocks: UtcInstant.utc(2026, 1, 1, 10, 30),
  capacity: PilotCapacity(
    commandAuthority: commandAuthority,
    soleManipulator: commandAuthority,
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
  late JurisdictionProjection projection;

  setUp(() {
    final registry = JurisdictionRegistry([
      const JurisdictionProfile(
        id: 'test.fake',
        rules: {'pic_rule': 'test.fake_rule'},
      ),
      const JurisdictionProfile(id: 'test.no-rules', rules: {}),
    ]);
    final primitives = PrimitiveRegistry({'test.fake_rule': _fakeRule});
    projection = JurisdictionProjection(
      registry: registry,
      primitives: primitives,
      jurisdictionId: 'test.fake',
    );
  });

  group('JurisdictionProjection.project', () {
    test('resolves the profile and dispatches to the named primitive', () {
      final result = projection.project(
        _flight(commandAuthority: true),
        _aircraft(),
      );

      expect(result.jurisdictionId, 'test.fake');
      expect(result['pic']?.value, const FlightDuration(90));
      expect(result['pic']?.creditable, isTrue);
    });

    test('computes block time from offBlocks/onBlocks, not a stored field', () {
      final result = projection.project(
        _flight(commandAuthority: false),
        _aircraft(),
      );

      // commandAuthority: false -> the fake rule reports zero, proving the
      // engine actually passed the real flight through rather than some
      // fixed value.
      expect(result['pic']?.value, FlightDuration.zero);
    });

    test(
      'a profile with no pic_rule set yields an empty result, not an error',
      () {
        final registry = JurisdictionRegistry([
          const JurisdictionProfile(id: 'test.no-rules', rules: {}),
        ]);
        final bare = JurisdictionProjection(
          registry: registry,
          primitives: PrimitiveRegistry(const {}),
          jurisdictionId: 'test.no-rules',
        );

        final result = bare.project(
          _flight(commandAuthority: true),
          _aircraft(),
        );
        expect(result.quantities, isEmpty);
      },
    );

    test('an unregistered primitive id throws ArgumentError', () {
      final registry = JurisdictionRegistry([
        const JurisdictionProfile(
          id: 'test.broken',
          rules: {'pic_rule': 'nothing.registered'},
        ),
      ]);
      final broken = JurisdictionProjection(
        registry: registry,
        primitives: PrimitiveRegistry(const {}),
        jurisdictionId: 'test.broken',
      );

      expect(
        () => broken.project(_flight(commandAuthority: true), _aircraft()),
        throwsArgumentError,
      );
    });
  });

  group('JurisdictionProjection.projectAggregate', () {
    test('sums creditable contributions across the flight set', () {
      final result = projection.projectAggregate([
        (_flight(commandAuthority: true), _aircraft()),
        (_flight(commandAuthority: true), _aircraft()),
        (_flight(commandAuthority: false), _aircraft()),
      ]);

      // 90 + 90 + 0 minutes.
      expect(result['pic']?.value, const FlightDuration(180));
      expect(result['pic']?.explanation, contains('3 flight'));
    });

    test(
      'excludes a non-creditable contribution from the total but names it',
      () {
        Map<String, DerivedQuantity> pendingRule(
          Flight flight,
          FlightDuration blockTime,
        ) => {'pic': DerivedQuantity.notCreditable(blockTime, 'fake: pending')};

        final registry = JurisdictionRegistry([
          const JurisdictionProfile(
            id: 'test.pending',
            rules: {'pic_rule': 'test.pending_rule'},
          ),
        ]);
        final pendingProjection = JurisdictionProjection(
          registry: registry,
          primitives: PrimitiveRegistry({'test.pending_rule': pendingRule}),
          jurisdictionId: 'test.pending',
        );

        final result = pendingProjection.projectAggregate([
          (_flight(commandAuthority: true), _aircraft()),
        ]);

        expect(
          result['pic']?.value,
          FlightDuration.zero,
          reason:
              'the one flight is not creditable, so it contributes nothing '
              'to the reliable total',
        );
        expect(
          result['pic']?.creditable,
          isTrue,
          reason: 'the total itself is reliable — it is honestly zero',
        );
        expect(result['pic']?.explanation, contains('excluded'));
      },
    );

    test('an empty flight set yields an empty result', () {
      final result = projection.projectAggregate(const []);
      expect(result.quantities, isEmpty);
    });
  });
}
