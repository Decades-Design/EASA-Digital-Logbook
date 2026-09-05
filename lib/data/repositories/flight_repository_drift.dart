import 'dart:convert';

import 'package:drift/drift.dart';

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

  @override
  Future<void> commit(String flightId) async {
    final current = await _requireRow(flightId);
    if (current.committedAt != null) {
      throw StateError('Flight $flightId is already committed');
    }
    await (_db.update(
      _db.flightsTable,
    )..where((t) => t.id.equals(flightId))).write(
      FlightsTableCompanion(
        committedAt: Value(DateTime.now().toUtc().millisecondsSinceEpoch),
      ),
    );
  }

  @override
  Future<void> updateCommitted(
    String flightId,
    Flight flight, {
    String? reason,
  }) {
    return _db.transaction(() async {
      final current = await _requireRow(flightId);
      if (current.committedAt == null) {
        throw StateError(
          'updateCommitted called on draft flight $flightId — use '
          'updateDraft instead',
        );
      }
      if (current.tombstonedAt != null) {
        throw StateError(
          'updateCommitted called on tombstoned flight $flightId — restore '
          'it first',
        );
      }

      final newRow = flightToRow(
        flight,
        id: flightId,
        aircraftId: current.aircraftId,
        committedAt: current.committedAt,
        tombstonedAt: current.tombstonedAt,
      );
      final changed = _diffRows(current, newRow);
      changed.addAll(await _diffChildren(flightId, flight));

      if (changed.isNotEmpty) {
        await _db
            .into(_db.flightRevisionsTable)
            .insert(
              FlightRevisionRow(
                id: generateUlid(),
                flightId: flightId,
                recordedAt: await _nextRevisionTimestamp(
                  flightId,
                  current.committedAt!,
                ),
                kind: 'edit',
                reason: reason,
                changedFields: jsonEncode(changed),
              ),
            );
      }

      await (_db.update(
        _db.flightsTable,
      )..where((t) => t.id.equals(flightId))).write(newRow);
      await _replaceChildren(flightId, flight);
    });
  }

  /// Route legs and approaches live in child tables, not on [FlightRow]
  /// itself, so `_diffRows` (which only compares [FlightsTable] columns)
  /// never sees them change — `updateCommitted` used to silently drop a
  /// route or approach edit from history entirely (nothing else consumed
  /// this data, so nothing failed, but a pilot's revision history would
  /// have omitted a real change). Returns the *old* route/approaches under
  /// `'route'`/`'approaches'` keys, matching `_diffRows`' "old value under
  /// the changed key" shape, only when they actually differ from
  /// [newFlight]'s.
  Future<Map<String, Object?>> _diffChildren(
    String flightId,
    Flight newFlight,
  ) async {
    final changed = <String, Object?>{};

    final oldLegs =
        await (_db.select(_db.flightRouteLegsTable)
              ..where((t) => t.flightId.equals(flightId)))
            .get();
    oldLegs.sort((a, b) => a.sequence.compareTo(b.sequence));
    final oldRoute = [for (final leg in oldLegs) leg.identifier];
    if (!_listEquals(oldRoute, newFlight.route)) {
      changed['route'] = oldRoute;
    }

    final oldApproachRows =
        await (_db.select(_db.flightApproachesTable)
              ..where((t) => t.flightId.equals(flightId)))
            .get();
    final oldApproaches = [
      for (final row in oldApproachRows)
        Approach(
          type: ApproachType.values.byName(row.type),
          aerodromeIcao: row.aerodromeIcao,
          runway: row.runway,
          count: row.count,
        ),
    ];
    if (!_listEquals(oldApproaches, newFlight.approaches)) {
      changed['approaches'] = [
        for (final approach in oldApproaches)
          {
            'type': approach.type.name,
            'aerodromeIcao': approach.aerodromeIcao,
            'runway': approach.runway,
            'count': approach.count,
          },
      ];
    }

    return changed;
  }

  @override
  Future<void> tombstone(String flightId, {String? reason}) {
    return _db.transaction(() async {
      final current = await _requireRow(flightId);
      if (current.committedAt == null) {
        throw StateError(
          'Cannot tombstone draft flight $flightId — delete it instead',
        );
      }
      if (current.tombstonedAt != null) {
        throw StateError('Flight $flightId is already tombstoned');
      }

      final recordedAt = await _nextRevisionTimestamp(
        flightId,
        current.committedAt!,
      );
      await _db
          .into(_db.flightRevisionsTable)
          .insert(
            FlightRevisionRow(
              id: generateUlid(),
              flightId: flightId,
              recordedAt: recordedAt,
              kind: 'tombstone',
              reason: reason,
              changedFields: jsonEncode(<String, Object?>{
                'tombstonedAt': null,
              }),
            ),
          );
      await (_db.update(
        _db.flightsTable,
      )..where((t) => t.id.equals(flightId))).write(
        FlightsTableCompanion(tombstonedAt: Value(recordedAt)),
      );
    });
  }

  @override
  Future<void> restore(String flightId, {String? reason}) {
    return _db.transaction(() async {
      final current = await _requireRow(flightId);
      if (current.tombstonedAt == null) {
        throw StateError('Flight $flightId is not tombstoned');
      }

      await _db
          .into(_db.flightRevisionsTable)
          .insert(
            FlightRevisionRow(
              id: generateUlid(),
              flightId: flightId,
              recordedAt: await _nextRevisionTimestamp(
                flightId,
                current.committedAt!,
              ),
              kind: 'restore',
              reason: reason,
              changedFields: jsonEncode(<String, Object?>{
                'tombstonedAt': current.tombstonedAt,
              }),
            ),
          );
      await (_db.update(_db.flightsTable)..where((t) => t.id.equals(flightId)))
          .write(const FlightsTableCompanion(tombstonedAt: Value(null)));
    });
  }

  /// Guarantees each flight's revision chain has strictly increasing
  /// `recordedAt` values, regardless of wall-clock resolution — two edits
  /// landing in the same millisecond (plausible: an in-memory test database
  /// has no real I/O latency between them, and even on-device two rapid
  /// saves aren't impossible) would otherwise tie, and `reconstructRowAsOf`
  /// depends on strict `>` ordering to tell revisions apart. Floors the
  /// current wall-clock time at one millisecond past whichever is later:
  /// [committedAt] or the flight's own latest revision.
  Future<int> _nextRevisionTimestamp(String flightId, int committedAt) async {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final latest =
        await (_db.select(_db.flightRevisionsTable)
              ..where((t) => t.flightId.equals(flightId))
              ..orderBy([(t) => OrderingTerm.desc(t.recordedAt)])
              ..limit(1))
            .getSingleOrNull();
    final floor = latest == null ? committedAt : latest.recordedAt;
    return now > floor ? now : floor + 1;
  }
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// Every column in [newRow] that differs from [oldRow], keyed by the Dart
/// field name (matching [FlightRow.toJson]'s default key casing), mapped to
/// [oldRow]'s value. `id` is never included — it cannot change.
Map<String, Object?> _diffRows(FlightRow oldRow, FlightRow newRow) {
  final oldJson = oldRow.toJson();
  final newJson = newRow.toJson();
  final changed = <String, Object?>{};
  for (final key in oldJson.keys) {
    if (key == 'id') {
      continue;
    }
    if (oldJson[key] != newJson[key]) {
      changed[key] = oldJson[key];
    }
  }
  return changed;
}
