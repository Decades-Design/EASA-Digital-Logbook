import '../domain/model/flight_duration.dart';

/// One printed row of the `AMC1 FCL.050` twelve-column-group logbook sheet
/// — already resolved to exactly what a page renders, per
/// `docs/amc1-fcl050-layout.md` §2. Durations, not pre-formatted strings,
/// for every time-bearing column: #77's running totals need to sum these
/// exactly (`FlightDuration` sums in whole minutes, never floating-point
/// hours — see that class's own dartdoc), so formatting to `HH:MM` stays a
/// render-time concern, not something baked in here.
///
/// Represents a flight entry only. Group 11 (FSTD session) has no data
/// model yet — issue #28 — so there is no FSTD-shaped row here; the layout
/// still prints group 11's column heading with an empty body until one
/// exists.
class Amc1Fcl050Row {
  const Amc1Fcl050Row({
    required this.date,
    required this.departurePlace,
    required this.departureTime,
    required this.arrivalPlace,
    required this.arrivalTime,
    required this.aircraftMakeModelVariant,
    required this.aircraftRegistration,
    required this.singlePilotSingleEngine,
    required this.singlePilotMultiEngine,
    required this.multiPilotTime,
    required this.totalTimeOfFlight,
    required this.namesPic,
    required this.landingsDay,
    required this.landingsNight,
    required this.operationalNight,
    required this.operationalIfr,
    required this.pilotFunctionPic,
    required this.pilotFunctionCoPilot,
    required this.pilotFunctionDual,
    required this.pilotFunctionInstructor,
    required this.remarks,
  });

  /// Group 1, formatted `dd/mm/yy` per the sheet's own sub-heading — the one
  /// column not left as a raw value, since there is nothing to total or
  /// otherwise compute from a formatted date string.
  final String date;

  /// Group 2.
  final String departurePlace;
  final String departureTime;

  /// Group 3.
  final String arrivalPlace;
  final String arrivalTime;

  /// Group 4. Make, model and variant as one free-text sub-column — the
  /// sheet has no separate cell for each, and `Aircraft` has no distinct
  /// "variant" field beyond `manufacturer`/`model` free text.
  final String aircraftMakeModelVariant;
  final String aircraftRegistration;

  /// Group 5 — `easaMultiPilotTime`'s three mutually-exclusive quantities,
  /// which always sum to [totalTimeOfFlight].
  final FlightDuration singlePilotSingleEngine;
  final FlightDuration singlePilotMultiEngine;
  final FlightDuration multiPilotTime;

  /// Group 6.
  final FlightDuration totalTimeOfFlight;

  /// Group 7. `'SELF'` when this pilot held command, by paper-logbook
  /// convention; otherwise whoever else did, or blank when neither is
  /// known — see `amc1_fcl050_row_mapper.dart`'s own dartdoc for exactly
  /// which raw fact each case reads.
  final String namesPic;

  /// Group 8. Full-stop and touch-and-go combined per period — the sheet
  /// has no further split, unlike `Flight.landings`' own four counts.
  final int landingsDay;
  final int landingsNight;

  /// Group 9 — `easaNightTime`'s `night`, `easaInstrumentTime`'s `ifr`.
  final FlightDuration operationalNight;
  final FlightDuration operationalIfr;

  /// Group 10 — `easaPilotFunctionTime`'s six named quantities folded to
  /// this sheet's four: SPIC and PICUS are both claimed *as* PIC time on
  /// the printed sheet (FCL.010 has no separate PIC sub-column for either),
  /// so both fold into [pilotFunctionPic] alongside plain PIC.
  final FlightDuration pilotFunctionPic;
  final FlightDuration pilotFunctionCoPilot;
  final FlightDuration pilotFunctionDual;
  final FlightDuration pilotFunctionInstructor;

  /// Group 12. Mandatory remarks (skill tests, proficiency checks,
  /// SPIC/PICUS countersignatures, instrument training) share this one
  /// free-text cell with ordinary pilot remarks — `docs/amc1-fcl050-
  /// layout.md` §5 is explicit the printed sheet has no structured field
  /// for either.
  final String remarks;
}
