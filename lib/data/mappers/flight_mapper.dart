import '../../domain/model/calendar_date.dart';
import '../../domain/model/countersignature.dart' as domain;
import '../../domain/model/flight.dart' as domain;
import '../../domain/model/flight_duration.dart';
import '../../domain/model/instructor_presence.dart' as domain;
import '../../domain/model/pilot_capacity.dart' as domain;
import '../../domain/model/utc_instant.dart';
import '../database.dart';
import '../ulid.dart';

int _epoch(UtcInstant instant) => instant.millisecondsSinceEpoch;

FlightRow flightToRow(
  domain.Flight flight, {
  required String id,
  required String aircraftId,
  int? committedAt,
  int? tombstonedAt,
}) {
  final capacity = flight.capacity;
  final instructor = capacity.instructor;
  final countersignature = capacity.countersignature;

  return FlightRow(
    id: id,
    aircraftId: aircraftId,
    prePlannedNavigation: flight.prePlannedNavigation,
    offBlocks: _epoch(flight.offBlocks),
    onBlocks: _epoch(flight.onBlocks),
    takeoff: flight.takeoff == null ? null : _epoch(flight.takeoff!),
    landing: flight.landing == null ? null : _epoch(flight.landing!),
    otherPilotName: flight.otherPilotName,
    otherPilotCredentialNumber: flight.otherPilotCredentialNumber,
    carryingPassengers: flight.carryingPassengers,
    takeoffsDayFullStop: flight.takeoffs.dayFullStop,
    takeoffsDayTouchAndGo: flight.takeoffs.dayTouchAndGo,
    takeoffsNightFullStop: flight.takeoffs.nightFullStop,
    takeoffsNightTouchAndGo: flight.takeoffs.nightTouchAndGo,
    landingsDayFullStop: flight.landings.dayFullStop,
    landingsDayTouchAndGo: flight.landings.dayTouchAndGo,
    landingsNightFullStop: flight.landings.nightFullStop,
    landingsNightTouchAndGo: flight.landings.nightTouchAndGo,
    ifrFlightPlanFiled: flight.ifrFlightPlanFiled,
    actualInstrumentMinutes: flight.actualInstrumentTime.inMinutes,
    simulatedInstrumentMinutes: flight.simulatedInstrumentTime.inMinutes,
    holdingProceduresCount: flight.holdingProceduresCount,
    trackingPerformed: flight.trackingPerformed,
    seriesGroupId: flight.seriesGroupId,
    airworthinessBasis: flight.airworthinessBasis?.name,
    remarks: flight.remarks,
    capacityCommandAuthority: capacity.commandAuthority,
    capacitySoleManipulator: capacity.soleManipulator,
    capacitySoleOccupant: capacity.soleOccupant,
    capacityMultiPilotOperation: capacity.multiPilotOperation,
    capacityAdditionalCrewRequiredByRule: capacity.additionalCrewRequiredByRule,
    capacityActingAsInstructor: capacity.actingAsInstructor,
    capacityActingAsExaminer: capacity.actingAsExaminer,
    capacityPicusClaimed: capacity.picusClaimed,
    capacityPicInterventionNotRequired: capacity.picInterventionNotRequired,
    capacityManipulationTimeMinutes: capacity.manipulationTime?.inMinutes,
    capacitySoloEndorsementHeld: capacity.soloEndorsementHeld,
    capacityEndorsingInstructorName: capacity.endorsingInstructorName,
    capacityInstructorCapacity: instructor?.capacity.name,
    capacityInstructorInfluencedFlight: instructor?.influencedFlight,
    capacityInstructorName: instructor?.name,
    capacityInstructorCredentialNumber: instructor?.credentialNumber,
    capacityInstructorCredentialExpiry: instructor?.credentialExpiry
        ?.toString(),
    capacityOtherPilotRole: capacity.otherPilotRole?.name,
    capacityCountersignatureStatus: countersignature?.status.name,
    capacityCountersignatureSignatoryName: countersignature?.signatoryName,
    capacityCountersignatureSignatoryCredentialNumber:
        countersignature?.signatoryCredentialNumber,
    capacityCountersignatureSignatoryCredentialExpiry: countersignature
        ?.signatoryCredentialExpiry
        ?.toString(),
    capacityCountersignatureSignedAt: countersignature?.signedAt == null
        ? null
        : _epoch(countersignature!.signedAt!),
    committedAt: committedAt,
    tombstonedAt: tombstonedAt,
  );
}

List<FlightRouteLegRow> flightRouteLegRows(
  String flightId,
  domain.Flight flight,
) {
  return [
    for (var i = 0; i < flight.route.length; i++)
      FlightRouteLegRow(
        id: generateUlid(),
        flightId: flightId,
        sequence: i,
        identifier: flight.route[i],
      ),
  ];
}

List<FlightApproachRow> flightApproachRows(
  String flightId,
  domain.Flight flight,
) {
  return [
    for (final approach in flight.approaches)
      FlightApproachRow(
        id: generateUlid(),
        flightId: flightId,
        type: approach.type.name,
        aerodromeIcao: approach.aerodromeIcao,
        runway: approach.runway,
        count: approach.count,
      ),
  ];
}

domain.Flight flightFromRow(
  FlightRow row,
  List<FlightRouteLegRow> legs,
  List<FlightApproachRow> approaches, {
  required String aircraftRegistration,
}) {
  domain.InstructorPresence? instructor;
  if (row.capacityInstructorCapacity != null) {
    instructor = domain.InstructorPresence(
      capacity: domain.InstructorCapacity.values.byName(
        row.capacityInstructorCapacity!,
      ),
      influencedFlight: row.capacityInstructorInfluencedFlight!,
      name: row.capacityInstructorName,
      credentialNumber: row.capacityInstructorCredentialNumber,
      credentialExpiry: row.capacityInstructorCredentialExpiry == null
          ? null
          : CalendarDate.parse(row.capacityInstructorCredentialExpiry!),
    );
  }

  domain.Countersignature? countersignature;
  if (row.capacityCountersignatureStatus != null) {
    countersignature = domain.Countersignature(
      status: domain.CountersignatureStatus.values.byName(
        row.capacityCountersignatureStatus!,
      ),
      signatoryName: row.capacityCountersignatureSignatoryName,
      signatoryCredentialNumber:
          row.capacityCountersignatureSignatoryCredentialNumber,
      signatoryCredentialExpiry:
          row.capacityCountersignatureSignatoryCredentialExpiry == null
          ? null
          : CalendarDate.parse(
              row.capacityCountersignatureSignatoryCredentialExpiry!,
            ),
      signedAt: row.capacityCountersignatureSignedAt == null
          ? null
          : _fromEpoch(row.capacityCountersignatureSignedAt!),
    );
  }

  final capacity = domain.PilotCapacity(
    commandAuthority: row.capacityCommandAuthority,
    soleManipulator: row.capacitySoleManipulator,
    soleOccupant: row.capacitySoleOccupant,
    multiPilotOperation: row.capacityMultiPilotOperation,
    additionalCrewRequiredByRule: row.capacityAdditionalCrewRequiredByRule,
    actingAsInstructor: row.capacityActingAsInstructor,
    actingAsExaminer: row.capacityActingAsExaminer,
    picusClaimed: row.capacityPicusClaimed,
    picInterventionNotRequired: row.capacityPicInterventionNotRequired,
    manipulationTime: row.capacityManipulationTimeMinutes == null
        ? null
        : FlightDuration(row.capacityManipulationTimeMinutes!),
    soloEndorsementHeld: row.capacitySoloEndorsementHeld,
    endorsingInstructorName: row.capacityEndorsingInstructorName,
    instructor: instructor,
    otherPilotRole: row.capacityOtherPilotRole == null
        ? null
        : domain.OtherPilotRole.values.byName(row.capacityOtherPilotRole!),
    countersignature: countersignature,
  );

  final sortedLegs = [...legs]
    ..sort((a, b) => a.sequence.compareTo(b.sequence));

  return domain.Flight(
    aircraftRegistration: aircraftRegistration,
    route: [for (final leg in sortedLegs) leg.identifier],
    prePlannedNavigation: row.prePlannedNavigation,
    offBlocks: _fromEpoch(row.offBlocks),
    onBlocks: _fromEpoch(row.onBlocks),
    takeoff: row.takeoff == null ? null : _fromEpoch(row.takeoff!),
    landing: row.landing == null ? null : _fromEpoch(row.landing!),
    capacity: capacity,
    otherPilotName: row.otherPilotName,
    otherPilotCredentialNumber: row.otherPilotCredentialNumber,
    carryingPassengers: row.carryingPassengers,
    takeoffs: domain.CircuitCounts(
      dayFullStop: row.takeoffsDayFullStop,
      dayTouchAndGo: row.takeoffsDayTouchAndGo,
      nightFullStop: row.takeoffsNightFullStop,
      nightTouchAndGo: row.takeoffsNightTouchAndGo,
    ),
    landings: domain.CircuitCounts(
      dayFullStop: row.landingsDayFullStop,
      dayTouchAndGo: row.landingsDayTouchAndGo,
      nightFullStop: row.landingsNightFullStop,
      nightTouchAndGo: row.landingsNightTouchAndGo,
    ),
    ifrFlightPlanFiled: row.ifrFlightPlanFiled,
    actualInstrumentTime: FlightDuration(row.actualInstrumentMinutes),
    simulatedInstrumentTime: FlightDuration(row.simulatedInstrumentMinutes),
    approaches: [
      for (final approach in approaches)
        domain.Approach(
          type: domain.ApproachType.values.byName(approach.type),
          aerodromeIcao: approach.aerodromeIcao,
          runway: approach.runway,
          count: approach.count,
        ),
    ],
    holdingProceduresCount: row.holdingProceduresCount,
    trackingPerformed: row.trackingPerformed,
    seriesGroupId: row.seriesGroupId,
    airworthinessBasis: row.airworthinessBasis == null
        ? null
        : domain.AirworthinessBasis.values.byName(row.airworthinessBasis!),
    remarks: row.remarks,
  );
}

UtcInstant _fromEpoch(int ms) => UtcInstant.fromDateTime(
  DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true),
);
