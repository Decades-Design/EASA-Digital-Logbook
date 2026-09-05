import 'dart:convert';

import 'database.dart';

/// Reconstructs a flight row's state as of [asOfEpochMs]: starts from
/// [current] (plus [currentRoute]/[currentApproaches], when the caller has
/// them — a revision's `changedFields` can carry a `'route'` or
/// `'approaches'` key alongside the flat column ones, since those live in
/// child tables rather than on [FlightRow] itself; see
/// `DriftFlightRepository.updateCommitted`), then walks [revisions] newer
/// than [asOfEpochMs] in reverse chronological order, applying each
/// revision's old values back over the running result — an "undo" replay,
/// not a forward replay from creation. See the M2 design spec's
/// `flight_revisions` section.
///
/// Returns a plain string-keyed map, not a [FlightRow] or a domain
/// `Flight` — #60's revision history viewer converts the result the rest of
/// the way (via `FlightRow.fromJson` plus its own route/approaches
/// reconstruction) once it has an aircraft registration to attach.
Map<String, Object?> reconstructRowAsOf(
  FlightRow current,
  List<FlightRevisionRow> revisions,
  int asOfEpochMs, {
  List<String>? currentRoute,
  List<Map<String, Object?>>? currentApproaches,
}) {
  final result = current.toJson();
  if (currentRoute != null) result['route'] = currentRoute;
  if (currentApproaches != null) result['approaches'] = currentApproaches;

  final applicable = revisions.where((r) => r.recordedAt > asOfEpochMs).toList()
    ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));

  for (final revision in applicable) {
    final oldValues =
        jsonDecode(revision.changedFields) as Map<String, dynamic>;
    result.addAll(oldValues);
  }

  return result;
}
