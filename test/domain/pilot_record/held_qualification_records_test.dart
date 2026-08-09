import 'package:easa_digital_log/domain/model/aircraft.dart';
import 'package:easa_digital_log/domain/model/calendar_date.dart';
import 'package:easa_digital_log/domain/pilot_record/held_aircraft_qualification.dart';
import 'package:easa_digital_log/domain/pilot_record/held_qualification_records.dart';
import 'package:easa_digital_log/domain/pilot_record/held_rating.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('heldAircraftQualificationHeldRecord', () {
    test('never expires, regardless of authority', () {
      final held = HeldAircraftQualification(
        qualification: AircraftQualification.easaVariablePitchPropeller,
        jurisdictionId: 'eu.easa.part-fcl',
        dateGranted: CalendarDate(2020, 1, 1),
        signatoryName: 'A. Instructor',
        signatoryCredentialNumber: 'FI-123',
      );

      final record = heldAircraftQualificationHeldRecord(held);

      expect(record.validFrom, CalendarDate(2020, 1, 1));
      expect(record.validUntil, isNull);
      expect(
        record.kind,
        'aircraft_qualification.eu.easa.part-fcl.easaVariablePitchPropeller',
      );
    });

    test('an FAA endorsement also never expires', () {
      final held = HeldAircraftQualification(
        qualification: AircraftQualification.faaHighPerformance,
        jurisdictionId: 'us.faa.part61',
        dateGranted: CalendarDate(2020, 1, 1),
      );

      expect(heldAircraftQualificationHeldRecord(held).validUntil, isNull);
    });
  });

  group('heldRatingHeldRecord', () {
    test('a class rating\'s stored expiry passes through unchanged', () {
      final held = HeldRating(
        kind: HeldRatingKind.classRating,
        designator: 'SEP(land)',
        jurisdictionId: 'eu.easa.part-fcl',
        issueDate: CalendarDate(2024, 1, 1),
        expiryDate: CalendarDate(2026, 1, 1),
      );

      final record = heldRatingHeldRecord(held);

      expect(record.validFrom, CalendarDate(2024, 1, 1));
      expect(record.validUntil, CalendarDate(2026, 1, 1));
      expect(record.kind, 'rating.eu.easa.part-fcl.classRating.SEP(land)');
    });

    test('an FAA type rating with no stored expiry never expires', () {
      final held = HeldRating(
        kind: HeldRatingKind.typeRating,
        designator: 'A320',
        jurisdictionId: 'us.faa.part61',
        issueDate: CalendarDate(2024, 1, 1),
      );

      expect(heldRatingHeldRecord(held).validUntil, isNull);
    });

    test(
      'two type ratings sharing a designator but different jurisdictions do not interfere',
      () {
        final easa = HeldRating(
          kind: HeldRatingKind.typeRating,
          designator: 'A320',
          jurisdictionId: 'eu.easa.part-fcl',
          issueDate: CalendarDate(2024, 1, 1),
          expiryDate: CalendarDate(2025, 1, 1),
        );
        final faa = HeldRating(
          kind: HeldRatingKind.typeRating,
          designator: 'A320',
          jurisdictionId: 'us.faa.part61',
          issueDate: CalendarDate(2024, 1, 1),
        );

        final easaRecord = heldRatingHeldRecord(easa);
        final faaRecord = heldRatingHeldRecord(faa);

        expect(easaRecord.kind, isNot(faaRecord.kind));
        expect(easaRecord.validUntil, isNotNull);
        expect(faaRecord.validUntil, isNull);
      },
    );

    group('language proficiency (FCL.055), duration computed from level', () {
      test('level 6 never expires, even if a stray expiryDate was stored', () {
        final held = HeldRating(
          kind: HeldRatingKind.languageProficiency,
          designator: 'english',
          jurisdictionId: 'eu.easa.part-fcl',
          issueDate: CalendarDate(2024, 1, 15),
          languageProficiencyLevel: 6,
        );

        expect(heldRatingHeldRecord(held).validUntil, isNull);
      });

      test('level 5 is valid for 6 years', () {
        final held = HeldRating(
          kind: HeldRatingKind.languageProficiency,
          designator: 'english',
          jurisdictionId: 'eu.easa.part-fcl',
          issueDate: CalendarDate(2024, 1, 15),
          languageProficiencyLevel: 5,
        );

        expect(
          heldRatingHeldRecord(held).validUntil,
          CalendarDate(2030, 1, 31),
        );
      });

      test('level 4 is valid for 4 years', () {
        final held = HeldRating(
          kind: HeldRatingKind.languageProficiency,
          designator: 'english',
          jurisdictionId: 'eu.easa.part-fcl',
          issueDate: CalendarDate(2024, 1, 15),
          languageProficiencyLevel: 4,
        );

        expect(
          heldRatingHeldRecord(held).validUntil,
          CalendarDate(2028, 1, 31),
        );
      });
    });
  });
}
