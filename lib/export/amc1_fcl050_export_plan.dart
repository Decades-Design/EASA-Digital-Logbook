import '../domain/model/calendar_date.dart';
import '../domain/projection/projection.dart';
import '../domain/repository/flight_read_repository.dart';
import 'amc1_fcl050_row.dart';
import 'amc1_fcl050_row_mapper.dart';
import 'amc1_fcl050_totals.dart';

/// Everything the AMC1 FCL.050 export needs to read before it can render
/// or seal anything (#83) — shared by preview and the real, sealing
/// export, so what a pilot previews is exactly what sealing would
/// produce. Read-only: never writes anything.
class Amc1Fcl050ExportPlan {
  const Amc1Fcl050ExportPlan({
    required this.contentRows,
    required this.openingBalance,
    required this.draftFlightIds,
  });

  /// Every committed-or-about-to-be-committed flight in the requested
  /// range, sorted chronologically by offBlocks — what the PDF prints.
  final List<Amc1Fcl050Row> contentRows;

  /// The sum of every committed, non-tombstoned flight before the range
  /// — seeds [buildAmc1Fcl050Logbook]'s openingBalance so running totals
  /// continue across separate export runs.
  final Amc1Fcl050Totals openingBalance;

  /// Ids of the flights in range still draft — what
  /// [FlightRepository.sealForExport] must be called with to actually
  /// seal this export, and what the confirmation dialog counts.
  final List<String> draftFlightIds;

  int get draftCount => draftFlightIds.length;
}

/// Builds the plan for exporting [from]..[to] under [easaProjection].
/// Fetches every committed flight with no date filter (`FlightReadRepository`
/// has no one-shot "before a date" query — see its own dartdoc on
/// `watchFlights`/`watchDrafts` being streams), then filters client-side
/// by each flight's own offBlocks date, since `FlightQuery.from`/`to`
/// only expresses "in this range", not "before it".
Future<Amc1Fcl050ExportPlan> buildAmc1Fcl050ExportPlan({
  required FlightReadRepository flightReadRepository,
  required Projection easaProjection,
  required CalendarDate from,
  required CalendarDate to,
}) async {
  final allCommitted = await flightReadRepository
      .watchFlights(projection: easaProjection)
      .first;
  final allDrafts = await flightReadRepository.watchDrafts().first;

  final beforeRange = <({String id, Amc1Fcl050Row row, CalendarDate date})>[];
  final inRange = <({String id, Amc1Fcl050Row row, CalendarDate date})>[];

  for (final projected in allCommitted) {
    final flight = projected.record.flight;
    final date = CalendarDate.fromUtcInstant(flight.offBlocks);
    final row = buildAmc1Fcl050Row(
      flight: flight,
      aircraft: projected.record.aircraft,
      easaProjection: easaProjection,
    );
    if (date < from) {
      beforeRange.add((id: projected.record.id, row: row, date: date));
    } else if (date <= to) {
      inRange.add((id: projected.record.id, row: row, date: date));
    }
  }

  final draftFlightIds = <String>[];
  for (final record in allDrafts) {
    final date = CalendarDate.fromUtcInstant(record.flight.offBlocks);
    if (date < from || date > to) continue;
    final row = buildAmc1Fcl050Row(
      flight: record.flight,
      aircraft: record.aircraft,
      easaProjection: easaProjection,
    );
    inRange.add((id: record.id, row: row, date: date));
    draftFlightIds.add(record.id);
  }

  inRange.sort((a, b) => a.date.compareTo(b.date));

  return Amc1Fcl050ExportPlan(
    contentRows: [for (final entry in inRange) entry.row],
    openingBalance: Amc1Fcl050Totals.fromRows([
      for (final entry in beforeRange) entry.row,
    ]),
    draftFlightIds: draftFlightIds,
  );
}
