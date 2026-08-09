import 'dart:convert';

import 'database.dart';

/// Reconstructs a flight row's state as of [asOfEpochMs]: starts from
/// [current], then walks [revisions] newer than [asOfEpochMs] in reverse
/// chronological order, applying each revision's old values back over the
/// running result — an "undo" replay, not a forward replay from creation.
/// See the M2 design spec's `flight_revisions` section.
///
/// Returns a plain column-name-keyed map, not a [FlightRow] or a domain
/// `Flight` — turning this into either needs a read/query layer (#35),
/// which does not exist yet. This function only proves the replay algorithm
/// is correct; wiring it into a caller is future work.
Map<String, Object?> reconstructRowAsOf(
  FlightRow current,
  List<FlightRevisionRow> revisions,
  int asOfEpochMs,
) {
  final result = current.toJson();

  final applicable = revisions.where((r) => r.recordedAt > asOfEpochMs).toList()
    ..sort((a, b) => b.recordedAt.compareTo(a.recordedAt));

  for (final revision in applicable) {
    final oldValues =
        jsonDecode(revision.changedFields) as Map<String, dynamic>;
    result.addAll(oldValues);
  }

  return result;
}
