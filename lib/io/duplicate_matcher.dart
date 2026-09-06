import '../domain/model/flight.dart';
import '../domain/model/utc_instant.dart';
import '../domain/repository/flight_read_repository.dart';
import 'canonical_import_row.dart';

/// How confident [findDuplicate] is that a candidate flight is the same
/// real flight as an existing one.
enum DuplicateConfidence {
  /// Same aircraft, identical route (every leg, in order) and identical
  /// block times to the minute. About as certain as two independently
  /// recorded flights can be.
  exact,

  /// Same aircraft, same departure and destination, and block times within
  /// the matcher's tolerance — plausibly the same flight recorded slightly
  /// differently by two sources (rounding, a dropped intermediate stop),
  /// but not identical enough to auto-skip without a look.
  likely,
}

/// One candidate duplicate found for an incoming flight, naming which
/// already-stored flight it plausibly repeats and why. Never used to *skip*
/// an import on its own (#75's own acceptance criteria: a per-row
/// skip/import choice, not a silent drop) — the preview step (#73) is
/// responsible for surfacing this to the pilot and defaulting the checkbox,
/// never for acting on it unattended.
class DuplicateMatch {
  const DuplicateMatch({
    required this.confidence,
    required this.existingFlightId,
    required this.reason,
  });

  /// [FlightRecord.id] of the existing flight this candidate plausibly
  /// repeats — a draft or a committed flight; the caller decides which
  /// pools to check by what it puts in [findDuplicate]'s `existingFlights`.
  final String existingFlightId;

  final DuplicateConfidence confidence;

  /// Plain-language explanation for the preview UI — CLAUDE.md's "never
  /// showing a red or green pill" spirit applied to duplicates: a pilot
  /// deciding whether to skip a row needs to know *why* it was flagged, not
  /// just that it was.
  final String reason;
}

/// Default tolerance for [DuplicateConfidence.likely] — wide enough to
/// absorb rounding and cross-vendor drift (a source logging to the nearest
/// minute versus one logging to the second, or a decimal-hours vendor
/// rounding a total differently), narrow enough that two genuinely distinct
/// same-day repeat flights (#75's own worked example: "two identical
/// circuits an hour apart") never collide with it.
const Duration _defaultTolerance = Duration(minutes: 5);

String _normalize(String value) => value.trim().toUpperCase();

bool _sameAircraft(Flight a, Flight b) =>
    _normalize(a.aircraftRegistration) == _normalize(b.aircraftRegistration);

bool _sameFullRoute(Flight a, Flight b) {
  if (a.route.length != b.route.length) return false;
  for (var i = 0; i < a.route.length; i++) {
    if (_normalize(a.route[i]) != _normalize(b.route[i])) return false;
  }
  return true;
}

bool _sameDepartureAndDestination(Flight a, Flight b) {
  if (a.route.isEmpty || b.route.isEmpty) return false;
  return _normalize(a.route.first) == _normalize(b.route.first) &&
      _normalize(a.route.last) == _normalize(b.route.last);
}

Duration _absoluteDifference(UtcInstant a, UtcInstant b) {
  final diff = a.difference(b);
  return diff.isNegative ? -diff : diff;
}

/// [DuplicateConfidence.exact] outranks [DuplicateConfidence.likely]
/// regardless of time difference — a closer-in-time `likely` match is still
/// a worse candidate than a byte-identical `exact` one.
int _confidenceRank(DuplicateConfidence confidence) =>
    confidence == DuplicateConfidence.exact ? 0 : 1;

/// Finds the best candidate duplicate for [candidate] among
/// [existingFlights] (typically a caller's combined drafts + committed
/// flights, pre-filtered to roughly the imported date range for
/// performance — this function does no filtering of its own), or `null`
/// when nothing plausibly matches.
///
/// Matching is keyed on aircraft, route and block times — #75's own
/// acceptance criteria — deliberately *not* on a separate "date" field
/// (`Flight` has none; a date is `offBlocks`'s UTC calendar date). Comparing
/// `offBlocks`/`onBlocks` directly, rather than pre-filtering by calendar
/// date, means a flight that crosses midnight Zulu and gets attributed to
/// different nominal dates by two sources still matches correctly.
///
/// [tolerance] governs [DuplicateConfidence.likely] only — [exact] always
/// requires identical route and block times, since "identical apart from
/// rounding" is exactly what [likely] is for.
DuplicateMatch? findDuplicate({
  required Flight candidate,
  required List<FlightRecord> existingFlights,
  Duration tolerance = _defaultTolerance,
}) {
  FlightRecord? bestMatch;
  DuplicateConfidence? bestConfidence;
  Duration? bestDistance;

  for (final existing in existingFlights) {
    final other = existing.flight;
    if (!_sameAircraft(candidate, other)) continue;

    final offBlocksDiff = _absoluteDifference(
      candidate.offBlocks,
      other.offBlocks,
    );
    final onBlocksDiff = _absoluteDifference(
      candidate.onBlocks,
      other.onBlocks,
    );

    DuplicateConfidence? confidence;
    if (_sameFullRoute(candidate, other) &&
        offBlocksDiff == Duration.zero &&
        onBlocksDiff == Duration.zero) {
      confidence = DuplicateConfidence.exact;
    } else if (_sameDepartureAndDestination(candidate, other) &&
        offBlocksDiff <= tolerance &&
        onBlocksDiff <= tolerance) {
      confidence = DuplicateConfidence.likely;
    }
    if (confidence == null) continue;

    final distance = offBlocksDiff + onBlocksDiff;
    final isBetter =
        bestConfidence == null ||
        _confidenceRank(confidence) < _confidenceRank(bestConfidence) ||
        (_confidenceRank(confidence) == _confidenceRank(bestConfidence) &&
            distance < bestDistance!);
    if (isBetter) {
      bestMatch = existing;
      bestConfidence = confidence;
      bestDistance = distance;
    }
  }

  if (bestMatch == null || bestConfidence == null) return null;

  final reason = bestConfidence == DuplicateConfidence.exact
      ? 'Same aircraft, route and block times as a flight already in your '
            'logbook.'
      : 'Same aircraft and departure/destination as a flight already in '
            'your logbook, with block times within '
            '${tolerance.inMinutes} minute(s) — likely the same flight, '
            'recorded slightly differently. Compare before deciding.';

  return DuplicateMatch(
    confidence: bestConfidence,
    existingFlightId: bestMatch.id,
    reason: reason,
  );
}

/// Runs [findDuplicate] for every row in [incoming] against the same
/// [existingFlights] pool, returning one result per row in the same order
/// — so a preview screen (#73) can zip `incoming` against the result to
/// pair each row with its verdict (`null` meaning "looks new").
///
/// This is the shape #75's "bulk actions for a wholly overlapping range"
/// criterion is built on: a preview screen offering "skip all duplicates"
/// is just filtering this list for non-null entries, not additional
/// matching logic — there is nothing file-level to detect here beyond what
/// each row's own match already says.
List<DuplicateMatch?> findDuplicates({
  required List<CanonicalImportRow> incoming,
  required List<FlightRecord> existingFlights,
  Duration tolerance = _defaultTolerance,
}) => [
  for (final row in incoming)
    findDuplicate(
      candidate: row.flight,
      existingFlights: existingFlights,
      tolerance: tolerance,
    ),
];
