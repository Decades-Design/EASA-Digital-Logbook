/// Generic-shaped export format info + a dispatch wrapper, so `lib/ui/`
/// never has to name a vendor or its exporter functions directly (#68 —
/// see `import_formats.dart`'s own note; the same leak applies on the
/// export side).
library;

import '../domain/model/calendar_date.dart';
import '../domain/projection/projection.dart';
import '../domain/repository/flight_read_repository.dart';
import 'foreflight/foreflight_exporter.dart';

/// #70: the export format is FAA-shaped CSV, unconditionally.
const String faaCsvExportFormatLabel = 'ForeFlight';

String buildFaaCsvExport({
  required List<FlightRecord> flights,
  required Projection faaProjection,
}) => exportForeFlightCsv(flights: flights, faaProjection: faaProjection);

String faaCsvExportFilename({
  required CalendarDate from,
  required CalendarDate to,
}) => foreFlightExportFilename(from: from, to: to);
