import 'package:csv/csv.dart';

import '../../domain/model/aircraft.dart';
import '../../domain/model/flight.dart';
import '../../domain/model/flight_duration.dart';
import '../../domain/model/pilot_capacity.dart';
import '../../domain/model/utc_instant.dart';
import '../canonical_import_row.dart';
import '../import_adapter.dart';
import 'generic_csv_field.dart';
import 'generic_csv_mapping.dart';

List<Map<String, String>> _parseCsvRows(String csvContent) {
  final allRows = Csv().decode(csvContent);
  if (allRows.isEmpty) return const [];
  final headers = allRows.first.map((cell) => cell.toString().trim()).toList();

  final rows = <Map<String, String>>[];
  for (final row in allRows.skip(1)) {
    if (row.every((cell) => cell.toString().trim().isEmpty)) continue;
    final map = <String, String>{};
    for (var i = 0; i < headers.length; i++) {
      map[headers[i]] = i < row.length ? row[i].toString().trim() : '';
    }
    rows.add(map);
  }
  return rows;
}

/// Reads a value mapped to [field] out of [row], or `''` if [field] isn't
/// mapped in [mapping] at all — an unmapped optional field, not a blank
/// cell.
String _value(
  Map<String, String> row,
  GenericCsvMapping mapping,
  GenericCsvField field,
) {
  final column = mapping.columnByField[field];
  if (column == null) return '';
  return row[column] ?? '';
}

({int year, int month, int day})? _parseDateParts(
  String raw,
  CsvDateFormat format,
) {
  final parts = raw.trim().split(RegExp(r'[-/]'));
  if (parts.length != 3) return null;
  final a = int.tryParse(parts[0]);
  final b = int.tryParse(parts[1]);
  final c = int.tryParse(parts[2]);
  if (a == null || b == null || c == null) return null;

  return switch (format) {
    CsvDateFormat.isoYmd => (year: a, month: b, day: c),
    CsvDateFormat.usMdy => (year: c, month: a, day: b),
    CsvDateFormat.dmy => (year: c, month: b, day: a),
  };
}

UtcInstant? _parseDateTime(
  String dateRaw,
  String timeRaw,
  CsvDateFormat format,
) {
  final dateParts = _parseDateParts(dateRaw, format);
  if (dateParts == null) return null;
  final timeParts = timeRaw.trim().split(':');
  if (timeParts.length != 2) return null;
  final hour = int.tryParse(timeParts[0]);
  final minute = int.tryParse(timeParts[1]);
  if (hour == null || minute == null) return null;

  try {
    return UtcInstant.utc(
      dateParts.year,
      dateParts.month,
      dateParts.day,
      hour,
      minute,
    );
  } on ArgumentError {
    return null;
  }
}

FlightDuration _parseDuration(String raw, CsvDurationFormat format) {
  if (raw.trim().isEmpty) return FlightDuration.zero;
  try {
    return format == CsvDurationFormat.decimalHours
        ? FlightDuration.parseDecimalHours(raw)
        : FlightDuration.parseHoursMinutes(raw);
  } on FormatException {
    return FlightDuration.zero;
  }
}

/// This pilot's [PilotCapacity], reverse-projected from whichever of
/// PIC/SIC/dual-received duration columns the mapping assigns and this row
/// populates — the same "flag, don't guess" reverse projection #69/#71 use
/// against a vendor schema, narrowed to the three tiers a hand-kept
/// spreadsheet realistically distinguishes. No PICUS, evaluator or
/// examiner column exists in this canonical field set at all: a generic
/// mapping has no structured way to say more than "the pilot flying logged
/// this much time in this capacity."
PilotCapacity _classifyCapacity(
  Map<String, String> row,
  GenericCsvMapping mapping,
  List<String> notes,
) {
  final pic = _parseDuration(
    _value(row, mapping, GenericCsvField.picDuration),
    mapping.durationFormat,
  );
  final sic = _parseDuration(
    _value(row, mapping, GenericCsvField.sicDuration),
    mapping.durationFormat,
  );
  final solo = _parseDuration(
    _value(row, mapping, GenericCsvField.soloDuration),
    mapping.durationFormat,
  );
  final dualReceived = _parseDuration(
    _value(row, mapping, GenericCsvField.dualReceivedDuration),
    mapping.durationFormat,
  );

  if (dualReceived.inMinutes > 0) {
    notes.add(
      'Logged as dual received — EASA SPIC vs. dual, and countersignature '
      'state, cannot be recovered from a generic CSV mapping and default '
      'to "not SPIC, no countersignature". Verify against the original '
      'record.',
    );
    return const PilotCapacity(
      commandAuthority: false,
      soleManipulator: true,
      soleOccupant: false,
      multiPilotOperation: false,
      additionalCrewRequiredByRule: false,
      actingAsInstructor: false,
      actingAsExaminer: false,
      picusClaimed: false,
      picInterventionNotRequired: false,
    );
  }

  if (sic.inMinutes > 0) {
    notes.add(
      'Logged as SIC — recorded as required crew, not holding command '
      'authority. Verify.',
    );
    return const PilotCapacity(
      commandAuthority: false,
      soleManipulator: false,
      soleOccupant: false,
      multiPilotOperation: false,
      additionalCrewRequiredByRule: true,
      actingAsInstructor: false,
      actingAsExaminer: false,
      picusClaimed: false,
      picInterventionNotRequired: false,
    );
  }

  if (pic.inMinutes > 0) {
    return PilotCapacity(
      commandAuthority: true,
      soleManipulator: true,
      soleOccupant: solo.inMinutes > 0,
      multiPilotOperation: false,
      additionalCrewRequiredByRule: false,
      actingAsInstructor: false,
      actingAsExaminer: false,
      picusClaimed: false,
      picInterventionNotRequired: false,
    );
  }

  notes.add(
    'None of PIC/SIC/dual received were mapped or populated for this row '
    "— pilot capacity couldn't be determined and defaults to every flag "
    'unset. Verify.',
  );
  return const PilotCapacity(
    commandAuthority: false,
    soleManipulator: false,
    soleOccupant: false,
    multiPilotOperation: false,
    additionalCrewRequiredByRule: false,
    actingAsInstructor: false,
    actingAsExaminer: false,
    picusClaimed: false,
    picInterventionNotRequired: false,
  );
}

/// Either a mapped `(flight, aircraft, unmappedFields, reviewNotes)`
/// bundle, or an [error] — the same shape ForeFlight's/Garmin's own row
/// mappings use, and for the same reason (#69's dartdoc): one bad row
/// reports its own problem rather than aborting the file.
class GenericCsvRowMapping {
  const GenericCsvRowMapping.mapped({
    required this.flight,
    required this.aircraft,
    this.unmappedFields = const {},
    this.reviewNotes = const [],
  }) : error = null;

  const GenericCsvRowMapping.error(this.error)
    : flight = null,
      aircraft = null,
      unmappedFields = const {},
      reviewNotes = const [];

  final Flight? flight;
  final Aircraft? aircraft;
  final String? error;
  final Map<String, String> unmappedFields;
  final List<String> reviewNotes;
}

/// Maps one CSV [row] using [mapping]. A generic CSV row has no aircraft
/// specification beyond a registration and, optionally, free-text type —
/// nothing like ForeFlight's/Garmin's own detailed aircraft tables. A
/// placeholder [Aircraft] (aeroplane, no engine, land, no qualifications)
/// is still constructed rather than erroring the row outright, because
/// `import_pipeline.dart`'s own `applyImport` already reuses an existing
/// stored registration's aircraft record instead of overwriting it — the
/// placeholder only ever matters for a registration genuinely new to this
/// app, and is heavily flagged for the pilot to correct under Aircraft
/// management rather than silently feeding a wrong category/engine into a
/// real currency calculation.
GenericCsvRowMapping mapGenericCsvRow(
  Map<String, String> row,
  GenericCsvMapping mapping,
) {
  final registration = _value(
    row,
    mapping,
    GenericCsvField.aircraftRegistration,
  );
  if (registration.isEmpty) {
    return const GenericCsvRowMapping.error(
      'The mapped aircraft registration column is blank — cannot resolve '
      'which aircraft this flight was flown in.',
    );
  }

  final dateRaw = _value(row, mapping, GenericCsvField.date);
  final offBlocks = _parseDateTime(
    dateRaw,
    _value(row, mapping, GenericCsvField.offBlocksTime),
    mapping.dateFormat,
  );
  var onBlocks = _parseDateTime(
    dateRaw,
    _value(row, mapping, GenericCsvField.onBlocksTime),
    mapping.dateFormat,
  );
  if (offBlocks == null || onBlocks == null) {
    return GenericCsvRowMapping.error(
      'Date "$dateRaw", off-blocks time '
      '"${_value(row, mapping, GenericCsvField.offBlocksTime)}" or on-blocks '
      'time "${_value(row, mapping, GenericCsvField.onBlocksTime)}" is '
      "missing or unparseable for the mapping's configured formats — every "
      'flight needs both block times.',
    );
  }
  if (onBlocks < offBlocks) onBlocks = onBlocks.add(const Duration(days: 1));

  final departure = _value(row, mapping, GenericCsvField.departure);
  final destination = _value(row, mapping, GenericCsvField.destination);
  if (departure.isEmpty || destination.isEmpty) {
    return const GenericCsvRowMapping.error(
      'The mapped departure or destination column is blank — every flight '
      'needs both.',
    );
  }

  final notes = <String>[];
  final capacity = _classifyCapacity(row, mapping, notes);

  final aircraftType = _value(row, mapping, GenericCsvField.aircraftType);
  notes.add(
    'Aircraft "$registration" details defaulted (category: aeroplane, '
    'engine: none, land) — a generic CSV mapping has no aircraft '
    'specification to read real values from. Correct it under Aircraft '
    'management if this is a new registration.',
  );
  final aircraft = Aircraft(
    registration: registration,
    manufacturer: '',
    model: aircraftType,
    category: AircraftCategory.aeroplane,
    engineType: EngineType.none,
    engineCount: 1,
    operatingSurface: OperatingSurface.land,
    requiresMultiCrew: false,
  );

  final flight = Flight(
    aircraftRegistration: registration,
    route: [departure, destination],
    prePlannedNavigation: false,
    offBlocks: offBlocks,
    onBlocks: onBlocks,
    capacity: capacity,
    carryingPassengers: false,
    takeoffs: const CircuitCounts(),
    landings: CircuitCounts(
      dayFullStop:
          int.tryParse(_value(row, mapping, GenericCsvField.dayLandings)) ?? 0,
      nightFullStop:
          int.tryParse(_value(row, mapping, GenericCsvField.nightLandings)) ??
          0,
    ),
    ifrFlightPlanFiled: false,
    actualInstrumentTime: FlightDuration.zero,
    simulatedInstrumentTime: FlightDuration.zero,
    approaches: const [],
    holdingProceduresCount: 0,
    trackingPerformed: false,
    remarks: _value(row, mapping, GenericCsvField.remarks),
  );

  final mappedColumns = mapping.columnByField.values.toSet();
  final unmappedFields = <String, String>{
    for (final entry in row.entries)
      if (!mappedColumns.contains(entry.key) && entry.value.isNotEmpty)
        entry.key: entry.value,
  };

  return GenericCsvRowMapping.mapped(
    flight: flight,
    aircraft: aircraft,
    unmappedFields: unmappedFields,
    reviewNotes: notes,
  );
}

/// Imports a spreadsheet the pilot has manually mapped to this app's
/// canonical fields (#72) — for LogTen, Skylog, MCC Pilot Log, and the
/// hand-kept spreadsheets none of the vendor adapters (#69/#71) cover.
///
/// Unlike those, there is no fixed vendor schema to validate the file
/// against — [parse] checks only that [mapping] assigns every one of
/// [requiredGenericCsvFields] to a header this file actually has, then
/// maps every data row the same "flag ambiguity, never guess" way
/// #69/#71 do.
class GenericCsvAdapter implements ImportAdapter {
  const GenericCsvAdapter(this.mapping);

  /// Key [parse] reads the CSV text from — see [ImportAdapter.parse].
  static const csvKey = 'csv';

  final GenericCsvMapping mapping;

  @override
  String get displayName => 'Generic CSV (${mapping.name})';

  @override
  ImportParseResult parse(Map<String, String> sources) {
    final csvContent = sources[csvKey];
    if (csvContent == null) {
      throw ArgumentError(
        'GenericCsvAdapter.parse requires a "$csvKey" entry in sources.',
      );
    }

    final headers = detectCsvHeaders(csvContent);
    for (final field in requiredGenericCsvFields) {
      final column = mapping.columnByField[field];
      if (column == null || !headers.contains(column)) {
        throw FormatException(
          'Mapping "${mapping.name}" requires a column for ${field.name}, '
          'but "${column ?? '(unmapped)'}" was not found among this '
          "file's headers.",
        );
      }
    }

    final rows = _parseCsvRows(csvContent);
    final canonicalRows = <CanonicalImportRow>[];
    final errors = <ImportRowError>[];

    for (var i = 0; i < rows.length; i++) {
      // +1 for 1-based, +1 to move past the header row itself.
      final sourceRowNumber = i + 2;
      final mapped = mapGenericCsvRow(rows[i], mapping);

      if (mapped.error != null) {
        errors.add(
          ImportRowError(rowNumber: sourceRowNumber, message: mapped.error!),
        );
        continue;
      }

      canonicalRows.add(
        CanonicalImportRow(
          sourceRowNumber: sourceRowNumber,
          flight: mapped.flight!,
          aircraft: mapped.aircraft!,
          unmappedFields: mapped.unmappedFields,
          reviewNotes: mapped.reviewNotes,
        ),
      );
    }

    return ImportParseResult(rows: canonicalRows, errors: errors);
  }
}
