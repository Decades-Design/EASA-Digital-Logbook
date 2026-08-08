// flutter_test re-exports test/group/expect from package:test_api, so plain
// Dart tests need no separate package:test dependency.
import 'package:easa_digital_log/domain/model/aircraft.dart';
import 'package:easa_digital_log/domain/model/mass.dart';
import 'package:easa_digital_log/domain/primitives/faa_aircraft_categories.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/decoders/aircraft_fixture.dart';
import '../../fixtures/decoders/fixture_fields.dart';

/// Every aircraft fixture, by name. Add one here when you add the file.
const List<String> aircraftFixtures = <String>[
  'g_abcd',
  'n456bd',
  'g_seaplane',
  'g_multicrew',
  'n700cm',
  'g_tailwheel_tmg',
];

void main() {
  group('aircraft fixtures', () {
    test('every fixture decodes', () {
      for (final name in aircraftFixtures) {
        expect(aircraftFromFixture(name), isA<Aircraft>(), reason: name);
      }
    });

    test('no two fixtures are indistinguishable', () {
      final decoded = <Aircraft, String>{};
      for (final name in aircraftFixtures) {
        final aircraft = aircraftFromFixture(name);
        expect(
          decoded[aircraft],
          isNull,
          reason: '$name and ${decoded[aircraft]} decode identically',
        );
        decoded[aircraft] = name;
      }
    });

    test('the fixtures exercise every category and surface they claim to', () {
      // An enum value no fixture uses is model surface nothing tests. Not
      // every AircraftCategory is covered — there is no helicopter or balloon
      // here yet, deliberately — but the ones the set claims to cover must
      // genuinely appear.
      final all = aircraftFixtures.map(aircraftFromFixture).toList();

      expect(
        all.map((a) => a.category).toSet(),
        containsAll(<AircraftCategory>[
          AircraftCategory.aeroplane,
          AircraftCategory.touringMotorGlider,
        ]),
      );
      expect(
        all.map((a) => a.operatingSurface).toSet(),
        containsAll(<OperatingSurface>[
          OperatingSurface.land,
          OperatingSurface.sea,
        ]),
      );
      expect(all.map((a) => a.requiresMultiCrew).toSet(), <bool>{true, false});
      expect(
        all.any((a) => a.typeRatingDesignator != null),
        isTrue,
        reason: 'nothing exercises the type-rated path',
      );
      expect(
        all.map((a) => a.maximumTakeoffMass?.unit).toSet(),
        containsAll(<MassUnit>[MassUnit.kilograms, MassUnit.pounds]),
        reason:
            'both certificated units must appear, or the unit-preserving '
            'comparison is never exercised',
      );
      expect(
        all.any((a) => a.horsepower == null),
        isTrue,
        reason: 'nothing exercises the unknown-horsepower path',
      );
    });
  });

  group('§61.31(e) complex', () {
    test('needs all three of gear, flaps and a variable-pitch propeller', () {
      expect(isComplex(aircraftFromFixture('n456bd')), isTrue);
      expect(isComplex(aircraftFromFixture('g_abcd')), isFalse);
    });

    test('drops the retractable-gear condition for a seaplane', () {
      // "in the case of a seaplane, flaps and a controllable pitch propeller".
      // A floatplane has no retractable undercarriage and would otherwise
      // never qualify. This is the case a naive implementation gets wrong.
      final seaplane = aircraftFromFixture('g_seaplane');

      expect(
        seaplane.equipment.contains(AircraftEquipment.retractableUndercarriage),
        isFalse,
      );
      expect(isComplex(seaplane), isTrue);
    });

    test('does not apply outside the aeroplane category', () {
      // The TMG has a variable-pitch propeller but is not an aeroplane.
      final tmg = aircraftFromFixture('g_tailwheel_tmg');

      expect(tmg.category, AircraftCategory.touringMotorGlider);
      expect(isComplex(tmg), isFalse);
    });

    test('is false for a jet, whose type rating covers the same ground', () {
      expect(isComplex(aircraftFromFixture('g_multicrew')), isFalse);
    });
  });

  group('§61.31(f) high-performance', () {
    test('turns on more than 200 horsepower', () {
      expect(isHighPerformance(aircraftFromFixture('n456bd')), isTrue);
      expect(isHighPerformance(aircraftFromFixture('g_abcd')), isFalse);
    });

    test('is exactly 200 hp, not 200 or more', () {
      // The rule reads "more than 200 horsepower". An implementation using
      // >= would make a 200 hp aeroplane require an endorsement it does not.
      final base = aircraftFromFixture('g_abcd');

      expect(isHighPerformance(base.copyWith(horsepower: 200)), isFalse);
      expect(isHighPerformance(base.copyWith(horsepower: 201)), isTrue);
    });

    test('answers null, not false, when horsepower is unknown', () {
      // "We do not know" and "no" lead to different actions. A silent false
      // would let an aeroplane needing the endorsement pass as one that does
      // not — CLAUDE.md: a wrong answer is worse than no answer.
      expect(isHighPerformance(aircraftFromFixture('g_multicrew')), isNull);
    });
  });

  group('§61.129(j) technically advanced', () {
    test('needs all three of PFD, moving-map MFD and integrated autopilot', () {
      expect(isTechnicallyAdvanced(aircraftFromFixture('n456bd')), isTrue);
      expect(isTechnicallyAdvanced(aircraftFromFixture('g_abcd')), isFalse);
    });

    test('each condition alone is insufficient', () {
      final advanced = aircraftFromFixture('n456bd');

      for (final missing in <AircraftEquipment>[
        AircraftEquipment.primaryFlightDisplay,
        AircraftEquipment.multiFunctionDisplayWithMovingMap,
        AircraftEquipment.integratedAutopilot,
      ]) {
        final without = advanced.copyWith(
          equipment: advanced.equipment.difference(<AircraftEquipment>{
            missing,
          }),
        );
        expect(
          isTechnicallyAdvanced(without),
          isFalse,
          reason: 'still technically advanced without $missing',
        );
      }
    });

    test('an EASA glass cockpit is not the same test', () {
      // GM1 FCL.700 EFIS and §61.129(j) draw different lines. The A320 has
      // EFIS and an integrated autopilot but no moving-map MFD recorded, so
      // it is not technically advanced — which is why the two are separate
      // facts rather than one standing in for the other.
      final jet = aircraftFromFixture('g_multicrew');

      expect(
        jet.equipment.contains(
          AircraftEquipment.electronicFlightInstrumentSystem,
        ),
        isTrue,
      );
      expect(isTechnicallyAdvanced(jet), isFalse);
    });
  });

  group('§61.31(a) FAA type rating', () {
    test('a light jet is caught by propulsion, not weight', () {
      // The Citation Mustang: 8,645 lb, well under the 12,500 lb limb, and
      // still type-rated. Its engines are turbofans, so a narrow reading of
      // "turbojet-powered" would let every light jet through.
      final mustang = aircraftFromFixture('n700cm');

      expect(
        mustang.maximumTakeoffMass!.exceeds(faaTypeRatingMassThreshold),
        isFalse,
      );
      expect(requiresFaaTypeRating(mustang), isTrue);
    });

    test('weight alone catches a heavy propeller aeroplane', () {
      final light = aircraftFromFixture('g_abcd');
      expect(requiresFaaTypeRating(light), isFalse);

      expect(
        requiresFaaTypeRating(
          light.copyWith(maximumTakeoffMass: const Mass.pounds(12501)),
        ),
        isTrue,
      );
    });

    test('is exactly 12,500 lb, not 12,500 or more', () {
      // "more than 12,500 pounds". 12,500 lb is a very common certification
      // limit precisely because it is the threshold, so an off-by-one here
      // would be hit often.
      final base = aircraftFromFixture('g_abcd');

      expect(
        requiresFaaTypeRating(
          base.copyWith(maximumTakeoffMass: const Mass.pounds(12500)),
        ),
        isFalse,
      );
    });

    test('comparing across units does not lose the boundary', () {
      // 12,500 lb is 5669.904625 kg. Storing kilograms and converting back is
      // what would misclassify an aeroplane sitting exactly on the line —
      // this is the reason Mass keeps the certificated unit.
      final base = aircraftFromFixture('g_abcd');

      expect(
        requiresFaaTypeRating(
          base.copyWith(maximumTakeoffMass: const Mass.kilograms(5669)),
        ),
        isFalse,
      );
      expect(
        requiresFaaTypeRating(
          base.copyWith(maximumTakeoffMass: const Mass.kilograms(5670)),
        ),
        isTrue,
      );
    });

    test('answers null when neither limb can be evaluated', () {
      final base = aircraftFromFixture('g_abcd');
      expect(
        requiresFaaTypeRating(base.copyWith(maximumTakeoffMass: null)),
        isNull,
      );
    });
  });

  group('§61.31(g) high altitude', () {
    test('takes the lower of service ceiling and max operating altitude', () {
      // The A320: 39,800 ft service ceiling, 39,100 ft max operating. The rule
      // compares the lower, so an airframe capable of 30,000 ft but limited to
      // 24,000 ft in operation needs no endorsement.
      final jet = aircraftFromFixture('g_multicrew');

      expect(jet.serviceCeilingFeet, 39800);
      expect(jet.maximumOperatingAltitudeFeet, 39100);
      expect(requiresHighAltitudeEndorsement(jet), isTrue);

      final limited = jet.copyWith(maximumOperatingAltitudeFeet: 24000);
      expect(requiresHighAltitudeEndorsement(limited), isFalse);
    });

    test('is above 25,000 ft, not at it', () {
      final base = aircraftFromFixture('g_abcd');

      expect(
        requiresHighAltitudeEndorsement(
          base.copyWith(serviceCeilingFeet: 25000),
        ),
        isFalse,
      );
      expect(
        requiresHighAltitudeEndorsement(
          base.copyWith(serviceCeilingFeet: 25001),
        ),
        isTrue,
      );
    });

    test('is not the same question as being pressurised', () {
      // Plenty of pressurised aeroplanes sit below the threshold. If the
      // primitive consulted the pressurised flag this would go red.
      final base = aircraftFromFixture('g_abcd').copyWith(
        serviceCeilingFeet: 20000,
        equipment: <AircraftEquipment>{
          AircraftEquipment.flaps,
          AircraftEquipment.pressurised,
        },
      );

      expect(requiresHighAltitudeEndorsement(base), isFalse);
    });

    test('answers null when no altitude is recorded', () {
      final base = aircraftFromFixture('g_abcd');
      expect(
        requiresHighAltitudeEndorsement(
          base.copyWith(
            serviceCeilingFeet: null,
            maximumOperatingAltitudeFeet: null,
          ),
        ),
        isNull,
      );
    });
  });

  group('Mass', () {
    test('compares exactly across units', () {
      // The international pound is exactly 0.45359237 kg, so this is not an
      // approximation.
      expect(
        const Mass.pounds(12500).exceeds(const Mass.kilograms(5669)),
        isTrue,
      );
      expect(
        const Mass.pounds(12500).exceeds(const Mass.kilograms(5670)),
        isFalse,
      );
      expect(
        const Mass.kilograms(1000).exceeds(const Mass.pounds(2204)),
        isTrue,
      );
      expect(
        const Mass.kilograms(1000).exceeds(const Mass.pounds(2205)),
        isFalse,
      );
    });

    test('equality is by mass, not by unit', () {
      expect(const Mass.kilograms(1000) == const Mass.kilograms(1000), isTrue);
      expect(const Mass.kilograms(1000) == const Mass.pounds(1000), isFalse);
      // The duplicate is the point: the set must collapse it. Built from a
      // list rather than a set literal, because `equal_elements_in_set`
      // rightly objects to a literal whose elements are visibly equal.
      const duplicates = <Mass>[Mass.kilograms(1000), Mass.kilograms(1000)];
      expect(duplicates.toSet(), hasLength(1));
    });

    test('keeps the certificated unit in its printed form', () {
      expect(const Mass.pounds(12500).toString(), '12500 lb');
      expect(const Mass.kilograms(5670).toString(), '5670 kg');
    });
  });

  group('the fixture decoder', () {
    test('rejects an unknown equipment spelling rather than ignoring it', () {
      // Silently dropping an attribute it does not recognise would make an
      // aircraft look less capable than it is, and change what §61.31 says
      // about it.
      expect(
        () => aircraftFromFixture('malformed/unknown_equipment'),
        throwsA(
          isA<FixtureFieldException>().having((e) => e.key, 'key', 'equipment'),
        ),
      );
    });

    test('rejects a missing required field', () {
      expect(
        () => aircraftFromFixture('malformed/missing_category'),
        throwsA(
          isA<FixtureFieldException>().having((e) => e.key, 'key', 'category'),
        ),
      );
    });
  });
}
