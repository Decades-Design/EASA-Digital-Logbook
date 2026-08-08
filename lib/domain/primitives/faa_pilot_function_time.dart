import '../model/flight.dart';
import '../model/flight_duration.dart';
import '../model/instructor_presence.dart';
import '../model/pilot_capacity.dart';
import '../projection/derived_quantity.dart';

/// FAA `§61.51` pilot function time: logged PIC, acting PIC, dual received,
/// SIC and solo.
///
/// Unlike [easaPilotFunctionTime], these five are **not** mutually
/// exclusive — `pic_sole_occupant.yaml` has logged PIC, acting PIC and solo
/// all simultaneously non-zero for the same flight, because `§61.51`
/// answers five separate questions rather than assigning one flight to one
/// bucket. So each quantity is computed independently below, not as a
/// branching chain where the first match wins.
///
/// Every rule was checked against all sixteen documented scenarios in
/// `test/fixtures/capacities/` — see `faa_pilot_function_time_test.dart`,
/// table-driven over that same set, and shared with #18's EASA test so the
/// two jurisdictions' answers for one fixture sit side by side.
Map<String, DerivedQuantity> faaPilotFunctionTime(
  Flight flight,
  FlightDuration blockTime,
) {
  final capacity = flight.capacity;

  return {
    'actingPic': _actingPic(capacity, blockTime),
    'loggedPic': _loggedPic(capacity, blockTime),
    'dualReceived': _dualReceived(capacity, blockTime),
    'sic': _sic(capacity, blockTime),
    'solo': _solo(capacity, blockTime),
  };
}

/// `§91.3`: final authority and responsibility. Mirrors
/// [PilotCapacity.commandAuthority] directly — it is the same jurisdiction-
/// agnostic fact FCL.010 reads for command, restated for the FAA reading.
/// `safety_pilot.yaml` is explicit that this and [_loggedPic] can both be
/// full block time for the same flight, for different reasons.
DerivedQuantity _actingPic(PilotCapacity capacity, FlightDuration blockTime) =>
    capacity.commandAuthority
    ? DerivedQuantity.creditable(
        blockTime,
        '§91.3: acting PIC, command authority held',
      )
    : DerivedQuantity.zero('§91.3: command authority not held');

/// `§61.51(d)`. Independent of every other quantity here — a pilot can be
/// solo and receiving no instruction, or solo is simply `false` the moment
/// anyone else is aboard, instructor or not.
DerivedQuantity _solo(PilotCapacity capacity, FlightDuration blockTime) =>
    capacity.soleOccupant
    ? DerivedQuantity.creditable(blockTime, '§61.51(d): sole occupant')
    : DerivedQuantity.zero('§61.51(d): not the sole occupant');

/// Three independent bases can each justify logging PIC time, checked in
/// this order — `flight_instructor.yaml`, `student_solo.yaml`,
/// `mid_flight_takeover.yaml` each exercise a different one. Whichever
/// basis applies, the *value* is the same in every fixture but one:
/// `mid_flight_takeover.yaml`, where §61.51(e)(1)(i) covers only the
/// manipulated portion, never overclaiming the whole flight.
///
/// None of these bases verify the pilot was actually *rated* for the
/// aircraft — no licence/rating record exists yet in this codebase (M1).
/// Every fixture's own comment carries the same "(sole manipulator, rated)"
/// qualifier; this is a known, uniform limitation, not an omission specific
/// to any one branch.
DerivedQuantity _loggedPic(PilotCapacity capacity, FlightDuration blockTime) {
  if (capacity.actingAsInstructor && capacity.commandAuthority) {
    return DerivedQuantity.creditable(
      blockTime,
      '§61.51(e)(3): PIC while serving as the authorised instructor',
    );
  }
  if (capacity.soloEndorsementHeld == true && capacity.soleOccupant) {
    return DerivedQuantity.creditable(
      blockTime,
      '§61.51(e)(4): student solo under a §61.87 endorsement',
    );
  }
  if (capacity.soleManipulator) {
    return DerivedQuantity.creditable(
      blockTime,
      '§61.51(e)(1)(i): sole manipulator, rated',
    );
  }
  final manipulationTime = capacity.manipulationTime;
  if (manipulationTime != null) {
    return DerivedQuantity.creditable(
      manipulationTime,
      '§61.51(e)(1)(i): sole manipulator for the manipulated portion only',
    );
  }
  return DerivedQuantity.zero(
    '§61.51(e)(1)(i): not the sole manipulator, in whole or in part',
  );
}

/// `§61.51(h)`. Gated on [InstructorPresence.capacity] as well as
/// [InstructorPresence.influencedFlight] — an examiner's checkride is not
/// "training received" even where an examiner did actively fly, which no
/// fixture exercises but which `§61.51(h)` does not cover either.
DerivedQuantity _dualReceived(
  PilotCapacity capacity,
  FlightDuration blockTime,
) {
  final instructor = capacity.instructor;
  final receivedInstruction =
      instructor != null &&
      instructor.influencedFlight &&
      instructor.capacity == InstructorCapacity.flightInstructor;
  return receivedInstruction
      ? DerivedQuantity.creditable(blockTime, '§61.51(h): training received')
      : DerivedQuantity.zero('§61.51(h): no training received');
}

/// `§61.51(f)`: SIC requires an aircraft that needs more than one pilot by
/// type certificate or by the rules the flight is operated under
/// ([PilotCapacity.additionalCrewRequiredByRule] or
/// [PilotCapacity.multiPilotOperation]), and this pilot not being the one
/// flying or in command. `co_pilot_sic.yaml` is the case where this fires;
/// `second_pilot_single_pilot_aircraft.yaml` is the case where neither
/// multi-pilot flag is set and it correctly does not.
DerivedQuantity _sic(PilotCapacity capacity, FlightDuration blockTime) {
  final multiCrew =
      capacity.additionalCrewRequiredByRule || capacity.multiPilotOperation;
  final qualifiesAsSic =
      !capacity.commandAuthority && !capacity.soleManipulator && multiCrew;
  return qualifiesAsSic
      ? DerivedQuantity.creditable(
          blockTime,
          '§61.51(f): SIC, qualified crewmember of a multi-pilot operation',
        )
      : DerivedQuantity.zero('§61.51(f): SIC conditions not met');
}
