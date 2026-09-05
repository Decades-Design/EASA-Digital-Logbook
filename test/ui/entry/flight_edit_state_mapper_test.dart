import 'package:easa_digital_log/domain/model/aircraft.dart';
import 'package:easa_digital_log/domain/model/countersignature.dart';
import 'package:easa_digital_log/domain/model/flight.dart';
import 'package:easa_digital_log/domain/model/flight_duration.dart';
import 'package:easa_digital_log/domain/model/instructor_presence.dart';
import 'package:easa_digital_log/domain/model/pilot_capacity.dart';
import 'package:easa_digital_log/domain/model/utc_instant.dart';
import 'package:easa_digital_log/ui/entry/flight_draft_mapper.dart';
import 'package:easa_digital_log/ui/entry/flight_edit_state_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

const _aircraft = Aircraft(
  registration: 'G-ABCD',
  manufacturer: 'Cessna',
  model: '172S',
  icaoTypeDesignator: 'C172',
  category: AircraftCategory.aeroplane,
  engineType: EngineType.piston,
  engineCount: 1,
  operatingSurface: OperatingSurface.land,
  requiresMultiCrew: false,
);

/// The screen's own `_utcOf` combines the wizard's single [state.date] with
/// each field's separate hour/minute — reproduced here so the round-trip
/// test exercises exactly what `NewFlightScreen` will do when it rebuilds a
/// [DraftFlightInputs] from a resolved [EditFormState].
UtcInstant? _instant(EditFormState state, DateTimeComponents? components) {
  if (components == null) return null;
  return UtcInstant.utc(
    state.date.year,
    state.date.month,
    state.date.day,
    components.$1,
    components.$2,
  );
}

/// Rebuilds a [Flight] from [state] the same way `NewFlightScreen` will:
/// combine its own local fields into a [DraftFlightInputs] and run it
/// through the same forward mapper editing must remain consistent with.
Flight _rebuild(EditFormState state, Aircraft aircraft) {
  final flight = buildDraftFlight(
    DraftFlightInputs(
      aircraft: aircraft,
      route: state.route,
      offBlocks: _instant(state, state.offBlocks)!,
      onBlocks: _instant(state, state.onBlocks)!,
      takeoff: _instant(state, state.takeoff),
      landing: _instant(state, state.landing),
      crew: state.crew,
      isStudent: false,
      soloEndorsementHeld: true,
      endorsingInstructorName: '',
      arrangement: state.arrangement,
      instructorName: state.instructorName,
      instructorLicence: state.instructorLicence,
      instructorCredentialExpiry: state.instructorCredentialExpiry == null
          ? null
          : (
              state.instructorCredentialExpiry!.year,
              state.instructorCredentialExpiry!.month,
              state.instructorCredentialExpiry!.day,
            ),
      purpose: state.purpose,
      instructorSoleManipulator: state.instructorSoleManipulator,
      instructorManipulationTime: state.instructorManipulationTime,
      instructorPassengers: state.instructorPassengers,
      command: state.command,
      flying: state.flying,
      otherPilotName: state.otherPilotName,
      otherPilotLicence: state.otherPilotLicence,
      multiPilotOperation: state.multiPilotOperation,
      otherPilotRole: state.otherPilotRole,
      picusClaimed: state.picusClaimed,
      picInterventionNotRequired: state.picInterventionNotRequired,
      otherManipulationTime: state.otherManipulationTime,
      otherPilotPassengers: state.otherPilotPassengers,
      sign: state.sign,
      signedAt: _instant(state, state.signedAt),
      ifrFlightPlanFiled: state.ifrFlightPlanFiled,
      actualInstrumentTime: state.actualInstrumentTime,
      simulatedInstrumentTime: state.simulatedInstrumentTime,
      approaches: state.approaches,
      holdingProceduresCount: state.holdingProceduresCount,
      trackingPerformed: state.trackingPerformed,
      takeoffs: CircuitCounts(
        dayFullStop: state.takeoffsDay,
        nightFullStop: state.takeoffsNight,
      ),
      landings: CircuitCounts(
        dayFullStop: state.landingsDay,
        nightFullStop: state.landingsNight,
      ),
      remarks: state.remarks,
    ),
  )!;
  return preserveWizardBlindSpots(flight, flight);
}

void main() {
  group('round-trips through the wizard for every supported crew shape', () {
    void expectRoundTrip(Flight original) {
      final resolution = resolveEditFormState(original, _aircraft);
      expect(
        resolution,
        isA<EditFormSupported>(),
        reason: 'expected this capacity shape to be supported',
      );
      final state = (resolution as EditFormSupported).state;
      final rebuilt = _rebuild(state, _aircraft);
      expect(rebuilt, original);
    }

    test('justMe: solo PIC', () {
      expectRoundTrip(
        Flight(
          aircraftRegistration: 'G-ABCD',
          route: const ['EGKA', 'EGKA'],
          prePlannedNavigation: false,
          offBlocks: UtcInstant.utc(2026, 3, 1, 9, 0),
          onBlocks: UtcInstant.utc(2026, 3, 1, 10, 0),
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
        ),
      );
    });

    test('withInstructor: receiving instruction (dual)', () {
      expectRoundTrip(
        Flight(
          aircraftRegistration: 'G-ABCD',
          route: const ['EGKA', 'EGKA'],
          prePlannedNavigation: false,
          offBlocks: UtcInstant.utc(2026, 3, 1, 9, 0),
          onBlocks: UtcInstant.utc(2026, 3, 1, 10, 0),
          capacity: PilotCapacity(
            commandAuthority: false,
            soleManipulator: true,
            soleOccupant: false,
            multiPilotOperation: false,
            additionalCrewRequiredByRule: false,
            actingAsInstructor: false,
            actingAsExaminer: false,
            picusClaimed: false,
            picInterventionNotRequired: false,
            instructor: const InstructorPresence(
              capacity: InstructorCapacity.flightInstructor,
              influencedFlight: true,
              name: 'J. Reilly',
              credentialNumber: 'FI-123',
            ),
            countersignature: const Countersignature(
              status: CountersignatureStatus.pending,
              signatoryName: 'J. Reilly',
              signatoryCredentialNumber: 'FI-123',
            ),
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
        ),
      );
    });

    test('withInstructor: SPIC (in command, instructor observing)', () {
      expectRoundTrip(
        Flight(
          aircraftRegistration: 'G-ABCD',
          route: const ['EGKA', 'EGKA'],
          prePlannedNavigation: false,
          offBlocks: UtcInstant.utc(2026, 3, 1, 9, 0),
          onBlocks: UtcInstant.utc(2026, 3, 1, 10, 0),
          capacity: PilotCapacity(
            commandAuthority: true,
            soleManipulator: true,
            soleOccupant: false,
            multiPilotOperation: false,
            additionalCrewRequiredByRule: false,
            actingAsInstructor: false,
            actingAsExaminer: false,
            picusClaimed: false,
            picInterventionNotRequired: false,
            instructor: const InstructorPresence(
              capacity: InstructorCapacity.flightInstructor,
              influencedFlight: false,
              name: 'J. Reilly',
            ),
            countersignature: const Countersignature(
              status: CountersignatureStatus.signed,
              signatoryName: 'J. Reilly',
              signedAt: null,
            ),
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
        ),
      );
    });

    test('withOtherPilot: PICUS claimed, split manipulation time', () {
      expectRoundTrip(
        Flight(
          aircraftRegistration: 'G-ABCD',
          route: const ['EGKA', 'EGHH', 'EGKA'],
          prePlannedNavigation: false,
          offBlocks: UtcInstant.utc(2026, 3, 1, 9, 0),
          onBlocks: UtcInstant.utc(2026, 3, 1, 11, 0),
          capacity: const PilotCapacity(
            commandAuthority: false,
            soleManipulator: false,
            soleOccupant: false,
            multiPilotOperation: true,
            additionalCrewRequiredByRule: false,
            actingAsInstructor: false,
            actingAsExaminer: false,
            picusClaimed: true,
            picInterventionNotRequired: true,
            manipulationTime: FlightDuration(45),
            otherPilotRole: OtherPilotRole.requiredCrew,
            countersignature: Countersignature(
              status: CountersignatureStatus.pending,
              signatoryName: 'M. Okafor',
              signatoryCredentialNumber: 'ATPL-456',
            ),
          ),
          otherPilotName: 'M. Okafor',
          otherPilotCredentialNumber: 'ATPL-456',
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
        ),
      );
    });

    test('withPassengers', () {
      expectRoundTrip(
        Flight(
          aircraftRegistration: 'G-ABCD',
          route: const ['EGKA', 'EGKA'],
          prePlannedNavigation: false,
          offBlocks: UtcInstant.utc(2026, 3, 1, 9, 0),
          onBlocks: UtcInstant.utc(2026, 3, 1, 10, 0),
          capacity: const PilotCapacity(
            commandAuthority: true,
            soleManipulator: true,
            soleOccupant: false,
            multiPilotOperation: false,
            additionalCrewRequiredByRule: false,
            actingAsInstructor: false,
            actingAsExaminer: false,
            picusClaimed: false,
            picInterventionNotRequired: false,
          ),
          carryingPassengers: true,
          takeoffs: const CircuitCounts(dayFullStop: 1),
          landings: const CircuitCounts(dayFullStop: 1),
          ifrFlightPlanFiled: false,
          actualInstrumentTime: FlightDuration.zero,
          simulatedInstrumentTime: FlightDuration.zero,
          approaches: const [],
          holdingProceduresCount: 0,
          trackingPerformed: false,
          remarks: '',
        ),
      );
    });
  });

  group('declines rather than guesses', () {
    Flight baseFlight(PilotCapacity capacity) => Flight(
      aircraftRegistration: 'G-ABCD',
      route: const ['EGKA', 'EGKA'],
      prePlannedNavigation: false,
      offBlocks: UtcInstant.utc(2026, 3, 1, 9, 0),
      onBlocks: UtcInstant.utc(2026, 3, 1, 10, 0),
      capacity: capacity,
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

    test('acting as instructor', () {
      final resolution = resolveEditFormState(
        baseFlight(
          const PilotCapacity(
            commandAuthority: true,
            soleManipulator: false,
            soleOccupant: false,
            multiPilotOperation: false,
            additionalCrewRequiredByRule: false,
            actingAsInstructor: true,
            actingAsExaminer: false,
            picusClaimed: false,
            picInterventionNotRequired: false,
          ),
        ),
        _aircraft,
      );
      expect(resolution, isA<EditFormUnsupported>());
      expect(
        (resolution as EditFormUnsupported).reason,
        EditUnsupportedReason.actingAsInstructorOrExaminer,
      );
    });

    test('acting as examiner', () {
      final resolution = resolveEditFormState(
        baseFlight(
          const PilotCapacity(
            commandAuthority: true,
            soleManipulator: false,
            soleOccupant: false,
            multiPilotOperation: false,
            additionalCrewRequiredByRule: false,
            actingAsInstructor: false,
            actingAsExaminer: true,
            picusClaimed: false,
            picInterventionNotRequired: false,
          ),
        ),
        _aircraft,
      );
      expect(resolution, isA<EditFormUnsupported>());
      expect(
        (resolution as EditFormUnsupported).reason,
        EditUnsupportedReason.actingAsInstructorOrExaminer,
      );
    });

    test('countersignature refused', () {
      final resolution = resolveEditFormState(
        baseFlight(
          PilotCapacity(
            commandAuthority: false,
            soleManipulator: false,
            soleOccupant: false,
            multiPilotOperation: true,
            additionalCrewRequiredByRule: false,
            actingAsInstructor: false,
            actingAsExaminer: false,
            picusClaimed: true,
            picInterventionNotRequired: true,
            otherPilotRole: OtherPilotRole.requiredCrew,
            countersignature: const Countersignature(
              status: CountersignatureStatus.refused,
            ),
          ),
        ),
        _aircraft,
      );
      expect(resolution, isA<EditFormUnsupported>());
      expect(
        (resolution as EditFormUnsupported).reason,
        EditUnsupportedReason.countersignatureRefused,
      );
    });

    test(
      'on-blocks past midnight, a different calendar date than off-blocks',
      () {
        final flight = Flight(
          aircraftRegistration: 'G-ABCD',
          route: const ['EGKA', 'EGKA'],
          prePlannedNavigation: false,
          offBlocks: UtcInstant.utc(2026, 3, 1, 23, 50),
          onBlocks: UtcInstant.utc(2026, 3, 2, 0, 15),
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
        final resolution = resolveEditFormState(flight, _aircraft);
        expect(resolution, isA<EditFormUnsupported>());
        expect(
          (resolution as EditFormUnsupported).reason,
          EditUnsupportedReason.overnightSpanningTimes,
        );
      },
    );
  });

  group('preserveWizardBlindSpots', () {
    test('carries forward fields the wizard has no question for', () {
      final original = Flight(
        aircraftRegistration: 'G-ABCD',
        route: const ['EGKA', 'EGHH'],
        prePlannedNavigation: true,
        offBlocks: UtcInstant.utc(2026, 3, 1, 9, 0),
        onBlocks: UtcInstant.utc(2026, 3, 1, 10, 0),
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
          soloEndorsementHeld: true,
          endorsingInstructorName: 'J. Reilly',
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
        seriesGroupId: 'series-1',
        remarks: '',
      );

      // What the wizard's forward mapper alone would produce -- notice it
      // silently drops prePlannedNavigation, seriesGroupId and the solo
      // endorsement, exactly the blind spots this function exists to patch.
      final mapped = original.copyWith(
        prePlannedNavigation: false,
        seriesGroupId: null,
        capacity: original.capacity.copyWith(
          soloEndorsementHeld: null,
          endorsingInstructorName: null,
        ),
      );

      final patched = preserveWizardBlindSpots(mapped, original);
      expect(patched, original);
    });
  });
}
