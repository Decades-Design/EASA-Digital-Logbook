import 'flight.dart';
import 'flight_duration.dart';

/// Block time and airborne time — #27's two distinct total-time readings.
///
/// Neither is stored: [Flight.onBlocks]'s own dartdoc already promises block
/// time is "not stored — it is `onBlocks.difference(offBlocks)`, computed on
/// read" (CLAUDE.md rule 1), and airborne time is the same idea applied to
/// [Flight.takeoff]/[Flight.landing]. This extension is the one place both
/// computations happen, so every caller reads the same arithmetic rather
/// than re-deriving it.
extension FlightTimes on Flight {
  /// `AMC1 FCL.050(g)(1)`; `§1.1`. First movement for the purpose of
  /// departure to finally coming to rest. Always available —
  /// [Flight.offBlocks] and [Flight.onBlocks] are both required fields.
  FlightDuration get blockTime =>
      FlightDuration(onBlocks.difference(offBlocks).inMinutes);

  /// Time actually airborne, from [Flight.takeoff] to [Flight.landing].
  ///
  /// `null` whenever either instant was not recorded. That is the ordinary
  /// case, not an error — #27's own acceptance criteria note "many pilots
  /// record only block times" — so a caller that needs airborne time and
  /// gets `null` back must say so explicitly in its own result rather than
  /// silently substituting [blockTime] for it. `night_time_support.dart`
  /// used to do exactly that substitution without disclosing it; this
  /// getter exists so that mistake can't happen again by accident.
  FlightDuration? get airborneTime {
    final start = takeoff;
    final end = landing;
    if (start == null || end == null) {
      return null;
    }
    return FlightDuration(end.difference(start).inMinutes);
  }
}
