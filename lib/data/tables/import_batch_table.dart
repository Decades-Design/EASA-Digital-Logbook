import 'package:drift/drift.dart';

/// One row per import applied through `FlightRepository.applyImportBatch`
/// (#73) — CLAUDE.md's "every import is a transaction ... recorded as a
/// batch, undoable even after restart". Survives independently of the
/// flights it created: once every draft in a batch has been deleted by
/// `undoImportBatch`, this row is the only remaining record that the
/// import ever happened.
///
/// `undoneAt` is the whole batch's own undo marker, set once regardless of
/// how many of its flights were drafts (deleted) versus already committed
/// (tombstoned) — the per-flight outcome lives on those flights themselves
/// (`FlightsTable.tombstonedAt`, or gone entirely), not duplicated here.
@DataClassName('ImportBatchRow')
class ImportBatchesTable extends Table {
  @override
  String get tableName => 'import_batches';

  TextColumn get id => text()();

  /// A human-readable label for what was imported, e.g. an
  /// `ImportAdapter.displayName` — never a vendor identifier hardcoded in
  /// this file (`tool/check_io_vendor_leak.dart` only exempts `lib/io/`),
  /// always supplied by the caller.
  TextColumn get sourceLabel => text()();

  IntColumn get importedAt => integer()();
  IntColumn get undoneAt => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}
