import '../../domain/model/flight.dart' as domain;
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
