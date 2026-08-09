import 'package:drift/drift.dart';

import '../../domain/model/calendar_date.dart';
import '../../domain/projection/projection.dart';
import '../../domain/repository/flight_read_repository.dart';
import '../database.dart';
import '../mappers/flight_mapper.dart';
import '../tables/flight_tables.dart';
import 'aircraft_repository.dart';

class DriftFlightReadRepository implements FlightReadRepository {
  DriftFlightReadRepository(this._db) : _aircraft = AircraftRepository(_db);

  final AppDatabase _db;
  final AircraftRepository _aircraft;

  @override
  Future<ProjectedFlight?> find(
    String flightId, {
    required Projection projection,
  }) async {
    final row = await (_db.select(_db.flightsTable)..where(
      (t) => t.id.equals(flightId) & t.committedAt.isNotNull(),
    )).getSingleOrNull();
    if (row == null) {
      return null;
    }
    return _projectedFromRow(row, projection);
  }

  @override
  Stream<List<ProjectedFlight>> watchFlights({
    required Projection projection,
    FlightQuery query = const FlightQuery(),
  }) {
    final statement = _db.select(_db.flightsTable)
      ..where((t) => t.committedAt.isNotNull() & t.tombstonedAt.isNull());

    if (query.aircraftId != null) {
      final aircraftId = query.aircraftId!;
      statement.where((t) => t.aircraftId.equals(aircraftId));
    }
    if (query.from != null) {
      final fromMs = _startOfDayUtcMs(query.from!);
      statement.where((t) => t.offBlocks.isBiggerOrEqualValue(fromMs));
    }
    if (query.to != null) {
      final toMs = _endOfDayUtcMs(query.to!);
      statement.where((t) => t.offBlocks.isSmallerOrEqualValue(toMs));
    }
    if (query.aerodromeIdentifier != null) {
      final identifier = query.aerodromeIdentifier!;
      statement.where(
        (t) =>
            existsQuery(
              _db.select(_db.flightRouteLegsTable)..where(
                (l) =>
                    l.flightId.equalsExp(t.id) &
                    l.identifier.equals(identifier),
              ),
            ) |
            existsQuery(
              _db.select(_db.flightApproachesTable)..where(
                (a) =>
                    a.flightId.equalsExp(t.id) &
                    a.aerodromeIcao.equals(identifier),
              ),
            ),
      );
    }
    if (query.capacity != null) {
      _applyCapacityFilter(statement, query.capacity!);
    }

    return statement.watch().asyncMap(
      (rows) async => [
        for (final row in rows) await _projectedFromRow(row, projection),
      ],
    );
  }

  void _applyCapacityFilter(
    SimpleSelectStatement<FlightsTable, FlightRow> statement,
    CapacityFilter filter,
  ) {
    if (filter.commandAuthority != null) {
      final value = filter.commandAuthority!;
      statement.where((t) => t.capacityCommandAuthority.equals(value));
    }
    if (filter.soleManipulator != null) {
      final value = filter.soleManipulator!;
      statement.where((t) => t.capacitySoleManipulator.equals(value));
    }
    if (filter.soleOccupant != null) {
      final value = filter.soleOccupant!;
      statement.where((t) => t.capacitySoleOccupant.equals(value));
    }
    if (filter.multiPilotOperation != null) {
      final value = filter.multiPilotOperation!;
      statement.where((t) => t.capacityMultiPilotOperation.equals(value));
    }
    if (filter.actingAsInstructor != null) {
      final value = filter.actingAsInstructor!;
      statement.where((t) => t.capacityActingAsInstructor.equals(value));
    }
    if (filter.actingAsExaminer != null) {
      final value = filter.actingAsExaminer!;
      statement.where((t) => t.capacityActingAsExaminer.equals(value));
    }
    if (filter.picusClaimed != null) {
      final value = filter.picusClaimed!;
      statement.where((t) => t.capacityPicusClaimed.equals(value));
    }
  }

  int _startOfDayUtcMs(CalendarDate date) =>
      DateTime.utc(date.year, date.month, date.day).millisecondsSinceEpoch;

  int _endOfDayUtcMs(CalendarDate date) => DateTime.utc(
    date.year,
    date.month,
    date.day,
    23,
    59,
    59,
    999,
  ).millisecondsSinceEpoch;

  @override
  Future<FlightRecord?> findDraft(String flightId) async {
    final row = await (_db.select(_db.flightsTable)..where(
      (t) => t.id.equals(flightId) & t.committedAt.isNull(),
    )).getSingleOrNull();
    if (row == null) {
      return null;
    }
    return _recordFromRow(row);
  }

  Future<ProjectedFlight> _projectedFromRow(
    FlightRow row,
    Projection projection,
  ) async {
    final record = await _recordFromRow(row);
    return ProjectedFlight(
      record: record,
      projection: projection.project(record.flight, record.aircraft),
    );
  }

  Future<FlightRecord> _recordFromRow(FlightRow row) async {
    final legs = await (_db.select(
      _db.flightRouteLegsTable,
    )..where((t) => t.flightId.equals(row.id))).get();
    final approaches = await (_db.select(
      _db.flightApproachesTable,
    )..where((t) => t.flightId.equals(row.id))).get();

    final aircraft = await _aircraft.find(row.aircraftId);
    if (aircraft == null) {
      throw StateError(
        'Flight ${row.id} references aircraft ${row.aircraftId}, which no '
        'longer exists',
      );
    }

    final flight = flightFromRow(
      row,
      legs,
      approaches,
      aircraftRegistration: aircraft.registration,
    );

    return FlightRecord(id: row.id, flight: flight, aircraft: aircraft);
  }
}
