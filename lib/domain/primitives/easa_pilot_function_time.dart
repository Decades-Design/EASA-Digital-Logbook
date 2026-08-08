import '../model/countersignature.dart';
import '../model/flight.dart';
import '../model/flight_duration.dart';
import '../model/pilot_capacity.dart';
import '../projection/derived_quantity.dart';

const String _pic = 'pic';
const String _dual = 'dual';
const String _spic = 'spic';
const String _picus = 'picus';
const String _copilot = 'copilot';
const String _instructor = 'instructor';

const List<String> _allNames = [
  _pic,
  _dual,
  _spic,
  _picus,
  _copilot,
  _instructor,
];

/// EASA `FCL.010` pilot function time: PIC, dual, SPIC and PICUS, plus
/// co-pilot and instructor time. One function, not six, because the six are
/// interdependent — see the dartdoc on [PilotFunctionTimeRule].
///
/// Every branch below was checked against all fifteen scenarios in
/// `test/fixtures/capacities/`, whose header comments record the exact
/// expected EASA outcome for issues #18/#19 to assert against — see
/// `easa_pilot_function_time_test.dart`, which is table-driven over that
/// same fixture set.
///
/// Branch order matters where a flight could theoretically match more than
/// one — FCL.010 does not allow that in practice (no fixture exercises it),
/// but the first matching branch below always wins.
Map<String, DerivedQuantity> easaPilotFunctionTime(
  Flight flight,
  FlightDuration blockTime,
) {
  final capacity = flight.capacity;

  // 1. Acting as instructor. AMC1 FCL.050(b)(1)(ii) records the same time as
  // both instructor time (column 10) and PIC — flight_instructor.yaml.
  if (capacity.actingAsInstructor) {
    return _result(
      blockTime,
      reason: 'this pilot was instructing',
      overrides: {
        _pic: DerivedQuantity.creditable(
          blockTime,
          'FCL.010: PIC while serving as the authorised instructor',
        ),
        _instructor: DerivedQuantity.creditable(
          blockTime,
          'AMC1 FCL.050 column 10: instructor time',
        ),
      },
    );
  }

  // 2. PICUS claimed. picus_countersigned/pending/refused.yaml: the claim
  // itself is the raw fact (PilotCapacity.picusClaimed); creditability turns
  // entirely on the countersignature that arrives after the flight.
  if (capacity.picusClaimed) {
    final quantity = _countersignedQuantity(
      blockTime,
      capacity.countersignature,
      claim: 'PICUS',
    );
    return _result(
      blockTime,
      reason: 'PICUS claimed instead',
      overrides: {_pic: quantity, _picus: quantity},
    );
  }

  if (capacity.commandAuthority) {
    final instructor = capacity.instructor;

    // 3a. SPIC: command held, an instructor aboard who did not influence
    // the flight. spic.yaml. Do not implement this as "instructor aboard
    // and not influencing" alone — that is wrong for any flight where the
    // pilot did not hold command (sole_manipulator_receiving_instruction
    // .yaml fails exactly this test and is dual instead, below).
    if (instructor != null && !instructor.influencedFlight) {
      final quantity = _countersignedQuantity(
        blockTime,
        capacity.countersignature,
        claim: 'SPIC',
      );
      return _result(
        blockTime,
        reason: 'SPIC claimed instead',
        overrides: {_pic: quantity, _spic: quantity},
      );
    }

    // 3b. Ordinary command PIC. FCL.010 does not care who was manipulating
    // — mid_flight_takeover.yaml, safety_pilot.yaml (EASA has no
    // safety-pilot category and reads command authority alone), examiner
    // .yaml (the mandatory column-12 remark is a Flight/export concern, not
    // a time computation), student_solo.yaml.
    return _result(
      blockTime,
      reason: 'command authority held instead',
      overrides: {
        _pic: DerivedQuantity.creditable(
          blockTime,
          'FCL.010: command authority held',
        ),
      },
    );
  }

  // 4. Dual received: an instructor aboard who did influence the flight.
  // sole_manipulator_receiving_instruction.yaml, dual_received_not_
  // manipulating.yaml. Mutually exclusive with SPIC under FCL.010 — SPIC
  // (branch 3a) requires commandAuthority, which this branch has already
  // ruled out.
  final instructor = capacity.instructor;
  if (instructor != null && instructor.influencedFlight) {
    return _result(
      blockTime,
      reason: 'dual instruction received instead',
      overrides: {
        _dual: DerivedQuantity.creditable(
          blockTime,
          'FCL.010: dual instruction received',
        ),
      },
    );
  }

  // 5. Co-pilot / multi-pilot time. co_pilot_sic.yaml. Gated on
  // multiPilotOperation, not merely on another required pilot being aboard —
  // second_pilot_single_pilot_aircraft.yaml is the counterintuitive case
  // this excludes: EASA co-pilot time exists only in multi-pilot
  // operations, so a spare qualified pilot in a single-pilot aeroplane logs
  // nothing at all, however competent.
  if (capacity.multiPilotOperation &&
      capacity.otherPilotRole == OtherPilotRole.requiredCrew) {
    return _result(
      blockTime,
      reason: 'co-pilot time instead',
      overrides: {
        _copilot: DerivedQuantity.creditable(
          blockTime,
          'AMC1 FCL.050 column 5/10: multi-pilot co-pilot time',
        ),
      },
    );
  }

  // 6. None of the above. second_pilot_single_pilot_aircraft.yaml,
  // skill_test_with_examiner.yaml (candidate side: the examiner holds
  // command on a test flight, and an assessment is not instruction, so
  // neither PIC nor dual accrues to the candidate).
  return _result(
    blockTime,
    reason: 'no pilot function time accrues to this pilot for this flight',
    overrides: const {},
  );
}

/// All six named quantities, zeroed with [reason] and then [overrides]
/// applied on top — every branch in [easaPilotFunctionTime] returns the
/// complete six-key set this way, so no branch can accidentally omit a name
/// the next branch happened to set.
Map<String, DerivedQuantity> _result(
  FlightDuration blockTime, {
  required String reason,
  required Map<String, DerivedQuantity> overrides,
}) {
  final result = <String, DerivedQuantity>{
    for (final name in _allNames)
      name: DerivedQuantity.zero('FCL.010: $reason'),
  };
  result.addAll(overrides);
  return result;
}

/// The shared shape of SPIC and PICUS: both are logged as [claim] in the PIC
/// column, creditable only once countersigned — `AMC1 FCL.050` requires the
/// signature for both, and an unsigned entry must be reported as *not
/// creditable, with a reason*, never silently 0 and never silently valid
/// (`test/fixtures/capacities/picus_pending.yaml`,
/// `test/fixtures/capacities/spic.yaml`).
DerivedQuantity _countersignedQuantity(
  FlightDuration blockTime,
  Countersignature? countersignature, {
  required String claim,
}) {
  switch (countersignature?.status) {
    case CountersignatureStatus.signed:
      return DerivedQuantity.creditable(
        blockTime,
        'FCL.010: $claim, countersigned',
      );
    case CountersignatureStatus.refused:
      return DerivedQuantity.notCreditable(
        blockTime,
        'AMC1 FCL.050: $claim claimed; countersignature refused',
      );
    case CountersignatureStatus.pending:
    case null:
      return DerivedQuantity.notCreditable(
        blockTime,
        'AMC1 FCL.050: $claim claimed; awaiting countersignature',
      );
  }
}
