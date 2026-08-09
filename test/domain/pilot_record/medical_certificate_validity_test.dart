import 'package:easa_digital_log/domain/model/calendar_date.dart';
import 'package:easa_digital_log/domain/pilot_record/medical_certificate.dart';
import 'package:easa_digital_log/domain/pilot_record/medical_certificate_validity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('EASA Class 2 (age-banded, MED.A.045)', () {
    test('issued well under 40: 60 months, no cap triggered', () {
      final certificate = MedicalCertificate(
        certificateClass: MedicalCertificateClass.easaClass2,
        jurisdictionId: 'eu.easa.part-fcl',
        issueDate: CalendarDate(2024, 1, 15),
      );
      final dateOfBirth = CalendarDate(1999, 6, 1); // 24 at issue

      final record = medicalCertificateHeldRecord(certificate, dateOfBirth);

      expect(record.validFrom, CalendarDate(2024, 1, 15));
      expect(record.validUntil, CalendarDate(2029, 1, 31));
    });

    test(
      'the birthday-crossing trap: issued at 39, capped at the 42nd birthday, not issue+60mo',
      () {
        final dateOfBirth = CalendarDate(1985, 3, 10);
        final certificate = MedicalCertificate(
          certificateClass: MedicalCertificateClass.easaClass2,
          jurisdictionId: 'eu.easa.part-fcl',
          issueDate: CalendarDate(
            2024,
            1,
            15,
          ), // holder is 38, turns 39 on 2024-03-10
        );

        final record = medicalCertificateHeldRecord(certificate, dateOfBirth);

        // Nominal 60-month validity would run to 2029-01-31, well past the
        // holder's 42nd birthday (2027-03-10) -- the cap wins.
        expect(record.validUntil, CalendarDate(2027, 3, 10));
      },
    );

    test('issued at 40-49: 24 months', () {
      final dateOfBirth = CalendarDate(1979, 1, 1);
      final certificate = MedicalCertificate(
        certificateClass: MedicalCertificateClass.easaClass2,
        jurisdictionId: 'eu.easa.part-fcl',
        issueDate: CalendarDate(2024, 6, 1), // 45 at issue
      );

      final record = medicalCertificateHeldRecord(certificate, dateOfBirth);

      expect(record.validUntil, CalendarDate(2026, 6, 30));
    });

    test(
      'issued at 49, capped at the 51st birthday rather than the full 24 months',
      () {
        final dateOfBirth = CalendarDate(1975, 4, 20);
        final certificate = MedicalCertificate(
          certificateClass: MedicalCertificateClass.easaClass2,
          jurisdictionId: 'eu.easa.part-fcl',
          issueDate: CalendarDate(2024, 6, 1), // 49 at issue
        );

        final record = medicalCertificateHeldRecord(certificate, dateOfBirth);

        // Nominal 24 months would run to 2026-06-30, past the 51st birthday
        // (2026-04-20).
        expect(record.validUntil, CalendarDate(2026, 4, 20));
      },
    );

    test('issued at 50 or older: 12 months, no cap needed', () {
      final dateOfBirth = CalendarDate(1970, 1, 1);
      final certificate = MedicalCertificate(
        certificateClass: MedicalCertificateClass.easaClass2,
        jurisdictionId: 'eu.easa.part-fcl',
        issueDate: CalendarDate(2024, 6, 1), // 54 at issue
      );

      final record = medicalCertificateHeldRecord(certificate, dateOfBirth);

      expect(record.validUntil, CalendarDate(2025, 6, 30));
    });

    test('a leap-day birthday caps on Feb 28 in a non-leap target year', () {
      final dateOfBirth = CalendarDate(1984, 2, 29);
      final certificate = MedicalCertificate(
        certificateClass: MedicalCertificateClass.easaClass2,
        jurisdictionId: 'eu.easa.part-fcl',
        issueDate: CalendarDate(2023, 6, 1), // 39 at issue
      );

      final record = medicalCertificateHeldRecord(certificate, dateOfBirth);

      // 42nd birthday would be 2026-02-29, but 2026 is not a leap year.
      expect(record.validUntil, CalendarDate(2026, 2, 28));
    });
  });

  group('EASA Class 1 (flat, single-pilot commercial reduction deferred)', () {
    test('12 months regardless of age', () {
      final certificate = MedicalCertificate(
        certificateClass: MedicalCertificateClass.easaClass1,
        jurisdictionId: 'eu.easa.part-fcl',
        issueDate: CalendarDate(2024, 1, 15),
      );
      final dateOfBirth = CalendarDate(1960, 1, 1); // 64 at issue

      final record = medicalCertificateHeldRecord(certificate, dateOfBirth);

      expect(record.validUntil, CalendarDate(2025, 1, 31));
    });
  });

  group(
    'FAA (§61.23(d), private/recreational/student tier -- no clawback cap)',
    () {
      test(
        'issued under 40: 60 months, full duration even if a birthday falls within it',
        () {
          final dateOfBirth = CalendarDate(1985, 3, 10);
          final certificate = MedicalCertificate(
            certificateClass: MedicalCertificateClass.faaThirdClass,
            jurisdictionId: 'us.faa.part61',
            issueDate: CalendarDate(
              2024,
              1,
              15,
            ), // 38, turns 40 well within the window
          );

          final record = medicalCertificateHeldRecord(certificate, dateOfBirth);

          // Unlike EASA Class 2, the FAA table has no cap -- the full 60
          // months stands even though the holder turns 40 partway through.
          expect(record.validUntil, CalendarDate(2029, 1, 31));
        },
      );

      test('issued at 40 or older: 24 months', () {
        final dateOfBirth = CalendarDate(1980, 1, 1);
        final certificate = MedicalCertificate(
          certificateClass: MedicalCertificateClass.faaFirstClass,
          jurisdictionId: 'us.faa.part61',
          issueDate: CalendarDate(2024, 6, 1), // 44 at issue
        );

        final record = medicalCertificateHeldRecord(certificate, dateOfBirth);

        expect(record.validUntil, CalendarDate(2026, 6, 30));
      });

      test('all three FAA classes use the same private-tier table', () {
        final dateOfBirth = CalendarDate(1990, 1, 1);
        final issueDate = CalendarDate(2024, 1, 1); // 34 at issue
        for (final certificateClass in [
          MedicalCertificateClass.faaFirstClass,
          MedicalCertificateClass.faaSecondClass,
          MedicalCertificateClass.faaThirdClass,
        ]) {
          final certificate = MedicalCertificate(
            certificateClass: certificateClass,
            jurisdictionId: 'us.faa.part61',
            issueDate: issueDate,
          );
          final record = medicalCertificateHeldRecord(certificate, dateOfBirth);
          expect(
            record.validUntil,
            CalendarDate(2029, 1, 31),
            reason: certificateClass.name,
          );
        }
      });
    },
  );

  test(
    'validFrom is the issue date and the held-record kind names the class',
    () {
      final certificate = MedicalCertificate(
        certificateClass: MedicalCertificateClass.easaClass1,
        jurisdictionId: 'eu.easa.part-fcl',
        issueDate: CalendarDate(2024, 1, 15),
      );

      final record = medicalCertificateHeldRecord(
        certificate,
        CalendarDate(1990, 1, 1),
      );

      expect(record.validFrom, CalendarDate(2024, 1, 15));
      expect(record.kind, 'medical_certificate.easaClass1');
    },
  );
}
