import '../../domain/model/flight.dart';
import '../../domain/repository/flight_repository.dart';
import '../database.dart';
import '../mappers/flight_mapper.dart';
import '../ulid.dart';

class DriftFlightRepository implements FlightRepository {
  DriftFlightRepository(this._db);

  final AppDatabase _db;

  @override
  Future<String> createDraft(Flight flight, {required String aircraftId}) {
    final id = generateUlid();
    return _db.transaction(() async {
      await _db
          .into(_db.flightsTable)
          .insert(flightToRow(flight, id: id, aircraftId: aircraftId));
      await _writeChildren(id, flight);
      return id;
    });
  }

  @override
  Future<void> updateDraft(String flightId, Flight flight) {
    return _db.transaction(() async {
      final current = await _requireRow(flightId);
      if (current.committedAt != null) {
        throw StateError(
          'updateDraft called on committed flight $flightId — use '
          'updateCommitted instead',
        );
      }

      await (_db.update(
        _db.flightsTable,
      )..where((t) => t.id.equals(flightId))).write(
        flightToRow(flight, id: flightId, aircraftId: current.aircraftId),
      );
      await _replaceChildren(flightId, flight);
    });
  }

  @override
  Future<void> deleteDraft(String flightId) async {
    final current = await _requireRow(flightId);
    if (current.committedAt != null) {
      throw StateError(
        'deleteDraft called on committed flight $flightId — committed '
        'flights are tombstoned, never deleted',
      );
    }
    await (_db.delete(
      _db.flightsTable,
    )..where((t) => t.id.equals(flightId))).go();
  }

  Future<FlightRow> _requireRow(String flightId) async {
    final row = await (_db.select(
      _db.flightsTable,
    )..where((t) => t.id.equals(flightId))).getSingleOrNull();
    if (row == null) {
      throw StateError('No flight with id $flightId');
    }
    return row;
  }

  Future<void> _writeChildren(String flightId, Flight flight) async {
    for (final leg in flightRouteLegRows(flightId, flight)) {
      await _db.into(_db.flightRouteLegsTable).insert(leg);
    }
    for (final approach in flightApproachRows(flightId, flight)) {
      await _db.into(_db.flightApproachesTable).insert(approach);
    }
  }

  Future<void> _replaceChildren(String flightId, Flight flight) async {
    await (_db.delete(
      _db.flightRouteLegsTable,
    )..where((t) => t.flightId.equals(flightId))).go();
    await (_db.delete(
      _db.flightApproachesTable,
    )..where((t) => t.flightId.equals(flightId))).go();
    await _writeChildren(flightId, flight);
  }
}
