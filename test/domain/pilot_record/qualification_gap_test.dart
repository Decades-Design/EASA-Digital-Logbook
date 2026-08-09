import 'package:easa_digital_log/domain/model/aircraft.dart';
import 'package:easa_digital_log/domain/model/calendar_date.dart';
import 'package:easa_digital_log/domain/pilot_record/held_aircraft_qualification.dart';
import 'package:easa_digital_log/domain/pilot_record/held_rating.dart';
import 'package:easa_digital_log/domain/pilot_record/qualification_gap.dart';
import 'package:flutter_test/flutter_test.dart';

const _easa = 'eu.easa.part-fcl';
const _faa = 'us.faa.part61';

Aircraft _arrow({String? typeRatingDesignator}) => Aircraft(
  registration: 'G-ARRW',
  manufacturer: 'Piper',
  model: 'Arrow',
  category: AircraftCategory.aeroplane,
  engineType: EngineType.piston,
  engineCount: 1,
  operatingSurface: OperatingSurface.land,
  requiresMultiCrew: false,
  typeRatingDesignator: typeRatingDesignator,
  requiredQualifications: const {
    _easa: {
      AircraftQualification.easaVariablePitchPropeller,
      AircraftQualification.easaRetractableUndercarriage,
    },
    _faa: {AircraftQualification.faaComplex},
  },
);

void main() {
  group('qualificationGaps (#105)', () {
    test('the pilot holds everything required: no gaps', () {
      final held = [
        HeldAircraftQualification(
          qualification: AircraftQualification.easaVariablePitchPropeller,
          jurisdictionId: _easa,
          dateGranted: CalendarDate(2020, 1, 1),
        ),
        HeldAircraftQualification(
          qualification: AircraftQualification.easaRetractableUndercarriage,
          jurisdictionId: _easa,
          dateGranted: CalendarDate(2020, 1, 1),
        ),
      ];

      final gaps = qualificationGaps(
        aircraft: _arrow(),
        jurisdictionId: _easa,
        heldAircraftQualifications: held,
        heldRatings: const [],
        asOf: CalendarDate(2024, 1, 1),
      );

      expect(gaps, isEmpty);
    });

    test('a required qualification the pilot does not hold is a gap', () {
      final held = [
        HeldAircraftQualification(
          qualification: AircraftQualification.easaVariablePitchPropeller,
          jurisdictionId: _easa,
          dateGranted: CalendarDate(2020, 1, 1),
        ),
      ];

      final gaps = qualificationGaps(
        aircraft: _arrow(),
        jurisdictionId: _easa,
        heldAircraftQualifications: held,
        heldRatings: const [],
        asOf: CalendarDate(2024, 1, 1),
      );

      expect(gaps, [
        QualificationGap.aircraftQualification(
          AircraftQualification.easaRetractableUndercarriage,
        ),
      ]);
    });

    test(
      'a set typeRatingDesignator with no matching held rating is a gap',
      () {
        final gaps = qualificationGaps(
          aircraft: _arrow(typeRatingDesignator: 'PA46'),
          jurisdictionId: _easa,
          heldAircraftQualifications: const [
            HeldAircraftQualification(
              qualification: AircraftQualification.easaVariablePitchPropeller,
              jurisdictionId: _easa,
              dateGranted: CalendarDate(2020, 1, 1),
            ),
            HeldAircraftQualification(
              qualification: AircraftQualification.easaRetractableUndercarriage,
              jurisdictionId: _easa,
              dateGranted: CalendarDate(2020, 1, 1),
            ),
          ],
          heldRatings: const [],
          asOf: CalendarDate(2024, 1, 1),
        );

        expect(gaps, [QualificationGap.typeRating('PA46')]);
      },
    );

    test('an expired type rating is a gap, not a pass', () {
      final gaps = qualificationGaps(
        aircraft: _arrow(typeRatingDesignator: 'PA46'),
        jurisdictionId: _easa,
        heldAircraftQualifications: const [
          HeldAircraftQualification(
            qualification: AircraftQualification.easaVariablePitchPropeller,
            jurisdictionId: _easa,
            dateGranted: CalendarDate(2020, 1, 1),
          ),
          HeldAircraftQualification(
            qualification: AircraftQualification.easaRetractableUndercarriage,
            jurisdictionId: _easa,
            dateGranted: CalendarDate(2020, 1, 1),
          ),
        ],
        heldRatings: [
          HeldRating(
            kind: HeldRatingKind.typeRating,
            designator: 'PA46',
            jurisdictionId: _easa,
            issueDate: CalendarDate(2022, 1, 1),
            expiryDate: CalendarDate(2023, 1, 1),
          ),
        ],
        asOf: CalendarDate(2024, 1, 1),
      );

      expect(gaps, [QualificationGap.typeRating('PA46')]);
    });

    test('a currently-valid type rating satisfies the requirement', () {
      final gaps = qualificationGaps(
        aircraft: _arrow(typeRatingDesignator: 'PA46'),
        jurisdictionId: _easa,
        heldAircraftQualifications: const [
          HeldAircraftQualification(
            qualification: AircraftQualification.easaVariablePitchPropeller,
            jurisdictionId: _easa,
            dateGranted: CalendarDate(2020, 1, 1),
          ),
          HeldAircraftQualification(
            qualification: AircraftQualification.easaRetractableUndercarriage,
            jurisdictionId: _easa,
            dateGranted: CalendarDate(2020, 1, 1),
          ),
        ],
        heldRatings: [
          HeldRating(
            kind: HeldRatingKind.typeRating,
            designator: 'PA46',
            jurisdictionId: _easa,
            issueDate: CalendarDate(2023, 1, 1),
            expiryDate: CalendarDate(2025, 1, 1),
          ),
        ],
        asOf: CalendarDate(2024, 1, 1),
      );

      expect(gaps, isEmpty);
    });

    test('an FAA type rating with no stored expiry is held permanently', () {
      final gaps = qualificationGaps(
        aircraft: _arrow(typeRatingDesignator: 'PA46'),
        jurisdictionId: _faa,
        heldAircraftQualifications: const [
          HeldAircraftQualification(
            qualification: AircraftQualification.faaComplex,
            jurisdictionId: _faa,
            dateGranted: CalendarDate(2020, 1, 1),
          ),
        ],
        heldRatings: [
          HeldRating(
            kind: HeldRatingKind.typeRating,
            designator: 'PA46',
            jurisdictionId: _faa,
            issueDate: CalendarDate(2010, 1, 1),
          ),
        ],
        asOf: CalendarDate(2040, 1, 1),
      );

      expect(gaps, isEmpty);
    });

    test(
      'an aircraft never set up for a jurisdiction (absent key) produces no warning',
      () {
        const aircraft = Aircraft(
          registration: 'G-NEW',
          manufacturer: 'Cessna',
          model: '172',
          category: AircraftCategory.aeroplane,
          engineType: EngineType.piston,
          engineCount: 1,
          operatingSurface: OperatingSurface.land,
          requiresMultiCrew: false,
        );

        final gaps = qualificationGaps(
          aircraft: aircraft,
          jurisdictionId: _easa,
          heldAircraftQualifications: const [],
          heldRatings: const [],
          asOf: CalendarDate(2024, 1, 1),
        );

        expect(gaps, isEmpty);
      },
    );

    test(
      'an aircraft set up with an empty required set produces no warning',
      () {
        const aircraft = Aircraft(
          registration: 'G-NEW',
          manufacturer: 'Cessna',
          model: '172',
          category: AircraftCategory.aeroplane,
          engineType: EngineType.piston,
          engineCount: 1,
          operatingSurface: OperatingSurface.land,
          requiresMultiCrew: false,
          requiredQualifications: {_easa: {}},
        );

        final gaps = qualificationGaps(
          aircraft: aircraft,
          jurisdictionId: _easa,
          heldAircraftQualifications: const [],
          heldRatings: const [],
          asOf: CalendarDate(2024, 1, 1),
        );

        expect(gaps, isEmpty);
      },
    );

    test(
      'runs per licence: a gap under one jurisdiction is not a gap under another',
      () {
        final held = [
          HeldAircraftQualification(
            qualification: AircraftQualification.faaComplex,
            jurisdictionId: _faa,
            dateGranted: CalendarDate(2020, 1, 1),
          ),
        ];
        final aircraft = _arrow();

        final easaGaps = qualificationGaps(
          aircraft: aircraft,
          jurisdictionId: _easa,
          heldAircraftQualifications: held,
          heldRatings: const [],
          asOf: CalendarDate(2024, 1, 1),
        );
        final faaGaps = qualificationGaps(
          aircraft: aircraft,
          jurisdictionId: _faa,
          heldAircraftQualifications: held,
          heldRatings: const [],
          asOf: CalendarDate(2024, 1, 1),
        );

        expect(easaGaps, isNotEmpty);
        expect(faaGaps, isEmpty);
      },
    );
  });
}
