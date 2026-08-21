/// Builds a draft [Flight] from the entry form's raw UI state, so the
/// derivation strip (docs/entry-form.md §7) can run it through the real
/// [JurisdictionProjection]s instead of re-deriving PIC/dual/SPIC/PICUS
/// logic in the UI layer — CLAUDE.md's whole point about
/// `domain/projection/` existing in the first place.
///
/// This mapping only ever *reads* form state; it never writes it. Whether
/// the result is fit to persist (required fields present, block time
/// non-negative, ...) is a separate, later concern — #56 wires up an actual
/// save.
library;

import '../../domain/model/aircraft.dart';
import '../../domain/model/calendar_date.dart';
import '../../domain/model/countersignature.dart';
import '../../domain/model/flight.dart';
import '../../domain/model/flight_duration.dart';
import '../../domain/model/instructor_presence.dart';
import '../../domain/model/pilot_capacity.dart';
import '../../domain/model/utc_instant.dart';
import 'entry_form_types.dart';
import 'widgets/crew/crew_selection.dart' show CrewSelection;

/// Everything the mapper needs, gathered from `NewFlightScreen`'s state.
/// A plain data holder, not a form-state manager — the screen still owns
/// every field independently; this is just the snapshot passed to
/// [buildDraftFlight] on each rebuild.
class DraftFlightInputs {
  const DraftFlightInputs({
    required this.aircraft,
    required this.route,
    required this.offBlocks,
    required this.onBlocks,
    this.takeoff,
    this.landing,
    required this.crew,
    required this.isStudent,
    required this.soloEndorsementHeld,
    required this.endorsingInstructorName,
    required this.arrangement,
    required this.instructorName,
    required this.instructorLicence,
    this.instructorCredentialExpiry,
    required this.purpose,
    required this.instructorSoleManipulator,
    this.instructorManipulationTime,
    required this.instructorPassengers,
    required this.command,
    required this.flying,
    required this.otherPilotName,
    required this.otherPilotLicence,
    required this.multiPilotOperation,
    this.otherPilotRole,
    required this.picusClaimed,
    required this.picInterventionNotRequired,
    this.otherManipulationTime,
    required this.otherPilotPassengers,
    required this.sign,
    this.signedAt,
    required this.ifrFlightPlanFiled,
    required this.actualInstrumentTime,
    required this.simulatedInstrumentTime,
    required this.approaches,
    required this.holdingProceduresCount,
    required this.trackingPerformed,
    required this.takeoffs,
    required this.landings,
    required this.remarks,
  });

  final Aircraft aircraft;
  final List<String> route;
  final UtcInstant offBlocks;
  final UtcInstant onBlocks;
  final UtcInstant? takeoff;
  final UtcInstant? landing;

  final CrewSelection crew;
  final bool isStudent;
  final bool soloEndorsementHeld;
  final String endorsingInstructorName;

  final InstructorArrangement arrangement;
  final String instructorName;
  final String instructorLicence;
  final CalendarDateInput? instructorCredentialExpiry;
  final String? purpose;
  final bool instructorSoleManipulator;
  final FlightDuration? instructorManipulationTime;
  final bool instructorPassengers;

  final CommandChoice command;
  final FlyingChoice flying;
  final String otherPilotName;
  final String otherPilotLicence;
  final bool multiPilotOperation;
  final OtherPilotRole? otherPilotRole;
  final bool picusClaimed;
  final bool picInterventionNotRequired;
  final FlightDuration? otherManipulationTime;
  final bool otherPilotPassengers;

  final SignChoice sign;
  final UtcInstant? signedAt;

  final bool ifrFlightPlanFiled;
  final FlightDuration actualInstrumentTime;
  final FlightDuration simulatedInstrumentTime;
  final List<Approach> approaches;
  final int holdingProceduresCount;
  final bool trackingPerformed;

  final CircuitCounts takeoffs;
  final CircuitCounts landings;

  final String remarks;
}

/// A calendar-date-shaped input the UI collects as a plain `DateTime` (from
/// `showDatePicker`) — kept separate from [CalendarDate] itself so this file
/// doesn't need to import `flutter/material.dart`.
typedef CalendarDateInput = (int year, int month, int day);

/// Builds the [PilotCapacity] + [Flight] the entry form's answers describe so
/// far. Returns `null` when there isn't enough to project yet — the
/// derivation strip then falls back to showing block time alone, exactly as
/// it did before any crew answer was given.
Flight? buildDraftFlight(DraftFlightInputs input) {
  final capacity = _buildCapacity(input);
  if (capacity == null) return null;

  return Flight(
    aircraftRegistration: input.aircraft.registration,
    route: input.route,
    // No UI for this yet — docs/entry-form.md §4 note: unbackfillable if
    // omitted, but nothing downstream (this screen's derivation strip) reads
    // cross-country time, so leaving it false here doesn't silently corrupt
    // anything a pilot would see today.
    prePlannedNavigation: false,
    offBlocks: input.offBlocks,
    onBlocks: input.onBlocks,
    takeoff: input.takeoff,
    landing: input.landing,
    capacity: capacity,
    otherPilotName: input.otherPilotName.isEmpty ? null : input.otherPilotName,
    otherPilotCredentialNumber: input.otherPilotLicence.isEmpty
        ? null
        : input.otherPilotLicence,
    carryingPassengers: switch (input.crew) {
      CrewSelection.justMe => false,
      CrewSelection.withInstructor => input.instructorPassengers,
      CrewSelection.withOtherPilot => input.otherPilotPassengers,
      CrewSelection.withPassengers => true,
    },
    takeoffs: input.takeoffs,
    landings: input.landings,
    ifrFlightPlanFiled: input.ifrFlightPlanFiled,
    actualInstrumentTime: input.actualInstrumentTime,
    simulatedInstrumentTime: input.simulatedInstrumentTime,
    approaches: input.approaches,
    holdingProceduresCount: input.holdingProceduresCount,
    trackingPerformed: input.trackingPerformed,
    remarks: input.remarks,
  );
}

PilotCapacity? _buildCapacity(DraftFlightInputs input) {
  switch (input.crew) {
    case CrewSelection.justMe:
      return PilotCapacity(
        commandAuthority: true,
        soleManipulator: true,
        soleOccupant: true,
        multiPilotOperation: false,
        additionalCrewRequiredByRule: false,
        actingAsInstructor: false,
        actingAsExaminer: false,
        picusClaimed: false,
        picInterventionNotRequired: false,
        soloEndorsementHeld: input.isStudent ? input.soloEndorsementHeld : null,
        endorsingInstructorName: input.isStudent
            ? _orNull(input.endorsingInstructorName)
            : null,
      );

    case CrewSelection.withInstructor:
      final receiving =
          input.arrangement == InstructorArrangement.receivingInstruction;
      final instructor = InstructorPresence(
        capacity: purposeHasExaminer(input.purpose)
            ? InstructorCapacity.flightExaminer
            : InstructorCapacity.flightInstructor,
        influencedFlight: receiving,
        name: _orNull(input.instructorName),
        credentialNumber: _orNull(input.instructorLicence),
        credentialExpiry: _calendarDate(input.instructorCredentialExpiry),
      );
      return PilotCapacity(
        commandAuthority: !receiving,
        soleManipulator: receiving ? input.instructorSoleManipulator : true,
        soleOccupant: false,
        multiPilotOperation: input.aircraft.requiresMultiCrew,
        additionalCrewRequiredByRule: false,
        actingAsInstructor: false,
        actingAsExaminer: false,
        picusClaimed: false,
        picInterventionNotRequired: false,
        manipulationTime: receiving && !input.instructorSoleManipulator
            ? input.instructorManipulationTime
            : null,
        instructor: instructor,
        countersignature: _countersignature(
          input.sign,
          input.signedAt,
          signatoryName: input.instructorName,
          signatoryCredentialNumber: input.instructorLicence,
        ),
      );

    case CrewSelection.withOtherPilot:
      final commandMe = input.command == CommandChoice.me;
      final flyingMe = input.flying == FlyingChoice.me;
      final canClaimPicus =
          (input.multiPilotOperation || input.aircraft.requiresMultiCrew) &&
          !commandMe;
      final picus = canClaimPicus && input.picusClaimed;
      return PilotCapacity(
        commandAuthority: commandMe,
        soleManipulator: flyingMe,
        soleOccupant: false,
        multiPilotOperation:
            input.multiPilotOperation || input.aircraft.requiresMultiCrew,
        additionalCrewRequiredByRule: false,
        actingAsInstructor: false,
        actingAsExaminer: false,
        picusClaimed: picus,
        picInterventionNotRequired: picus && input.picInterventionNotRequired,
        manipulationTime: input.flying == FlyingChoice.bothSplit
            ? input.otherManipulationTime
            : null,
        otherPilotRole: input.otherPilotRole,
        countersignature: picus
            ? _countersignature(
                input.sign,
                input.signedAt,
                signatoryName: input.otherPilotName,
                signatoryCredentialNumber: input.otherPilotLicence,
              )
            : null,
      );

    case CrewSelection.withPassengers:
      return const PilotCapacity(
        commandAuthority: true,
        soleManipulator: true,
        soleOccupant: false,
        multiPilotOperation: false,
        additionalCrewRequiredByRule: false,
        actingAsInstructor: false,
        actingAsExaminer: false,
        picusClaimed: false,
        picInterventionNotRequired: false,
      );
  }
}

Countersignature _countersignature(
  SignChoice sign,
  UtcInstant? signedAt, {
  required String signatoryName,
  required String signatoryCredentialNumber,
}) {
  return Countersignature(
    status: sign == SignChoice.now
        ? CountersignatureStatus.signed
        : CountersignatureStatus.pending,
    signatoryName: _orNull(signatoryName),
    signatoryCredentialNumber: _orNull(signatoryCredentialNumber),
    signedAt: sign == SignChoice.now ? signedAt : null,
  );
}

String? _orNull(String value) => value.isEmpty ? null : value;

CalendarDate? _calendarDate(CalendarDateInput? input) {
  if (input == null) return null;
  return CalendarDate(input.$1, input.$2, input.$3);
}
