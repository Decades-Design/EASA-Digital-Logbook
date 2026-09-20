import '../../domain/model/calendar_date.dart';
import '../../domain/repository/export_record_repository.dart';
import '../../domain/repository/export_sealing_coordinator.dart';
import '../../domain/repository/flight_repository.dart';
import '../database.dart';

/// Wraps [ExportRecordRepository.recordExport] and
/// [FlightRepository.sealForExport] in one `_db.transaction`, the same
/// nesting primitive `DriftFlightRepository.applyImportBatch` already uses
/// to compose several of its own single-table-transactional methods into one
/// all-or-nothing operation — drift runs a `transaction()` called from
/// inside an already-open one in that same outer transaction rather than
/// starting a second one, so a throw from either repository call rolls back
/// both the ledger insert and any partial sealing.
class DriftExportSealingCoordinator implements ExportSealingCoordinator {
  DriftExportSealingCoordinator(
    this._db,
    this._exportRecordRepository,
    this._flightRepository,
  );

  final AppDatabase _db;
  final ExportRecordRepository _exportRecordRepository;
  final FlightRepository _flightRepository;

  @override
  Future<String> recordExportAndSeal({
    required String format,
    required CalendarDate from,
    required CalendarDate to,
    required List<String> draftFlightIds,
  }) {
    return _db.transaction(() async {
      final exportRecordId = await _exportRecordRepository.recordExport(
        format: format,
        from: from,
        to: to,
      );
      await _flightRepository.sealForExport(
        flightIds: draftFlightIds,
        exportRecordId: exportRecordId,
      );
      return exportRecordId;
    });
  }
}
