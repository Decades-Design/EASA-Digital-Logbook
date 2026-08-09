import '../model/flight.dart';
import '../model/flight_duration.dart';
import '../projection/derived_quantity.dart';

/// FAA `instrument_rule` primitive: `§61.51(g)(1)` actual instrument time and
/// `§61.51(b)(3)(iii)` simulated instrument time, kept as two independent
/// figures — unlike [easaInstrumentTime]'s single IFR column, the FAA has no
/// concept of "flew under an IFR flight plan" as a loggable quantity at all,
/// so [Flight.ifrFlightPlanFiled] is never read here.
///
/// Both figures are stored, not derived from [blockTime]: `Flight.dart`
/// already carries [Flight.actualInstrumentTime] and
/// [Flight.simulatedInstrumentTime] as raw pilot-entered facts (rule 2 —
/// nobody can reconstruct after the fact how much of a flight was flown
/// solely by reference to instruments), so this primitive's job is only to
/// carry them into a [DerivedQuantity], not to compute them.
Map<String, DerivedQuantity> faaInstrumentTime(
  Flight flight,
  FlightDuration blockTime,
) {
  return {
    'actualInstrument': DerivedQuantity.creditable(
      flight.actualInstrumentTime,
      '§61.51(g)(1): time by sole reference to instruments, actual '
      'conditions',
    ),
    'simulatedInstrument': DerivedQuantity.creditable(
      flight.simulatedInstrumentTime,
      '§61.51(b)(3)(iii): time by sole reference to instruments, simulated',
    ),
  };
}
