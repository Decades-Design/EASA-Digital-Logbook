/// Generic-shaped descriptions of the import formats needing a direct
/// [ImportAdapter] dispatch, so `lib/ui/` can present and drive them without
/// ever naming a vendor or its adapter class itself (#68: "never let a
/// vendor's field naming past `io/`" — a UI label or a bare `FooAdapter()`
/// call is exactly that kind of leak, not just a stored field). The generic
/// CSV format needs no entry here since its own screen never names a
/// vendor.
///
/// Update alongside `ImportAdapter.displayName` as adapters are added —
/// there is no registry yet listing them for this to read live.
library;

import 'foreflight/foreflight_adapter.dart';
import 'garmin/garmin_adapter.dart';
import 'import_adapter.dart';

/// An import format needing exactly one picked file.
class SingleFileImportFormat {
  const SingleFileImportFormat({
    required this.label,
    required this.subtitle,
    required this.dialogTitle,
    required this.parse,
  });

  final String label;
  final String subtitle;
  final String dialogTitle;
  final ImportParseResult Function(String source) parse;
}

/// An import format needing exactly two picked files, in a fixed order.
class TwoFileImportFormat {
  const TwoFileImportFormat({
    required this.label,
    required this.subtitle,
    required this.firstDialogTitle,
    required this.secondDialogTitle,
    required this.parse,
  });

  final String label;
  final String subtitle;
  final String firstDialogTitle;
  final String secondDialogTitle;
  final ImportParseResult Function(String first, String second) parse;
}

final SingleFileImportFormat foreFlightImportFormat = SingleFileImportFormat(
  label: 'ForeFlight',
  subtitle: 'logbook_template.csv',
  dialogTitle: 'Select logbook_template.csv',
  parse: (source) =>
      ForeFlightAdapter().parse({ForeFlightAdapter.logbookKey: source}),
);

final TwoFileImportFormat garminImportFormat = TwoFileImportFormat(
  label: 'Garmin Pilot',
  subtitle: 'Aircraft types + logbook CSV (two files)',
  firstDialogTitle: 'Select the aircraft-types export',
  secondDialogTitle: 'Select the logbook export',
  parse: (aircraftTypes, logEntries) => GarminAdapter().parse({
    GarminAdapter.aircraftTypesKey: aircraftTypes,
    GarminAdapter.logEntriesKey: logEntries,
  }),
);
