// flutter_test re-exports test/group/expect from package:test_api, so plain
// Dart tests need no separate package:test dependency.
import 'package:easa_digital_log/domain/model/aircraft.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../fixtures/decoders/aircraft_fixture.dart';
import '../../fixtures/decoders/fixture_fields.dart';

/// Every aircraft fixture, by name. Add one here when you add the file.
const List<String> aircraftFixtures = <String>[
  'g_abcd',
  'n456bd',
  'g_arrow',
  'g_c206',
  'g_multicrew',
  'g_tailwheel_tmg',
];

const String faa = 'us.faa.part61';
const String easa = 'eu.easa.part-fcl';

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

    test('every discriminator varies across the set', () {
      // A field that never changes across every fixture is untested surface.
      final all = aircraftFixtures.map(aircraftFromFixture).toList();

      expect(all.map((a) => a.requiresMultiCrew).toSet(), <bool>{true, false});
      expect(
        all.map((a) => a.category).toSet(),
        containsAll(<AircraftCategory>[
          AircraftCategory.aeroplane,
          AircraftCategory.touringMotorGlider,
        ]),
      );
      expect(
        all.any((a) => a.typeRatingDesignator != null),
        isTrue,
        reason: 'nothing exercises the type-rated path',
      );
      expect(
        all.any((a) => a.icaoTypeDesignator == null),
        isTrue,
        reason: 'nothing exercises an aircraft without an ICAO designator',
      );
    });
  });

  group('required qualifications', () {
    test('an absent authority is not the same as an empty list', () {
      // The distinction the Map exists for. G-EZAB has never been set up under
      // Part 61; G-ABCD has, and requires nothing. Collapsing the two would
      // tell a pilot an aeroplane needs no FAA endorsements when nobody has
      // ever looked.
      final neverSetUp = aircraftFromFixture('g_multicrew');
      final setUpAndClear = aircraftFromFixture('g_abcd');

      expect(neverSetUp.requiredQualifications.containsKey(faa), isFalse);
      expect(neverSetUp.requiredQualifications[faa], isNull);

      expect(setUpAndClear.requiredQualifications.containsKey(faa), isTrue);
      expect(setUpAndClear.requiredQualifications[faa], isEmpty);
    });

    test('the two authorities reach different lists for one aeroplane', () {
      final bonanza = aircraftFromFixture('n456bd');

      expect(bonanza.requiredQualifications[faa], <AircraftQualification>{
        AircraftQualification.faaComplex,
        AircraftQualification.faaHighPerformance,
      });
      expect(bonanza.requiredQualifications[easa], <AircraftQualification>{
        AircraftQualification.easaVariablePitchPropeller,
        AircraftQualification.easaRetractableUndercarriage,
        AircraftQualification.easaElectronicFlightInstrumentSystem,
      });
    });

    test('complex and high performance are independent of each other', () {
      // docs/ratings-and-endorsements.md §3, both asymmetry cases at once.
      // The Arrow is complex and not high performance; the 206 is the exact
      // reverse. Any code treating one as implying the other fails here.
      final arrow = aircraftFromFixture('g_arrow');
      final stationair = aircraftFromFixture('g_c206');

      expect(arrow.requiredQualifications[faa], <AircraftQualification>{
        AircraftQualification.faaComplex,
      });
      expect(stationair.requiredQualifications[faa], <AircraftQualification>{
        AircraftQualification.faaHighPerformance,
      });

      // And their EASA lists differ by exactly the retractable item, which is
      // the only physical difference between them that EASA cares about.
      expect(
        arrow.requiredQualifications[easa]!.difference(
          stationair.requiredQualifications[easa]!,
        ),
        <AircraftQualification>{
          AircraftQualification.easaRetractableUndercarriage,
        },
      );
    });

    test('tailwheel is recorded separately under each authority', () {
      // The one item that maps roughly one-to-one. It is still two values,
      // because holding an FAA tailwheel endorsement says nothing about
      // having had EASA differences training, and vice versa.
      final tmg = aircraftFromFixture('g_tailwheel_tmg');

      expect(
        tmg.requiredQualifications[faa],
        contains(AircraftQualification.faaTailwheel),
      );
      expect(
        tmg.requiredQualifications[easa],
        contains(AircraftQualification.easaTailwheel),
      );
    });
  });

  group('type ratings', () {
    test('the identifier alone says whether one is required', () {
      // No boolean beside it, so "true with no identifier" and "false with
      // one" are states the model cannot express.
      expect(aircraftFromFixture('g_multicrew').typeRatingDesignator, 'A320');
      expect(aircraftFromFixture('g_abcd').typeRatingDesignator, isNull);
    });

    test('two registrations sharing an identifier share one rating', () {
      // The join. A second A32N carries the same designator, so both resolve
      // to the one type rating the pilot holds, with one validity date —
      // revalidating updates one record rather than one per airframe.
      final first = aircraftFromFixture('g_multicrew');
      final second = first.copyWith(registration: 'G-EZBB');

      expect(first.registration, isNot(second.registration));
      expect(first.typeRatingDesignator, second.typeRatingDesignator);
    });
  });

  group('the fixture decoder', () {
    test('rejects an unknown qualification rather than dropping it', () {
      // Silently dropping it would make the aeroplane look as though it needs
      // less than the pilot said. "faa_complex_high_performance" is the
      // plausible mistake — one value where two are required.
      expect(
        () => aircraftFromFixture('malformed/unknown_qualification'),
        throwsA(
          isA<FixtureFieldException>().having(
            (e) => e.key,
            'key',
            'required_qualifications.$faa',
          ),
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
