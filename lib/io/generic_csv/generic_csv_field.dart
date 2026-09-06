/// The canonical fields the generic CSV importer (#72) can map a column
/// to — deliberately a smaller vocabulary than the vendor adapters'
/// (#69/#71). Those adapters have a fixed, known vendor schema to read
/// from; a hand-kept spreadsheet realistically has a handful of columns,
/// not the dozens ForeFlight/Garmin export. `[requiredGenericCsvFields]`
/// names the ones a mapping cannot be saved without.
enum GenericCsvField {
  /// Calendar date, e.g. `2026-01-01` — paired with [offBlocksTime]/
  /// [onBlocksTime] to build the block-time instants every [Flight]
  /// requires. Required.
  date,

  /// Time-of-day off blocks, `HH:MM`. Required — this app has no
  /// duration-only path for a regular flight (the same rule #71's Garmin
  /// importer established: `Flight.offBlocks`/`onBlocks` are non-nullable
  /// raw facts, and the entry form itself has no "just enter total hours"
  /// mode either).
  offBlocksTime,

  /// Time-of-day on blocks, `HH:MM`. Required.
  onBlocksTime,

  /// The aircraft's registration, e.g. `G-ABCD`. Required.
  aircraftRegistration,

  /// Free text naming the aircraft type, e.g. `C172` — optional. Used only
  /// as [Aircraft.model] when a registration is seen for the first time;
  /// see `generic_csv_adapter.dart`'s own dartdoc on why a placeholder
  /// [Aircraft] is safe to construct here.
  aircraftType,

  /// Departure aerodrome identifier. Required.
  departure,

  /// Destination aerodrome identifier. Required.
  destination,

  /// PIC duration, in whatever [CsvDurationFormat] the mapping specifies.
  picDuration,

  /// SIC duration.
  sicDuration,

  /// Dual received duration.
  dualReceivedDuration,

  /// Solo duration.
  soloDuration,

  /// Day landings, full-stop and touch-and-go combined — a hand-kept
  /// spreadsheet essentially never splits the two, so there's nothing to
  /// disambiguate here the way #69/#71 did against a vendor total.
  dayLandings,

  /// Night landings, same caveat as [dayLandings].
  nightLandings,

  /// Free-text remarks.
  remarks,
}

/// A mapping cannot be saved or used without an assignment for every one
/// of these — everything else in [GenericCsvField] is optional and simply
/// defaults to zero/blank when unmapped.
const Set<GenericCsvField> requiredGenericCsvFields = {
  GenericCsvField.date,
  GenericCsvField.offBlocksTime,
  GenericCsvField.onBlocksTime,
  GenericCsvField.aircraftRegistration,
  GenericCsvField.departure,
  GenericCsvField.destination,
};

/// How a mapped date column is written. `CalendarDate.parse` only accepts
/// ISO `YYYY-MM-DD` — a hand-kept spreadsheet frequently doesn't, hence a
/// per-mapping, explicitly-chosen format rather than guessing one from the
/// data (CLAUDE.md: "reject with a clear per-row error rather than
/// silently coercing" applies just as much to which format a column is in
/// as to whether one cell parses).
enum CsvDateFormat {
  /// `YYYY-MM-DD`.
  isoYmd,

  /// `MM/DD/YYYY`.
  usMdy,

  /// `DD/MM/YYYY`.
  dmy,
}

/// How a mapped duration column is written.
enum CsvDurationFormat {
  /// `1.5`, `0.25`.
  decimalHours,

  /// `1:30`, `0:15`.
  hoursMinutes,
}
