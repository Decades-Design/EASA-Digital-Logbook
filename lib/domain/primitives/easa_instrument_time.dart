import '../model/flight.dart';
import '../model/flight_duration.dart';
import '../projection/derived_quantity.dart';

/// EASA `instrument_rule` primitive: `AMC1 FCL.050` column 9 ("operational
/// condition time") records IFR time as a single figure — the whole flight
/// counts once [Flight.ifrFlightPlanFiled] is true, regardless of whether
/// any of it was actually flown in instrument meteorological conditions.
///
/// This is the operational condition, not the meteorological one:
/// `docs/jurisdiction-matrix.md` §3 is explicit that "an IFR flight entirely
/// in VMC = full EASA IFR time, zero FAA instrument time" — see
/// [faaInstrumentTime] for the other half of that divergence. EASA has no
/// separate simulated-instrument column; `Flight.simulatedInstrumentTime`
/// is read only by the FAA primitive.
Map<String, DerivedQuantity> easaInstrumentTime(
  Flight flight,
  FlightDuration blockTime,
) {
  return {
    'ifr': flight.ifrFlightPlanFiled
        ? DerivedQuantity.creditable(
            blockTime,
            'AMC1 FCL.050 column 9: IFR flight plan filed',
          )
        : DerivedQuantity.zero(
            'AMC1 FCL.050 column 9: no IFR flight plan filed',
          ),
  };
}
