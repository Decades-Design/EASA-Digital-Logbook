import 'package:drift/drift.dart';

import '../../domain/projection/projection.dart';
import '../../domain/repository/flight_read_repository.dart';
import '../database.dart';
import '../mappers/flight_mapper.dart';
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
