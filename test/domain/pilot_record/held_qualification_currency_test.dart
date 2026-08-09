import 'package:easa_digital_log/domain/currency/currency_rule.dart';
import 'package:easa_digital_log/domain/currency/currency_rule_evaluator.dart';
import 'package:easa_digital_log/domain/currency/evaluation_subject.dart';
import 'package:easa_digital_log/domain/model/aircraft.dart';
import 'package:easa_digital_log/domain/model/calendar_date.dart';
import 'package:easa_digital_log/domain/pilot_record/held_aircraft_qualification.dart';
import 'package:easa_digital_log/domain/pilot_record/held_qualification_records.dart';
import 'package:easa_digital_log/domain/pilot_record/held_rating.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const evaluator = CurrencyRuleEvaluator();

  test(
    'an EASA and an FAA instrument rating do not interfere with each other',
    () {
      // #52: "a pilot holding both an EASA and an FAA licence has independent
      // rating sets that do not interfere." The FAA IR never expires; the
      // EASA IR has lapsed. Checking "am I current on my EASA IR" must not
      // be satisfied by the still-valid FAA one just because both are
      // nominally "an instrument rating".
      final easaIr = HeldRating(
        kind: HeldRatingKind.instrumentRating,
        designator: 'IR',
        jurisdictionId: 'eu.easa.part-fcl',
        issueDate: CalendarDate(2020, 1, 1),
        expiryDate: CalendarDate(2021, 1, 1), // lapsed
      );
      final faaIr = HeldRating(
        kind: HeldRatingKind.instrumentRating,
        designator: 'IR',
        jurisdictionId: 'us.faa.part61',
        issueDate: CalendarDate(2020, 1, 1),
        // no expiryDate -- FAA instrument ratings never expire.
      );
      final subject = EvaluationSubject(
        flights: const [],
        heldRecords: [
          heldRatingHeldRecord(easaIr),
          heldRatingHeldRecord(faaIr),
        ],
      );

      final easaRequirement = Requirement.heldRecordCurrentlyValid(
        'rating.eu.easa.part-fcl.instrumentRating.IR',
      );
      final faaRequirement = Requirement.heldRecordCurrentlyValid(
        'rating.us.faa.part61.instrumentRating.IR',
      );

      final asOf = CalendarDate(2024, 1, 1);
      expect(
        evaluator.evaluateRequirement(easaRequirement, subject, asOf).satisfied,
        isFalse,
      );
      expect(
        evaluator.evaluateRequirement(faaRequirement, subject, asOf).satisfied,
        isTrue,
      );
    },
  );

  test(
    'a type rating keys on the same designator string Aircraft carries, joining two registrations of one type',
    () {
      const airbus1 = Aircraft(
        registration: 'G-ONE',
        manufacturer: 'Airbus',
        model: 'A320',
        typeRatingDesignator: 'A320',
        category: AircraftCategory.aeroplane,
        engineType: EngineType.turbofan,
        engineCount: 2,
        operatingSurface: OperatingSurface.land,
        requiresMultiCrew: true,
      );
      const airbus2 = Aircraft(
        registration: 'G-TWO',
        manufacturer: 'Airbus',
        model: 'A320',
        typeRatingDesignator: 'A320',
        category: AircraftCategory.aeroplane,
        engineType: EngineType.turbofan,
        engineCount: 2,
        operatingSurface: OperatingSurface.land,
        requiresMultiCrew: true,
      );
      // One held rating, naming the type once.
      final held = HeldRating(
        kind: HeldRatingKind.typeRating,
        designator: 'A320',
        jurisdictionId: 'eu.easa.part-fcl',
        issueDate: CalendarDate(2024, 1, 1),
        expiryDate: CalendarDate(2025, 1, 1),
      );

      // The held record's kind is built from the rating's own designator,
      // independent of which specific registration is being asked about --
      // it resolves the same way for either airframe.
      expect(
        held.designator,
        airbus1.typeRatingDesignator,
        reason: 'same string space as Aircraft.typeRatingDesignator',
      );
      expect(held.designator, airbus2.typeRatingDesignator);
      expect(heldRatingHeldRecord(held).kind, contains('A320'));
    },
  );

  test(
    'differences training is a raw fact with no expiry, so it is always currently valid once granted',
    () {
      final held = HeldAircraftQualification(
        qualification: AircraftQualification.easaRetractableUndercarriage,
        jurisdictionId: 'eu.easa.part-fcl',
        dateGranted: CalendarDate(2015, 1, 1),
        signatoryName: 'A. Instructor',
        signatoryCredentialNumber: 'FI-42',
      );
      final requirement = Requirement.heldRecordCurrentlyValid(
        'aircraft_qualification.eu.easa.part-fcl.easaRetractableUndercarriage',
      );
      final subject = EvaluationSubject(
        flights: const [],
        heldRecords: [heldAircraftQualificationHeldRecord(held)],
      );

      // Ten years after being granted, with no revalidation of any kind.
      final result = evaluator.evaluateRequirement(
        requirement,
        subject,
        CalendarDate(2025, 1, 1),
      );

      expect(result.satisfied, isTrue);
      expect(result.expiresOn, isNull);
    },
  );
}
