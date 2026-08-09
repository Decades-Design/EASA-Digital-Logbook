import 'dart:convert';

import 'package:easa_digital_log/data/database.dart';
import 'package:easa_digital_log/data/flight_history.dart';
import 'package:flutter_test/flutter_test.dart';

FlightRow _row({String remarks = 'current', int? tombstonedAt}) {
  return FlightRow(
    id: 'f1',
    aircraftId: 'a1',
    prePlannedNavigation: false,
    offBlocks: 1000,
    onBlocks: 2000,
    takeoff: null,
    landing: null,
    otherPilotName: null,
    otherPilotCredentialNumber: null,
    carryingPassengers: false,
    takeoffsDayFullStop: 1,
    takeoffsDayTouchAndGo: 0,
    takeoffsNightFullStop: 0,
    takeoffsNightTouchAndGo: 0,
    landingsDayFullStop: 1,
    landingsDayTouchAndGo: 0,
    landingsNightFullStop: 0,
    landingsNightTouchAndGo: 0,
    ifrFlightPlanFiled: false,
    actualInstrumentMinutes: 0,
    simulatedInstrumentMinutes: 0,
    holdingProceduresCount: 0,
    trackingPerformed: false,
    seriesGroupId: null,
    airworthinessBasis: null,
    remarks: remarks,
    capacityCommandAuthority: true,
    capacitySoleManipulator: true,
    capacitySoleOccupant: true,
    capacityMultiPilotOperation: false,
    capacityAdditionalCrewRequiredByRule: false,
    capacityActingAsInstructor: false,
    capacityActingAsExaminer: false,
    capacityPicusClaimed: false,
    capacityPicInterventionNotRequired: false,
    capacityManipulationTimeMinutes: null,
    capacitySoloEndorsementHeld: null,
    capacityEndorsingInstructorName: null,
    capacityInstructorCapacity: null,
    capacityInstructorInfluencedFlight: null,
    capacityInstructorName: null,
    capacityInstructorCredentialNumber: null,
    capacityInstructorCredentialExpiry: null,
    capacityOtherPilotRole: null,
    capacityCountersignatureStatus: null,
    capacityCountersignatureSignatoryName: null,
    capacityCountersignatureSignatoryCredentialNumber: null,
    capacityCountersignatureSignatoryCredentialExpiry: null,
    capacityCountersignatureSignedAt: null,
    committedAt: 500,
    tombstonedAt: tombstonedAt,
  );
}

FlightRevisionRow _revision(
  int recordedAt,
  String kind,
  Map<String, Object?> changed,
) {
  return FlightRevisionRow(
    id: 'r-$recordedAt',
    flightId: 'f1',
    recordedAt: recordedAt,
    kind: kind,
    reason: null,
    changedFields: jsonEncode(changed),
  );
}

void main() {
  test(
    'with no revisions newer than asOf, returns the current row unchanged',
    () {
      final result = reconstructRowAsOf(_row(remarks: 'current'), [], 5000);
      expect(result['remarks'], 'current');
    },
  );

  test('applies one revision newer than asOf, restoring its old value', () {
    final revisions = [
      _revision(3000, 'edit', {'remarks': 'original'}),
    ];
    final result = reconstructRowAsOf(
      _row(remarks: 'current'),
      revisions,
      2000,
    );
    expect(result['remarks'], 'original');
  });

  test(
    'chains two revisions in reverse order, each undoing on top of the last',
    () {
      // Row started as 'first', edited to 'second' at t=3000, edited to
      // 'current' at t=4000. Reconstructing at t=2500 must undo both edits.
      final revisions = [
        _revision(3000, 'edit', {'remarks': 'first'}),
        _revision(4000, 'edit', {'remarks': 'second'}),
      ];
      final result = reconstructRowAsOf(
        _row(remarks: 'current'),
        revisions,
        2500,
      );
      expect(result['remarks'], 'first');
    },
  );

  test('ignores revisions at or before asOf', () {
    final revisions = [
      _revision(1000, 'edit', {'remarks': 'too old to matter'}),
    ];
    final result = reconstructRowAsOf(
      _row(remarks: 'current'),
      revisions,
      2000,
    );
    expect(result['remarks'], 'current');
  });
}
