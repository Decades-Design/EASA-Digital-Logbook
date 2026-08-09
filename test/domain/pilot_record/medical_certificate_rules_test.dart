import 'dart:io';

import 'package:easa_digital_log/domain/currency/currency_rule.dart';
import 'package:easa_digital_log/domain/currency/currency_rule_evaluator.dart';
import 'package:easa_digital_log/domain/currency/currency_rule_yaml.dart';
import 'package:easa_digital_log/domain/currency/evaluation_subject.dart';
import 'package:easa_digital_log/domain/model/calendar_date.dart';
import 'package:easa_digital_log/domain/pilot_record/medical_certificate.dart';
import 'package:easa_digital_log/domain/pilot_record/medical_certificate_validity.dart';
import 'package:flutter_test/flutter_test.dart';

CurrencyRule _loadRule(String path) =>
    parseCurrencyRuleYaml(File(path).readAsStringSync());

void main() {
  const evaluator = CurrencyRuleEvaluator();

  group('eu.easa.med_a045.class2_validity end to end', () {
    final rule = _loadRule('assets/rules/easa/med_a045_class2_validity.yaml');

    test(
      'currently valid just inside the birthday cap, not just inside the nominal duration',
      () {
        // Issued at 39; nominal 60 months would run past the 42nd birthday,
        // but the cap governs -- so asking "am I current" the day before the
        // 42nd birthday must say yes, and the day of/after must say no, even
        // though the nominal 60-month window hasn't elapsed either way.
        final dateOfBirth = CalendarDate(1985, 3, 10);
        final certificate = MedicalCertificate(
          certificateClass: MedicalCertificateClass.easaClass2,
          jurisdictionId: 'eu.easa.part-fcl',
          issueDate: CalendarDate(2024, 1, 15),
        );
        final heldRecord = medicalCertificateHeldRecord(
          certificate,
          dateOfBirth,
        );

        final dayBeforeCap = evaluator.evaluateRequirement(
          rule.requirement,
          EvaluationSubject(flights: const [], heldRecords: [heldRecord]),
          CalendarDate(2027, 3, 9),
        );
        final onCapDate = evaluator.evaluateRequirement(
          rule.requirement,
          EvaluationSubject(flights: const [], heldRecords: [heldRecord]),
          CalendarDate(2027, 3, 11),
        );

        expect(dayBeforeCap.satisfied, isTrue);
        expect(onCapDate.satisfied, isFalse);
      },
    );

    test('not current with no medical certificate on file at all', () {
      final result = evaluator.evaluateRequirement(
        rule.requirement,
        const EvaluationSubject(flights: []),
        CalendarDate(2024, 1, 1),
      );

      expect(result.satisfied, isFalse);
    });
  });

  group('us.faa.61_23.third_class_medical_validity end to end', () {
    final rule = _loadRule(
      'assets/rules/faa/61_23_third_class_medical_validity.yaml',
    );

    test(
      'the same FAA certificate stays valid across a birthday EASA would have clawed back',
      () {
        final dateOfBirth = CalendarDate(1985, 3, 10);
        final certificate = MedicalCertificate(
          certificateClass: MedicalCertificateClass.faaThirdClass,
          jurisdictionId: 'us.faa.part61',
          issueDate: CalendarDate(2024, 1, 15),
        );
        final heldRecord = medicalCertificateHeldRecord(
          certificate,
          dateOfBirth,
        );

        // EASA Class 2 with this same issue date/DOB lapses 2027-03-10 (the
        // capped 42nd birthday) -- see the class2_validity test above. FAA's
        // equivalent has no cap and runs the full 60 months.
        final result = evaluator.evaluateRequirement(
          rule.requirement,
          EvaluationSubject(flights: const [], heldRecords: [heldRecord]),
          CalendarDate(2027, 3, 11),
        );

        expect(result.satisfied, isTrue);
      },
    );
  });
}
