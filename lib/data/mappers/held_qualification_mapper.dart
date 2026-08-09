import '../../domain/model/aircraft.dart';
import '../../domain/model/calendar_date.dart';
import '../../domain/pilot_record/held_aircraft_qualification.dart' as domain;
import '../../domain/pilot_record/held_rating.dart' as domain;
import '../database.dart';

HeldAircraftQualificationRow heldAircraftQualificationToRow(
  domain.HeldAircraftQualification held, {
  required String id,
}) {
  return HeldAircraftQualificationRow(
    id: id,
    qualification: held.qualification.name,
    jurisdictionId: held.jurisdictionId,
    dateGranted: held.dateGranted.toString(),
    signatoryName: held.signatoryName,
    signatoryCredentialNumber: held.signatoryCredentialNumber,
  );
}

domain.HeldAircraftQualification heldAircraftQualificationFromRow(
  HeldAircraftQualificationRow row,
) {
  return domain.HeldAircraftQualification(
    qualification: AircraftQualification.values.byName(row.qualification),
    jurisdictionId: row.jurisdictionId,
    dateGranted: CalendarDate.parse(row.dateGranted),
    signatoryName: row.signatoryName,
    signatoryCredentialNumber: row.signatoryCredentialNumber,
  );
}

HeldRatingRow heldRatingToRow(domain.HeldRating held, {required String id}) {
  return HeldRatingRow(
    id: id,
    kind: held.kind.name,
    designator: held.designator,
    jurisdictionId: held.jurisdictionId,
    issueDate: held.issueDate.toString(),
    expiryDate: held.expiryDate?.toString(),
    languageProficiencyLevel: held.languageProficiencyLevel,
  );
}

domain.HeldRating heldRatingFromRow(HeldRatingRow row) {
  return domain.HeldRating(
    kind: domain.HeldRatingKind.values.byName(row.kind),
    designator: row.designator,
    jurisdictionId: row.jurisdictionId,
    issueDate: CalendarDate.parse(row.issueDate),
    expiryDate: row.expiryDate == null
        ? null
        : CalendarDate.parse(row.expiryDate!),
    languageProficiencyLevel: row.languageProficiencyLevel,
  );
}
