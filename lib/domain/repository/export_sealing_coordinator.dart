import '../model/calendar_date.dart';

/// Atomically records an export and seals the draft flights it included —
/// #83's "either the PDF was produced and everything in it is sealed, or
/// neither" acceptance criterion.
///
/// [ExportRecordRepository.recordExport] and [FlightRepository.sealForExport]
/// are each independently transactional on their own table (the ledger row,
/// the flights it seals), but the original implementation called them
/// sequentially from the UI as two separate transactions: if `recordExport`
/// succeeded and `sealForExport` then threw, a stray ledger entry survived
/// with nothing actually sealed — not the single-transaction guarantee the
/// design spec called for. This composes both inside one database
/// transaction, so a failure in either half rolls back both.
abstract class ExportSealingCoordinator {
  /// Records an export of [format] covering [from]..[to], then seals every
  /// one of [draftFlightIds] as part of it. Returns the new export record's
  /// id. Throws and leaves no trace — no ledger row, no sealed flight — if
  /// sealing any flight id fails (e.g. an unknown id).
  Future<String> recordExportAndSeal({
    required String format,
    required CalendarDate from,
    required CalendarDate to,
    required List<String> draftFlightIds,
  });
}
