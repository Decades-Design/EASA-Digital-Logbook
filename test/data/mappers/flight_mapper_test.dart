import 'package:easa_digital_log/data/mappers/flight_mapper.dart';
import 'package:easa_digital_log/domain/model/calendar_date.dart';
import 'package:easa_digital_log/domain/model/countersignature.dart';
import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/instructor_presence.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:flutter_test/flutter_test.dart';

Flight _sampleFlight() {
  return Flight(
    aircraftRegistration: 'G-ABCD',
    route: const ['EGKA', 'EGKB'],
    prePlannedNavigation: true,
    offBlocks: UtcInstant.utc(2026, 6, 1, 10, 0),
    onBlocks: UtcInstant.utc(2026, 6, 1, 11, 30),
    takeoff: UtcInstant.utc(2026, 6, 1, 10, 5),
    landing: UtcInstant.utc(2026, 6, 1, 11, 25),
    capacity: const PilotCapacity(
      commandAuthority: true,
      soleManipulator: true,
      soleOccupant: true,
      multiPilotOperation: false,
      additionalCrewRequiredByRule: false,
      actingAsInstructor: false,
      actingAsExaminer: false,
      picusClaimed: false,
      picInterventionNotRequired: false,
    ),
    carryingPassengers: false,
    takeoffs: const CircuitCounts(dayFullStop: 1),
    landings: const CircuitCounts(dayFullStop: 1),
    ifrFlightPlanFiled: false,
    actualInstrumentTime: FlightDuration.zero,
    simulatedInstrumentTime: FlightDuration.zero,
    approaches: const [
      Approach(
        type: ApproachType.ils,
        aerodromeIcao: 'EGKB',
        runway: '20',
        count: 2,
      ),
    ],
    holdingProceduresCount: 0,
    trackingPerformed: false,
    remarks: '',
  );
}

void main() {
  group('flightToRow', () {
    test('flattens capacity, times and counts onto the row', () {
      final row = flightToRow(_sampleFlight(), id: 'f1', aircraftId: 'a1');

      expect(row.id, 'f1');
      expect(row.aircraftId, 'a1');
      expect(
        row.offBlocks,
        UtcInstant.utc(2026, 6, 1, 10, 0).millisecondsSinceEpoch,
      );
      expect(row.takeoffsDayFullStop, 1);
      expect(row.capacityCommandAuthority, isTrue);
      expect(row.capacityInstructorCapacity, isNull);
      expect(row.committedAt, isNull);
      expect(row.tombstonedAt, isNull);
    });

    test('carries committedAt/tombstonedAt through when supplied', () {
      final row = flightToRow(
        _sampleFlight(),
        id: 'f1',
        aircraftId: 'a1',
        committedAt: 1000,
        tombstonedAt: 2000,
      );

      expect(row.committedAt, 1000);
      expect(row.tombstonedAt, 2000);
    });
  });

  group('flightRouteLegRows', () {
    test('one row per route entry, in order', () {
      final rows = flightRouteLegRows('f1', _sampleFlight());

      expect(rows, hasLength(2));
      expect(rows[0].sequence, 0);
      expect(rows[0].identifier, 'EGKA');
      expect(rows[1].sequence, 1);
      expect(rows[1].identifier, 'EGKB');
      expect(rows.every((r) => r.flightId == 'f1'), isTrue);
    });
  });

  group('flightApproachRows', () {
    test('one row per approach', () {
      final rows = flightApproachRows('f1', _sampleFlight());

      expect(rows, hasLength(1));
      expect(rows.single.type, 'ils');
      expect(rows.single.count, 2);
    });
  });

  group('flightFromRow round trip', () {
    test('reconstructs every field flightToRow set, including nested capacity '
        'structures', () {
      final original = Flight(
        aircraftRegistration: 'G-ABCD',
        route: const ['EGKA', 'EGKB', 'EGHI'],
        prePlannedNavigation: true,
        offBlocks: UtcInstant.utc(2026, 6, 1, 10, 0),
        onBlocks: UtcInstant.utc(2026, 6, 1, 12, 30),
        takeoff: UtcInstant.utc(2026, 6, 1, 10, 5),
        landing: UtcInstant.utc(2026, 6, 1, 12, 25),
        capacity: PilotCapacity(
          commandAuthority: true,
          soleManipulator: false,
          soleOccupant: false,
          multiPilotOperation: false,
          additionalCrewRequiredByRule: false,
          actingAsInstructor: false,
          actingAsExaminer: false,
          picusClaimed: true,
          picInterventionNotRequired: true,
          manipulationTime: FlightDuration.parseHoursMinutes('0:45'),
          soloEndorsementHeld: true,
          endorsingInstructorName: 'A. Trainer',
          instructor: InstructorPresence(
            capacity: InstructorCapacity.flightInstructor,
            influencedFlight: true,
            name: 'B. Coach',
            credentialNumber: 'GBR.FI.1234',
            credentialExpiry: const CalendarDate(2027, 5, 31),
          ),
          otherPilotRole: OtherPilotRole.requiredCrew,
          countersignature: Countersignature(
            status: CountersignatureStatus.signed,
            signatoryName: 'B. Coach',
            signatoryCredentialNumber: 'GBR.FI.1234',
            signatoryCredentialExpiry: const CalendarDate(2027, 5, 31),
            signedAt: UtcInstant.utc(2026, 6, 2),
          ),
        ),
        otherPilotName: 'C. Pilot',
        otherPilotCredentialNumber: 'GBR.PPL.5678',
        carryingPassengers: true,
        takeoffs: const CircuitCounts(dayFullStop: 2, dayTouchAndGo: 1),
        landings: const CircuitCounts(dayFullStop: 2, dayTouchAndGo: 1),
        ifrFlightPlanFiled: true,
        actualInstrumentTime: FlightDuration.parseHoursMinutes('0:20'),
        simulatedInstrumentTime: FlightDuration.parseHoursMinutes('0:10'),
        approaches: const [
          Approach(
            type: ApproachType.ils,
            aerodromeIcao: 'EGHI',
            runway: '20',
            count: 1,
          ),
        ],
        holdingProceduresCount: 1,
        trackingPerformed: true,
        seriesGroupId: 'series-1',
        airworthinessBasis: AirworthinessBasis.usRegistryStandardOrSpecial,
        remarks: 'Nav ex',
      );

      final row = flightToRow(original, id: 'f1', aircraftId: 'a1');
      final legs = flightRouteLegRows('f1', original);
      final approachRows = flightApproachRows('f1', original);

      final reconstructed = flightFromRow(
        row,
        legs,
        approachRows,
        aircraftRegistration: original.aircraftRegistration,
      );

      expect(reconstructed, original);
    });

    test('reconstructs a minimal flight with every optional field null', () {
      final original = Flight(
        aircraftRegistration: 'G-ABCD',
        route: const [],
        prePlannedNavigation: false,
        offBlocks: UtcInstant.utc(2026, 6, 1, 10),
        onBlocks: UtcInstant.utc(2026, 6, 1, 11),
        capacity: const PilotCapacity(
          commandAuthority: true,
          soleManipulator: true,
          soleOccupant: true,
          multiPilotOperation: false,
          additionalCrewRequiredByRule: false,
          actingAsInstructor: false,
          actingAsExaminer: false,
          picusClaimed: false,
          picInterventionNotRequired: false,
        ),
        carryingPassengers: false,
        takeoffs: const CircuitCounts(dayFullStop: 1),
        landings: const CircuitCounts(dayFullStop: 1),
        ifrFlightPlanFiled: false,
        actualInstrumentTime: FlightDuration.zero,
        simulatedInstrumentTime: FlightDuration.zero,
        approaches: const [],
        holdingProceduresCount: 0,
        trackingPerformed: false,
        remarks: '',
      );

      final row = flightToRow(original, id: 'f2', aircraftId: 'a1');
      final reconstructed = flightFromRow(
        row,
        const [],
        const [],
        aircraftRegistration: original.aircraftRegistration,
      );

      expect(reconstructed, original);
    });
  });
}
