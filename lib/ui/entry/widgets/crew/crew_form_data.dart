import 'package:flutter/material.dart';

import '../../../../domain/model/pilot_capacity.dart';
import '../../entry_form_types.dart';
import 'crew_selection.dart';

/// The mutable pieces of entry-form state the four crew paths (§4A-§4D)
/// read and write, gathered into one bag rather than threaded through as
/// thirty-odd individual constructor parameters on every crew widget. Owned
/// and mutated by `NewFlightScreen` via [onSelectCrew] and friends; every
/// other field here is read-only from a crew widget's point of view.
///
/// Mirrors the shape of the flat `state` object in the Flight Entry Form
/// mockup's own logic class — one state, every section reads the slice it
/// needs.
class CrewFormData {
  const CrewFormData({
    required this.crew,
    required this.onSelectCrew,
    // §4A — just me.
    required this.isStudent,
    required this.soloEndorsementHeld,
    required this.onToggleSoloEndorsement,
    required this.endorsingInstructorController,
    // §4B — with an instructor.
    required this.arrangement,
    required this.onArrangementChanged,
    required this.spicOffered,
    required this.instructorNameController,
    required this.instructorLicenceController,
    required this.hasFaaLicence,
    required this.instructorCertExpiry,
    required this.onPickInstructorCertExpiry,
    required this.purpose,
    required this.onPurposeChanged,
    required this.examinerNoController,
    required this.result,
    required this.onResultChanged,
    required this.ratingAffectedController,
    required this.instructorSoleManipulator,
    required this.onToggleInstructorSoleManipulator,
    required this.instructorManipHoursController,
    required this.instructorManipMinutesController,
    required this.instructorPassengers,
    required this.onToggleInstructorPassengers,
    // §4C — with another pilot.
    required this.command,
    required this.onCommandChanged,
    required this.flying,
    required this.onFlyingChanged,
    required this.otherPilotNameController,
    required this.otherPilotLicenceController,
    required this.multiPilotOperation,
    required this.aircraftRequiresMultiCrew,
    required this.onToggleMultiPilot,
    required this.otherManipHoursController,
    required this.otherManipMinutesController,
    required this.otherPilotRole,
    required this.onOtherPilotRoleChanged,
    required this.picusClaimed,
    required this.onTogglePicus,
    required this.picInterventionNotRequired,
    required this.onTogglePicInterventionNotRequired,
    required this.simulatedInstrumentPresent,
    required this.otherPilotPassengers,
    required this.onToggleOtherPilotPassengers,
  });

  final CrewSelection? crew;
  final ValueChanged<CrewSelection> onSelectCrew;

  final bool isStudent;
  final bool soloEndorsementHeld;
  final VoidCallback onToggleSoloEndorsement;
  final TextEditingController endorsingInstructorController;

  final InstructorArrangement arrangement;
  final ValueChanged<InstructorArrangement> onArrangementChanged;

  /// Whether "I was in command, instructor observing only" (SPIC) is
  /// offered — FCL.020 restricts it to student pilots. Stubbed `true` by
  /// the caller until a real licence-profile source exists.
  final bool spicOffered;
  final TextEditingController instructorNameController;
  final TextEditingController instructorLicenceController;
  final bool hasFaaLicence;
  final DateTime? instructorCertExpiry;
  final VoidCallback onPickInstructorCertExpiry;
  final String? purpose;
  final ValueChanged<String?> onPurposeChanged;
  final TextEditingController examinerNoController;
  final String? result;
  final ValueChanged<String> onResultChanged;
  final TextEditingController ratingAffectedController;
  final bool instructorSoleManipulator;
  final VoidCallback onToggleInstructorSoleManipulator;
  final TextEditingController instructorManipHoursController;
  final TextEditingController instructorManipMinutesController;
  final bool instructorPassengers;
  final VoidCallback onToggleInstructorPassengers;

  final CommandChoice command;
  final ValueChanged<CommandChoice> onCommandChanged;
  final FlyingChoice flying;
  final ValueChanged<FlyingChoice> onFlyingChanged;
  final TextEditingController otherPilotNameController;
  final TextEditingController otherPilotLicenceController;
  final bool multiPilotOperation;

  /// Pre-fill hint from the resolved aircraft record — display only; the
  /// toggle itself is [multiPilotOperation], independently overridable
  /// (docs/entry-form.md §4C: "overridable for ops that require two pilots
  /// by regulation rather than by type certificate").
  final bool aircraftRequiresMultiCrew;
  final VoidCallback onToggleMultiPilot;
  final TextEditingController otherManipHoursController;
  final TextEditingController otherManipMinutesController;
  final OtherPilotRole? otherPilotRole;
  final ValueChanged<OtherPilotRole?> onOtherPilotRoleChanged;
  final bool picusClaimed;
  final VoidCallback onTogglePicus;
  final bool picInterventionNotRequired;
  final VoidCallback onTogglePicInterventionNotRequired;

  /// Whether §6 Conditions' simulated-instrument field is greater than
  /// zero — gates the safety-pilot toggle (§4C).
  final bool simulatedInstrumentPresent;
  final bool otherPilotPassengers;
  final VoidCallback onToggleOtherPilotPassengers;
}
