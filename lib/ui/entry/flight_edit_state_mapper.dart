/// The reverse of `flight_draft_mapper.dart`: given a stored [Flight], works
/// out what the entry wizard's own crew questions (`entry_form_types.dart`,
/// `CrewSelection`) must have been answered to produce it, so editing can
/// reopen the same wizard rather than a second, parallel form (#59).
///
/// **This is necessarily partial.** The wizard's crew model doesn't cover
/// every [PilotCapacity] shape the domain can represent — there is no
/// "I was the instructor/examiner" question, no "refused" countersignature
/// choice, and no way to enter an overnight flight (one calendar-date field
/// serves every time on the screen). [resolveEditFormState] returns
/// [EditFormUnsupported] rather than guessing for any of these, since a
/// wrong guess here would silently rewrite a stored raw fact the next time
/// the flight is saved — CLAUDE.md's "never guess a missing discriminator"
/// rule applies exactly as hard in reverse as it does going forward.
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
import 'widgets/crew/crew_selection.dart';

/// The wizard's own answers, reconstructed from a stored [Flight] — one
/// field per piece of state `NewFlightScreen` needs to prefill.
class EditFormState {
  const EditFormState({
    required this.date,
    required this.route,
    required this.offBlocks,
    required this.onBlocks,
    this.takeoff,
    this.landing,
    required this.crew,
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
    required this.takeoffsDay,
    required this.takeoffsNight,
    required this.landingsDay,
    required this.landingsNight,
    required this.remarks,
  });

  final CalendarDate date;
  final List<String> route;
  final DateTimeComponents offBlocks;
  final DateTimeComponents onBlocks;
  final DateTimeComponents? takeoff;
  final DateTimeComponents? landing;

  final CrewSelection crew;

  final InstructorArrangement arrangement;
  final String instructorName;
  final String instructorLicence;
  final CalendarDate? instructorCredentialExpiry;
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
  final DateTimeComponents? signedAt;

  final bool ifrFlightPlanFiled;
  final FlightDuration actualInstrumentTime;
  final FlightDuration simulatedInstrumentTime;
  final List<Approach> approaches;
  final int holdingProceduresCount;
  final bool trackingPerformed;

  final int takeoffsDay;
  final int takeoffsNight;
  final int landingsDay;
  final int landingsNight;

  final String remarks;
}

/// An hour/minute-of-day pair — all the wizard's `TimeOfDay` fields need,
/// kept free of `flutter/material.dart` so this file stays plain Dart.
typedef DateTimeComponents = (int hour, int minute);

/// Why [resolveEditFormState] declined to produce an [EditFormState] — shown
/// to the pilot verbatim rather than as a raw enum name.
enum EditUnsupportedReason {
  actingAsInstructorOrExaminer(
    "This flight is logged with you acting as the instructor or examiner — "
    'the edit form doesn\'t have a path for that crew arrangement yet.',
  ),
  countersignatureRefused(
    'This flight\'s countersignature was refused — the edit form can only '
    'represent pending or signed.',
  ),
  overnightSpanningTimes(
    'This flight\'s recorded times cross midnight — the edit form only '
    'supports a single calendar date.',
  ),
  unrecognisedCapacityShape(
    "This flight's crew arrangement doesn't match any of the edit form's "
    "questions.",
  );

  const EditUnsupportedReason(this.message);

  /// A complete sentence, ready to show in a dialog or snackbar.
  final String message;
}

sealed class EditFormResolution {}

class EditFormSupported extends EditFormResolution {
  EditFormSupported(this.state);
  final EditFormState state;
}

class EditFormUnsupported extends EditFormResolution {
  EditFormUnsupported(this.reason);
  final EditUnsupportedReason reason;
}

/// Fields the wizard has no question for at all, carried forward untouched
/// from [original] onto whatever the wizard's own forward mapper
/// (`buildDraftFlight`) produces when a committed or draft entry is
/// re-saved — never silently defaulted away. See this file's own dartdoc.
Flight preserveWizardBlindSpots(Flight mapped, Flight original) {
  return mapped.copyWith(
    prePlannedNavigation: original.prePlannedNavigation,
    seriesGroupId: original.seriesGroupId,
    alternativeComplianceEvents: original.alternativeComplianceEvents,
    airworthinessBasis: original.airworthinessBasis,
    capacity: mapped.capacity.copyWith(
      soloEndorsementHeld: original.capacity.soloEndorsementHeld,
      endorsingInstructorName: original.capacity.endorsingInstructorName,
    ),
  );
}

EditFormResolution resolveEditFormState(Flight flight, Aircraft aircraft) {
  final capacity = flight.capacity;

  if (capacity.actingAsInstructor || capacity.actingAsExaminer) {
    return EditFormUnsupported(
      EditUnsupportedReason.actingAsInstructorOrExaminer,
    );
  }
  if (capacity.countersignature?.status == CountersignatureStatus.refused) {
    return EditFormUnsupported(EditUnsupportedReason.countersignatureRefused);
  }

  final offDate = CalendarDate.fromUtcInstant(flight.offBlocks);
  for (final instant in [
    flight.onBlocks,
    if (flight.takeoff != null) flight.takeoff!,
    if (flight.landing != null) flight.landing!,
  ]) {
    if (CalendarDate.fromUtcInstant(instant) != offDate) {
      return EditFormUnsupported(EditUnsupportedReason.overnightSpanningTimes);
    }
  }

  final resolution = _resolveCrew(flight, capacity);
  if (resolution == null) {
    return EditFormUnsupported(EditUnsupportedReason.unrecognisedCapacityShape);
  }

  final (
    crew,
    arrangement,
    command,
    flying,
    multiPilotOperation,
    otherPilotRole,
    picusClaimed,
    picInterventionNotRequired,
    otherManipulationTime,
    otherPilotPassengers,
    instructorSoleManipulator,
    instructorManipulationTime,
    instructorPassengers,
    purpose,
  ) = resolution;

  return EditFormSupported(
    EditFormState(
      date: offDate,
      route: flight.route,
      offBlocks: _components(flight.offBlocks),
      onBlocks: _components(flight.onBlocks),
      takeoff: flight.takeoff == null ? null : _components(flight.takeoff!),
      landing: flight.landing == null ? null : _components(flight.landing!),
      crew: crew,
      arrangement: arrangement,
      instructorName: capacity.instructor?.name ?? '',
      instructorLicence: capacity.instructor?.credentialNumber ?? '',
      instructorCredentialExpiry: capacity.instructor?.credentialExpiry,
      purpose: purpose,
      instructorSoleManipulator: instructorSoleManipulator,
      instructorManipulationTime: instructorManipulationTime,
      instructorPassengers: instructorPassengers,
      command: command,
      flying: flying,
      otherPilotName: flight.otherPilotName ?? '',
      otherPilotLicence: flight.otherPilotCredentialNumber ?? '',
      multiPilotOperation: multiPilotOperation,
      otherPilotRole: otherPilotRole,
      picusClaimed: picusClaimed,
      picInterventionNotRequired: picInterventionNotRequired,
      otherManipulationTime: otherManipulationTime,
      otherPilotPassengers: otherPilotPassengers,
      sign: capacity.countersignature?.status == CountersignatureStatus.signed
          ? SignChoice.now
          : SignChoice.defer,
      signedAt: capacity.countersignature?.signedAt == null
          ? null
          : _components(capacity.countersignature!.signedAt!),
      ifrFlightPlanFiled: flight.ifrFlightPlanFiled,
      actualInstrumentTime: flight.actualInstrumentTime,
      simulatedInstrumentTime: flight.simulatedInstrumentTime,
      approaches: List.of(flight.approaches),
      holdingProceduresCount: flight.holdingProceduresCount,
      trackingPerformed: flight.trackingPerformed,
      takeoffsDay: flight.takeoffs.dayFullStop + flight.takeoffs.dayTouchAndGo,
      takeoffsNight:
          flight.takeoffs.nightFullStop + flight.takeoffs.nightTouchAndGo,
      landingsDay: flight.landings.dayFullStop + flight.landings.dayTouchAndGo,
      landingsNight:
          flight.landings.nightFullStop + flight.landings.nightTouchAndGo,
      remarks: flight.remarks,
    ),
  );
}

typedef _CrewResolution = (
  CrewSelection,
  InstructorArrangement,
  CommandChoice,
  FlyingChoice,
  bool, // multiPilotOperation
  OtherPilotRole?,
  bool, // picusClaimed
  bool, // picInterventionNotRequired
  FlightDuration?, // otherManipulationTime
  bool, // otherPilotPassengers
  bool, // instructorSoleManipulator
  FlightDuration?, // instructorManipulationTime
  bool, // instructorPassengers
  String?, // purpose
);

/// Works out which of the wizard's four [CrewSelection] branches produced
/// [capacity] — see this file's own dartdoc for the one genuine ambiguity
/// (a passenger-carrying flight and a "with another pilot, no role picked,
/// not counted as passengers" flight can collapse to near-identical stored
/// facts) and how it's resolved.
_CrewResolution? _resolveCrew(Flight flight, PilotCapacity capacity) {
  const defaultArrangement = InstructorArrangement.receivingInstruction;
  const defaultCommand = CommandChoice.me;
  const defaultFlying = FlyingChoice.me;

  if (capacity.instructor != null) {
    final instructor = capacity.instructor!;
    final receiving = instructor.influencedFlight;
    final purpose = instructor.capacity == InstructorCapacity.flightExaminer
        // The specific purpose (Skill test vs Proficiency check) isn't a
        // stored raw fact at all — `flight_draft_mapper.dart` never writes
        // it anywhere on `Flight`. Picking one is only about landing the
        // form on the right question group; nothing is lost that the
        // domain model ever actually held.
        ? 'Skill test'
        : null;
    return (
      CrewSelection.withInstructor,
      receiving
          ? InstructorArrangement.receivingInstruction
          : InstructorArrangement.inCommandObserving,
      defaultCommand,
      defaultFlying,
      false,
      null,
      false,
      false,
      null,
      false,
      receiving ? capacity.soleManipulator : true,
      receiving ? capacity.manipulationTime : null,
      flight.carryingPassengers,
      purpose,
    );
  }

  final looksLikeOtherPilot =
      capacity.otherPilotRole != null ||
      capacity.picusClaimed ||
      (flight.otherPilotName?.isNotEmpty ?? false) ||
      (!capacity.soleOccupant && !flight.carryingPassengers);
  if (looksLikeOtherPilot) {
    return (
      CrewSelection.withOtherPilot,
      defaultArrangement,
      capacity.commandAuthority ? CommandChoice.me : CommandChoice.otherPilot,
      capacity.manipulationTime != null
          ? FlyingChoice.bothSplit
          : (capacity.soleManipulator
                ? FlyingChoice.me
                : FlyingChoice.otherPilot),
      capacity.multiPilotOperation,
      capacity.otherPilotRole,
      capacity.picusClaimed,
      capacity.picInterventionNotRequired,
      capacity.manipulationTime,
      flight.carryingPassengers,
      true,
      null,
      false,
      null,
    );
  }

  if (capacity.multiPilotOperation) {
    // Reachable only via withInstructor/withOtherPilot in the forward
    // mapper -- if neither matched above, this shape didn't come from this
    // wizard at all.
    return null;
  }

  if (!capacity.soleOccupant) {
    // withPassengers: sole occupant false, nothing else set, and (per the
    // branch above) actually counted as passengers.
    if (!capacity.commandAuthority || !capacity.soleManipulator) return null;
    return (
      CrewSelection.withPassengers,
      defaultArrangement,
      defaultCommand,
      defaultFlying,
      false,
      null,
      false,
      false,
      null,
      false,
      true,
      null,
      false,
      null,
    );
  }

  // justMe.
  if (!capacity.commandAuthority || !capacity.soleManipulator) return null;
  return (
    CrewSelection.justMe,
    defaultArrangement,
    defaultCommand,
    defaultFlying,
    false,
    null,
    false,
    false,
    null,
    false,
    true,
    null,
    false,
    null,
  );
}

DateTimeComponents _components(UtcInstant instant) {
  final dt = instant.asUtcDateTime;
  return (dt.hour, dt.minute);
}
