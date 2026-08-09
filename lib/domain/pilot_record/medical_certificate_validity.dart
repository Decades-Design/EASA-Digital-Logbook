import '../currency/held_record.dart';
import '../currency/rule_window.dart';
import '../model/calendar_date.dart';
import 'medical_certificate.dart';

/// Computes the [HeldRecord] a [MedicalCertificate] currently materialises
/// to, for a `held_record_currently_valid` currency rule (#51) to consume.
///
/// Real logic in Dart, not YAML, per CLAUDE.md's "declarative stops" rule:
/// age-banded duration is exactly the kind of thing a rule author
/// references by name rather than expresses inline.
///
/// **Scope boundary, deliberate.** FAA medical validity genuinely depends
/// on which privilege is being exercised on a given flight — `§61.23(d)`'s
/// duration table gives three different answers for the same certificate
/// depending on whether the flight is flown under ATP, commercial or
/// private/recreational/student privileges. This app has no "which
/// privilege" fact anywhere yet, so only the private/recreational/student
/// tier is modelled; commercial and ATP tiering is deferred until that
/// fact exists. Likewise EASA Class 1's reduction to 6 months for
/// single-pilot commercial air transport of passengers at age 40+ (or 60
/// regardless of operation) is not modelled — the same missing fact.
///
/// **⚠️ Source note.** EASA figures were cross-checked against two
/// secondary summaries of `MED.A.045` that initially disagreed on Class
/// 1's structure; the figures here match the source that also correctly
/// described Class 2's birthday-cap mechanism. Confirm against the current
/// AMC/GM before this becomes load-bearing, per CLAUDE.md's
/// regulatory-text caveat.
HeldRecord medicalCertificateHeldRecord(
  MedicalCertificate certificate,
  CalendarDate dateOfBirth,
) {
  return HeldRecord(
    kind: _heldRecordKind(certificate.certificateClass),
    validFrom: certificate.issueDate,
    validUntil: _validUntil(certificate, dateOfBirth),
  );
}

String _heldRecordKind(MedicalCertificateClass certificateClass) =>
    'medical_certificate.${certificateClass.name}';

CalendarDate _validUntil(
  MedicalCertificate certificate,
  CalendarDate dateOfBirth,
) {
  final ageAtIssue = _ageAt(dateOfBirth, certificate.issueDate);

  switch (certificate.certificateClass) {
    case MedicalCertificateClass.easaClass1:
      // Flat 12 months -- the single-pilot-commercial-passenger 6-month
      // reduction at 40+/60 is deferred; see the scope boundary above.
      return RuleWindow.calendarMonths(12).expiryFrom(certificate.issueDate);

    case MedicalCertificateClass.easaClass2:
      return _easaClass2ValidUntil(
        certificate.issueDate,
        dateOfBirth,
        ageAtIssue,
      );

    case MedicalCertificateClass.faaFirstClass:
    case MedicalCertificateClass.faaSecondClass:
    case MedicalCertificateClass.faaThirdClass:
      // §61.23(d), private/recreational/student/sport tier only -- no
      // birthday clawback, unlike EASA: the full nominal duration stands
      // even if the holder ages into the next band before it lapses.
      final months = ageAtIssue < 40 ? 60 : 24;
      return RuleWindow.calendarMonths(
        months,
      ).expiryFrom(certificate.issueDate);
  }
}

/// MED.A.045: 60/24/12 months by age band at issue, each of the first two
/// bands additionally capped at a fixed birthday -- "a certificate can
/// shorten its own validity partway through its life" (#51). A certificate
/// issued at 39 does not get the full 60 months; it is clawed back to the
/// 42nd birthday. Whichever of the nominal duration and the cap is
/// *earlier* governs.
CalendarDate _easaClass2ValidUntil(
  CalendarDate issueDate,
  CalendarDate dateOfBirth,
  int ageAtIssue,
) {
  final (months, capAge) = switch (ageAtIssue) {
    < 40 => (60, 42),
    < 50 => (24, 51),
    _ => (12, null),
  };

  final nominal = RuleWindow.calendarMonths(months).expiryFrom(issueDate);
  if (capAge == null) {
    return nominal;
  }
  final cap = _nthBirthday(dateOfBirth, capAge);
  return nominal < cap ? nominal : cap;
}

int _ageAt(CalendarDate dateOfBirth, CalendarDate date) {
  var age = date.year - dateOfBirth.year;
  final hadBirthdayYet =
      date.month > dateOfBirth.month ||
      (date.month == dateOfBirth.month && date.day >= dateOfBirth.day);
  if (!hadBirthdayYet) {
    age -= 1;
  }
  return age;
}

/// [dateOfBirth]'s [n]th anniversary, clamped to the last real day of the
/// month for a 29 February birthday landing on a non-leap year.
CalendarDate _nthBirthday(CalendarDate dateOfBirth, int n) {
  final year = dateOfBirth.year + n;
  final isLeapFeb29 = dateOfBirth.month == 2 && dateOfBirth.day == 29;
  final isLeapYear = (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;
  final day = (isLeapFeb29 && !isLeapYear) ? 28 : dateOfBirth.day;
  return CalendarDate(year, dateOfBirth.month, day);
}
