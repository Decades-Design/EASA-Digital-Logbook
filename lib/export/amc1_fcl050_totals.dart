import '../domain/model/flight_duration.dart';
import 'amc1_fcl050_row.dart';

/// The sum, across a set of [Amc1Fcl050Row]s, of every column AMC1
/// FCL.050's totals band can meaningfully total (#77) — every duration
/// field via [FlightDuration.sum] (integer minutes, never floating
/// point — see that class's own dartdoc), and the two landings counts as
/// plain integer sums. Dates, places, aircraft, name(s) PIC and remarks
/// have no total: [amc1Fcl050PageOneTotalsValues]/
/// [amc1Fcl050PageTwoTotalsValues] leave those columns blank.
class Amc1Fcl050Totals {
  const Amc1Fcl050Totals({
    required this.singlePilotSingleEngine,
    required this.singlePilotMultiEngine,
    required this.multiPilotTime,
    required this.totalTimeOfFlight,
    required this.landingsDay,
    required this.landingsNight,
    required this.operationalNight,
    required this.operationalIfr,
    required this.pilotFunctionPic,
    required this.pilotFunctionCoPilot,
    required this.pilotFunctionDual,
    required this.pilotFunctionInstructor,
  });

  static const zero = Amc1Fcl050Totals(
    singlePilotSingleEngine: FlightDuration.zero,
    singlePilotMultiEngine: FlightDuration.zero,
    multiPilotTime: FlightDuration.zero,
    totalTimeOfFlight: FlightDuration.zero,
    landingsDay: 0,
    landingsNight: 0,
    operationalNight: FlightDuration.zero,
    operationalIfr: FlightDuration.zero,
    pilotFunctionPic: FlightDuration.zero,
    pilotFunctionCoPilot: FlightDuration.zero,
    pilotFunctionDual: FlightDuration.zero,
    pilotFunctionInstructor: FlightDuration.zero,
  );

  /// Sums every summable field across [rows]. [zero] for an empty list.
  factory Amc1Fcl050Totals.fromRows(
    List<Amc1Fcl050Row> rows,
  ) => Amc1Fcl050Totals(
    singlePilotSingleEngine: FlightDuration.sum(
      rows.map((row) => row.singlePilotSingleEngine),
    ),
    singlePilotMultiEngine: FlightDuration.sum(
      rows.map((row) => row.singlePilotMultiEngine),
    ),
    multiPilotTime: FlightDuration.sum(rows.map((row) => row.multiPilotTime)),
    totalTimeOfFlight: FlightDuration.sum(
      rows.map((row) => row.totalTimeOfFlight),
    ),
    landingsDay: rows.fold(0, (sum, row) => sum + row.landingsDay),
    landingsNight: rows.fold(0, (sum, row) => sum + row.landingsNight),
    operationalNight: FlightDuration.sum(
      rows.map((row) => row.operationalNight),
    ),
    operationalIfr: FlightDuration.sum(rows.map((row) => row.operationalIfr)),
    pilotFunctionPic: FlightDuration.sum(
      rows.map((row) => row.pilotFunctionPic),
    ),
    pilotFunctionCoPilot: FlightDuration.sum(
      rows.map((row) => row.pilotFunctionCoPilot),
    ),
    pilotFunctionDual: FlightDuration.sum(
      rows.map((row) => row.pilotFunctionDual),
    ),
    pilotFunctionInstructor: FlightDuration.sum(
      rows.map((row) => row.pilotFunctionInstructor),
    ),
  );

  final FlightDuration singlePilotSingleEngine;
  final FlightDuration singlePilotMultiEngine;
  final FlightDuration multiPilotTime;
  final FlightDuration totalTimeOfFlight;
  final int landingsDay;
  final int landingsNight;
  final FlightDuration operationalNight;
  final FlightDuration operationalIfr;
  final FlightDuration pilotFunctionPic;
  final FlightDuration pilotFunctionCoPilot;
  final FlightDuration pilotFunctionDual;
  final FlightDuration pilotFunctionInstructor;

  /// Combines two totals field by field — used to accumulate a running
  /// "brought forward" figure across spreads (#77) without re-summing
  /// every row seen so far on every page.
  Amc1Fcl050Totals operator +(Amc1Fcl050Totals other) => Amc1Fcl050Totals(
    singlePilotSingleEngine:
        singlePilotSingleEngine + other.singlePilotSingleEngine,
    singlePilotMultiEngine:
        singlePilotMultiEngine + other.singlePilotMultiEngine,
    multiPilotTime: multiPilotTime + other.multiPilotTime,
    totalTimeOfFlight: totalTimeOfFlight + other.totalTimeOfFlight,
    landingsDay: landingsDay + other.landingsDay,
    landingsNight: landingsNight + other.landingsNight,
    operationalNight: operationalNight + other.operationalNight,
    operationalIfr: operationalIfr + other.operationalIfr,
    pilotFunctionPic: pilotFunctionPic + other.pilotFunctionPic,
    pilotFunctionCoPilot: pilotFunctionCoPilot + other.pilotFunctionCoPilot,
    pilotFunctionDual: pilotFunctionDual + other.pilotFunctionDual,
    pilotFunctionInstructor:
        pilotFunctionInstructor + other.pilotFunctionInstructor,
  );
}

/// `HH:MM` for a totals-band figure — unlike a per-flight cell (which
/// leaves a zero duration blank, matching how a pilot fills in a paper
/// logbook — see `amc1_fcl050_layout.dart`'s own `_duration`), a
/// *computed* total always prints its value, including `00:00`, so a
/// genuinely zero total is never confused with a column that was simply
/// never computed.
String _totalDuration(FlightDuration value) => value.toHoursMinutes();

/// The hours and minutes halves of a totals-band duration, as the two
/// physical columns a duration leaf always splits into — see
/// [_totalDuration].
List<String> _totalDurationParts(FlightDuration value) {
  final parts = _totalDuration(value).split(':');
  return [parts[0], parts[1]];
}

/// Groups 1–8's sixteen physical columns for one page's running totals —
/// mirrors `amc1Fcl050PageOneCellValues`'s column order exactly, but
/// every duration/count column shows [totals]' summed figure (never
/// blank on zero) and every non-summable column (date, places, aircraft,
/// name(s) PIC) is blank, since a total means nothing there. Public so a
/// test can assert the totals-to-column mapping, and reconciliation
/// across spreads, directly — without parsing rendered PDF content back
/// out.
List<String> amc1Fcl050PageOneTotalsValues(Amc1Fcl050Totals totals) => [
  '', // date
  '', '', // departure place, time
  '', '', // arrival place, time
  '', '', // aircraft make/model/variant, registration
  _totalDuration(totals.singlePilotSingleEngine),
  _totalDuration(totals.singlePilotMultiEngine),
  ..._totalDurationParts(totals.multiPilotTime),
  ..._totalDurationParts(totals.totalTimeOfFlight),
  '', // names PIC
  totals.landingsDay.toString(),
  totals.landingsNight.toString(),
];

/// Groups 9–12's totals — see [amc1Fcl050PageOneTotalsValues]. FSTD
/// session is always blank (no FSTD data model exists yet — #28); this
/// list has no remarks entry, since the totals band's remarks column
/// carries the certification block instead of a sixteenth total.
List<String> amc1Fcl050PageTwoTotalsValues(Amc1Fcl050Totals totals) => [
  ..._totalDurationParts(totals.operationalNight),
  ..._totalDurationParts(totals.operationalIfr),
  ..._totalDurationParts(totals.pilotFunctionPic),
  ..._totalDurationParts(totals.pilotFunctionCoPilot),
  ..._totalDurationParts(totals.pilotFunctionDual),
  ..._totalDurationParts(totals.pilotFunctionInstructor),
  '', '', // FSTD date, type
  '', '', // FSTD total time of session, hours/minutes
];
