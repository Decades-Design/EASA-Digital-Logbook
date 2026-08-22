import '../../domain/model/calendar_date.dart';
import '../../domain/pilot_record/medical_certificate.dart' as domain;
import '../../domain/pilot_record/pilot_profile.dart' as domain;
import '../database.dart';

PilotProfileRow pilotProfileToRow(
  domain.PilotProfile profile, {
  required String id,
}) {
  return PilotProfileRow(
    id: id,
    dateOfBirth: profile.dateOfBirth.toString(),
    primaryJurisdictionId: profile.primaryJurisdictionId,
    homeBaseIcao: profile.homeBaseIcao,
  );
}

domain.PilotProfile pilotProfileFromRow(PilotProfileRow row) {
  return domain.PilotProfile(
    dateOfBirth: CalendarDate.parse(row.dateOfBirth),
    primaryJurisdictionId: row.primaryJurisdictionId,
    homeBaseIcao: row.homeBaseIcao,
  );
}

MedicalCertificateRow medicalCertificateToRow(
  domain.MedicalCertificate certificate, {
  required String id,
}) {
  return MedicalCertificateRow(
    id: id,
    certificateClass: certificate.certificateClass.name,
    jurisdictionId: certificate.jurisdictionId,
    issueDate: certificate.issueDate.toString(),
  );
}

domain.MedicalCertificate medicalCertificateFromRow(MedicalCertificateRow row) {
  return domain.MedicalCertificate(
    certificateClass: domain.MedicalCertificateClass.values.byName(
      row.certificateClass,
    ),
    jurisdictionId: row.jurisdictionId,
    issueDate: CalendarDate.parse(row.issueDate),
  );
}
