import '../model/aircraft.dart';
import '../model/flight.dart';
import '../model/flight_duration.dart';
import '../projection/derived_quantity.dart';

/// EASA `multi_pilot_rule` primitive: `AMC1 FCL.050` column 5 —
/// single-pilot time, split single-engine/multi-engine, and multi-pilot
/// time, undivided — as three mutually exclusive quantities that always
/// sum to [blockTime].
///
/// The single-pilot/multi-pilot split reads [Flight.capacity]'s
/// [PilotCapacity.multiPilotOperation], **not** [Aircraft.requiresMultiCrew]
/// — that field is what actually happened on this flight, already
/// independent of what the aircraft's type certificate requires (see its
/// dartdoc), which is exactly what #26 asks for: a multi-crew operation
/// flown in a single-pilot-certified aircraft is multi-pilot time, and a
/// solo flight in a multi-pilot-certified aircraft is not. The SE/ME split
/// within single-pilot time is the one part of this column that genuinely
/// is an aircraft fact — [Aircraft.engineCount] — since it describes the
/// machine, not the crew.
///
/// [Aircraft.engineCount] of zero or one (gliders, balloons, and every
/// single-engine aeroplane or helicopter) falls in the single-engine
/// bucket: `AMC1 FCL.050` column 5 has no separate sub-column for
/// unpowered categories, and how the printed sheet labels that time is
/// #27's layout concern, not this primitive's.
Map<String, DerivedQuantity> easaMultiPilotTime(
  Flight flight,
  Aircraft aircraft,
  FlightDuration blockTime,
) {
  if (flight.capacity.multiPilotOperation) {
    return {
      'multiPilot': DerivedQuantity.creditable(
        blockTime,
        'AMC1 FCL.050 column 5: multi-pilot operation',
      ),
      'singlePilotSingleEngine': DerivedQuantity.zero(
        'AMC1 FCL.050 column 5: multi-pilot operation instead',
      ),
      'singlePilotMultiEngine': DerivedQuantity.zero(
        'AMC1 FCL.050 column 5: multi-pilot operation instead',
      ),
    };
  }

  final singleEngine = aircraft.engineCount <= 1;
  return {
    'multiPilot': DerivedQuantity.zero(
      'AMC1 FCL.050 column 5: single-pilot operation',
    ),
    'singlePilotSingleEngine': singleEngine
        ? DerivedQuantity.creditable(
            blockTime,
            'AMC1 FCL.050 column 5: single-pilot, single-engine',
          )
        : DerivedQuantity.zero(
            'AMC1 FCL.050 column 5: single-pilot, but multi-engine',
          ),
    'singlePilotMultiEngine': singleEngine
        ? DerivedQuantity.zero(
            'AMC1 FCL.050 column 5: single-pilot, but single-engine',
          )
        : DerivedQuantity.creditable(
            blockTime,
            'AMC1 FCL.050 column 5: single-pilot, multi-engine',
          ),
  };
}
